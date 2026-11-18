import Foundation
import Speech
import AVFoundation
import CoreMedia
import Accelerate

/// Configuración del motor híbrido de transcripción (Apple Speech / SpeechAnalyzer iOS 26+ + Post-procesamiento + Whisper / IA Adaptativa).
struct TranscriptionConfiguration: Codable {
    enum AcousticSensitivityLevel: String, Codable, CaseIterable, Identifiable {
        case conservative = "conservative"
        case balanced = "balanced"
        case high = "high"

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .conservative: return L10n.acousticSensitivityConservative
            case .balanced:     return L10n.acousticSensitivityBalanced
            case .high:         return L10n.acousticSensitivityHigh
            }
        }
    }

    enum AIRefinementProviderPreference: String, Codable, CaseIterable, Identifiable {
        case automatic = "automatic"
        case appleIntelligenceLocal = "apple_local"
        case cloudOpenAICompatible = "cloud"

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .automatic:               return L10n.aiProviderAutomatic
            case .appleIntelligenceLocal:  return L10n.aiProviderAppleLocal
            case .cloudOpenAICompatible:   return L10n.aiProviderCloud
            }
        }
    }

    static let automaticLocaleIdentifier = "auto"

    var localeIdentifier: String = TranscriptionConfiguration.automaticLocaleIdentifier
    var preferOnDeviceRecognition: Bool = true
    var useModernSpeechAnalyzer: Bool = true
    var acousticSensitivity: AcousticSensitivityLevel = .balanced

    var enableWhisperPostProcessing: Bool = false
    var whisperEndpointURL: String = "https://api.openai.com/v1/audio/transcriptions"
    var whisperAPIKey: String = ""
    var whisperModelName: String = "whisper-1"

    var enableAIRefinementOnFinish: Bool = false
    var aiRefinementProvider: AIRefinementProviderPreference = .automatic
    var aiChatEndpointURL: String = "https://api.groq.com/openai/v1/chat/completions"
    var aiChatModelName: String = "llama-3.3-70b-versatile"
    var aiChatAPIKey: String = ""

    static let storageKey = "com.pixelvoicepro.transcription.config"
    private static let autoLocaleMigrationKey = "com.pixelvoicepro.transcription.migratedAutoLocale.v1"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        localeIdentifier = try c.decodeIfPresent(String.self, forKey: .localeIdentifier) ?? Self.automaticLocaleIdentifier
        preferOnDeviceRecognition = try c.decodeIfPresent(Bool.self, forKey: .preferOnDeviceRecognition) ?? true
        useModernSpeechAnalyzer = try c.decodeIfPresent(Bool.self, forKey: .useModernSpeechAnalyzer) ?? true
        acousticSensitivity = try c.decodeIfPresent(AcousticSensitivityLevel.self, forKey: .acousticSensitivity) ?? .balanced
        enableWhisperPostProcessing = try c.decodeIfPresent(Bool.self, forKey: .enableWhisperPostProcessing) ?? false
        whisperEndpointURL = try c.decodeIfPresent(String.self, forKey: .whisperEndpointURL) ?? "https://api.openai.com/v1/audio/transcriptions"
        whisperAPIKey = try c.decodeIfPresent(String.self, forKey: .whisperAPIKey) ?? ""
        whisperModelName = try c.decodeIfPresent(String.self, forKey: .whisperModelName) ?? "whisper-1"
        enableAIRefinementOnFinish = try c.decodeIfPresent(Bool.self, forKey: .enableAIRefinementOnFinish) ?? false
        aiRefinementProvider = try c.decodeIfPresent(AIRefinementProviderPreference.self, forKey: .aiRefinementProvider) ?? .automatic
        aiChatEndpointURL = try c.decodeIfPresent(String.self, forKey: .aiChatEndpointURL) ?? "https://api.groq.com/openai/v1/chat/completions"
        aiChatModelName = try c.decodeIfPresent(String.self, forKey: .aiChatModelName) ?? "llama-3.3-70b-versatile"
        aiChatAPIKey = try c.decodeIfPresent(String.self, forKey: .aiChatAPIKey) ?? ""
    }

    var resolvedWhisperAPIKey: String {
        let direct = whisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }
        return aiChatAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedAIChatAPIKey: String {
        let direct = aiChatAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }
        return whisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func applyGroqFreePreset() {
        whisperEndpointURL = "https://api.groq.com/openai/v1/audio/transcriptions"
        whisperModelName = "whisper-large-v3-turbo"
        aiChatEndpointURL = "https://api.groq.com/openai/v1/chat/completions"
        aiChatModelName = "llama-3.3-70b-versatile"
        if aiRefinementProvider == .appleIntelligenceLocal && !AdaptiveAICapability.isAppleIntelligenceAvailable {
            aiRefinementProvider = .automatic
        }
    }

    static func load() -> TranscriptionConfiguration {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var decoded = try? JSONDecoder().decode(TranscriptionConfiguration.self, from: data) else {
            UserDefaults.standard.set(true, forKey: autoLocaleMigrationKey)
            return TranscriptionConfiguration()
        }
        // Migrar una sola vez configuraciones antiguas fijadas en "es-ES" al modo automático según el idioma del iPhone
        if !UserDefaults.standard.bool(forKey: autoLocaleMigrationKey) {
            UserDefaults.standard.set(true, forKey: autoLocaleMigrationKey)
            if decoded.localeIdentifier == "es-ES" {
                decoded.localeIdentifier = automaticLocaleIdentifier
                decoded.save()
            }
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// Servicio de Transcripción Inteligente Multi-idioma con sincronización palabra por palabra (`WordTimestamp`),
/// detección automática del idioma del dispositivo, modo ahorro plegable y pipeline de 45 segundos.
final class SpeechTranscriptionService {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private(set) var activeLocale: Locale = Locale.current

    /// Palabras consolidadas de sesiones previas
    private var committedWords: [WordTimestamp] = []
    /// Palabras de la ventana activa actual de `SFSpeechRecognizer`
    private var currentSessionWords: [WordTimestamp] = []
    private var sessionTimeOffset: TimeInterval = 0.0
    private(set) var isLiveRecognitionRunning: Bool = false

    var configuration: TranscriptionConfiguration = .load()

    /// Callback invocado en el hilo principal cada vez que se actualiza la lista de palabras transcritas en vivo
    var onLiveWordsUpdated: (([WordTimestamp]) -> Void)?

    init() {
        configureRecognizer(localeIdentifier: configuration.localeIdentifier)
    }

    /// Resuelve un identificador configurado (`"auto"` o código BCP-47) al `Locale` compatible con `SFSpeechRecognizer`.
    static func resolveRecognitionLocale(for configuredId: String) -> Locale {
        let supported = SFSpeechRecognizer.supportedLocales()
        if configuredId != TranscriptionConfiguration.automaticLocaleIdentifier {
            if let matched = matchSupportedLocale(for: configuredId, in: supported) {
                return matched
            }
            return Locale(identifier: configuredId)
        }

        for preferred in Locale.preferredLanguages {
            if let matched = matchSupportedLocale(for: preferred, in: supported) {
                return matched
            }
        }

        if let systemDefault = SFSpeechRecognizer()?.locale {
            return systemDefault
        }
        return Locale.current
    }

    static func activeLanguageDisplayName(for configuredId: String = TranscriptionConfiguration.load().localeIdentifier) -> String {
        let resolved = resolveRecognitionLocale(for: configuredId)
        return localizedDisplayName(for: resolved)
    }

    static func localizedDisplayName(for locale: Locale) -> String {
        let normalized = locale.identifier.replacingOccurrences(of: "_", with: "-")
        return Locale.current.localizedString(forIdentifier: normalized)?.localizedCapitalized ?? normalized
    }

    static func availableSpeechLocaleOptions() -> [(id: String, name: String)] {
        var seen: Set<String> = []
        var options: [(id: String, name: String)] = []
        for loc in SFSpeechRecognizer.supportedLocales() {
            let normId = loc.identifier.replacingOccurrences(of: "_", with: "-")
            guard !seen.contains(normId) else { continue }
            seen.insert(normId)
            options.append((id: normId, name: localizedDisplayName(for: loc)))
        }
        return options.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func matchSupportedLocale(for identifier: String, in supported: Set<Locale>) -> Locale? {
        guard !supported.isEmpty else { return nil }
        let normInput = identifier.replacingOccurrences(of: "_", with: "-").lowercased()

        // 1. Coincidencia exacta
        if let exact = supported.first(where: { $0.identifier.replacingOccurrences(of: "_", with: "-").lowercased() == normInput }) {
            return exact
        }

        let parsed = Locale(identifier: identifier)
        let langCode = parsed.language.languageCode?.identifier.lowercased()
            ?? normInput.split(separator: "-").first.map(String.init)
            ?? ""
        let scriptCode = parsed.language.script?.identifier
        let regionCode = parsed.region?.identifier.uppercased()

        guard !langCode.isEmpty else { return nil }

        // 2. Mapeo específico de Chino (zh-Hans -> zh-CN / zh-SG, zh-Hant -> zh-TW / zh-HK)
        if langCode == "zh" {
            let preferredChineseIDs: [String]
            if scriptCode == "Hant" || regionCode == "TW" || regionCode == "HK" || regionCode == "MO" {
                preferredChineseIDs = (regionCode == "HK" || regionCode == "MO")
                    ? ["zh-hk", "zh-tw", "zh-cn"]
                    : ["zh-tw", "zh-hk", "zh-cn"]
            } else {
                preferredChineseIDs = ["zh-cn", "zh-sg", "zh-tw", "zh-hk"]
            }
            for candidate in preferredChineseIDs {
                if let match = supported.first(where: { $0.identifier.replacingOccurrences(of: "_", with: "-").lowercased() == candidate }) {
                    return match
                }
            }
        }

        // 3. Coincidencia por idioma + región
        if let regionCode {
            if let langRegionMatch = supported.first(where: { loc in
                let locLang = loc.language.languageCode?.identifier.lowercased()
                let locReg = loc.region?.identifier.uppercased()
                return locLang == langCode && locReg == regionCode
            }) {
                return langRegionMatch
            }
        }

        // 4. Preferencias regionales naturales cuando el iPhone usa una región sin modelo propio
        let preferredFallbacksByLanguage: [String: [String]] = [
            "en": ["en-us", "en-gb"],
            "es": ["es-419", "es-es", "es-us", "es-mx"],
            "pt": ["pt-br", "pt-pt"],
            "fr": ["fr-fr", "fr-ca"],
            "de": ["de-de"],
            "it": ["it-it"],
            "ru": ["ru-ru"],
            "ko": ["ko-kr"],
            "ja": ["ja-jp"],
            "ar": ["ar-sa"],
            "hi": ["hi-in"],
            "uk": ["uk-ua"],
            "tr": ["tr-tr"],
            "nl": ["nl-nl"],
            "pl": ["pl-pl"]
        ]
        if let defaults = preferredFallbacksByLanguage[langCode] {
            for candidate in defaults {
                if let match = supported.first(where: { $0.identifier.replacingOccurrences(of: "_", with: "-").lowercased() == candidate }) {
                    return match
                }
            }
        }

        // 5. Cualquier locale soportado con el mismo código de idioma
        return supported
            .filter { $0.language.languageCode?.identifier.lowercased() == langCode }
            .sorted { $0.identifier < $1.identifier }
            .first
    }

    func configureRecognizer(localeIdentifier: String) {
        let resolved = Self.resolveRecognitionLocale(for: localeIdentifier)
        activeLocale = resolved
        if let recognizer = SFSpeechRecognizer(locale: resolved) {
            speechRecognizer = recognizer
        } else if let defaultRecognizer = SFSpeechRecognizer() {
            speechRecognizer = defaultRecognizer
            activeLocale = defaultRecognizer.locale
        } else {
            speechRecognizer = nil
        }
    }

    func resetCaptureBuffer() {
        stopLiveTranscription()
        committedWords.removeAll()
        currentSessionWords.removeAll()
        sessionTimeOffset = 0.0
    }

    /// Inicia o reanuda la transcripción en vivo desde el segundo `offsetSeconds`.
    func startLiveTranscription(diarizer: SpeakerDiarizationService, offsetSeconds: TimeInterval = 0.0) {
        stopLiveTranscription()
        configureRecognizer(localeIdentifier: configuration.localeIdentifier)
        startRecognitionSession(diarizer: diarizer, offsetSeconds: offsetSeconds)
    }

    private func startRecognitionSession(diarizer: SpeakerDiarizationService, offsetSeconds: TimeInterval) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        if configuration.preferOnDeviceRecognition && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        self.recognitionRequest = request
        self.sessionTimeOffset = offsetSeconds
        self.isLiveRecognitionRunning = true

        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                var parsedWords: [WordTimestamp] = []
                let existingByIndex = self.currentSessionWords

                for (idx, segment) in result.bestTranscription.segments.enumerated() {
                    let trimmedWord = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedWord.isEmpty else { continue }

                    let wordStart: TimeInterval
                    let wordDuration: TimeInterval
                    if segment.timestamp > 0 || idx == 0 {
                        wordStart = self.sessionTimeOffset + segment.timestamp
                        wordDuration = max(0.18, segment.duration)
                    } else if let previous = parsedWords.last {
                        wordStart = previous.endTime + 0.04
                        wordDuration = 0.28
                    } else {
                        wordStart = self.sessionTimeOffset
                        wordDuration = 0.28
                    }

                    let assignedSpeaker: String
                    if idx < existingByIndex.count && abs(existingByIndex[idx].startTime - wordStart) < 0.8 {
                        assignedSpeaker = existingByIndex[idx].speakerId
                    } else {
                        assignedSpeaker = diarizer.speakerId(at: wordStart)
                    }

                    let wordItem = WordTimestamp(
                        word: trimmedWord,
                        startTime: wordStart,
                        endTime: wordStart + wordDuration,
                        confidence: segment.confidence > 0 ? segment.confidence : 0.92,
                        speakerId: assignedSpeaker
                    )
                    parsedWords.append(wordItem)
                }

                self.currentSessionWords = parsedWords
                let allWords = self.committedWords + self.currentSessionWords

                DispatchQueue.main.async {
                    self.onLiveWordsUpdated?(allWords)
                }

                if result.isFinal {
                    self.committedWords.append(contentsOf: self.currentSessionWords)
                    self.currentSessionWords.removeAll()
                }
            }

            if error != nil {
                if !self.currentSessionWords.isEmpty {
                    self.committedWords.append(contentsOf: self.currentSessionWords)
                    self.currentSessionWords.removeAll()
                }
            }
        }
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isLiveRecognitionRunning else { return }
        recognitionRequest?.append(buffer)
    }

    /// Detiene el motor de reconocimiento en vivo para ahorrar RAM y batería durante clases largas, conservando lo ya transcrito.
    func stopLiveTranscription() {
        isLiveRecognitionRunning = false
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        if !currentSessionWords.isEmpty {
            committedWords.append(contentsOf: currentSessionWords)
            currentSessionWords.removeAll()
        }
    }

    var allCapturedWords: [WordTimestamp] {
        committedWords + currentSessionWords
    }

    // MARK: - Post-Procesamiento Completo por Fragmentos Seguros de 45 Segundos (Clases Largas)

    struct PostProcessOutcome: Sendable {
        let segments: [TranscriptSegment]
        let engineDescription: String
        let state: TranscriptionProcessingState
        let errorMessage: String
    }

    private struct ChunkBatchResult {
        let words: [WordTimestamp]
        let processedNonSilentChunks: Int
        let recognizerAvailable: Bool
        let fatalErrorsCount: Int
        let lastErrorMessage: String
        let wasCancelled: Bool
    }

    private struct ChunkRecognizeOutcome {
        let words: [WordTimestamp]
        let errorDescription: String?
        let isSystemFailure: Bool
    }

    /// Procesa el archivo de audio completo al finalizar la grabación:
    /// Filtra audios accidentales (< 3 s), omite silencios absolutos, divide audios largos en fragmentos seguros de 45s
    /// y reporta un estado final preciso (`.completed`, `.noSpeechFound`, `.tooShort`, `.interrupted`, `.failed`).
    func postProcessRecording(
        audioFileURL: URL,
        totalDuration: TimeInterval,
        existingWords: [WordTimestamp],
        diarizer: SpeakerDiarizationService,
        acousticEvents: [AcousticEvent],
        forceFullAnalysis: Bool = false,
        bypassShortAudioFilter: Bool = false,
        onProgress: (@MainActor (Double, String) -> Void)? = nil
    ) async -> PostProcessOutcome {
        configuration = .load()
        configureRecognizer(localeIdentifier: configuration.localeIdentifier)

        let physicalDuration = RecordingStorageService.queryAudioDuration(at: audioFileURL)
        let effectiveDuration = physicalDuration > 0 ? physicalDuration : totalDuration

        if !bypassShortAudioFilter && effectiveDuration < 3.0 {
            await onProgress?(1.0, L10n.transcriptionBadgeTooShort)
            return PostProcessOutcome(
                segments: [],
                engineDescription: L10n.transcriptionBadgeTooShort,
                state: .tooShort,
                errorMessage: ""
            )
        }

        if Task.isCancelled {
            return PostProcessOutcome(
                segments: [],
                engineDescription: L10n.transcriptionBadgeInterrupted,
                state: .interrupted,
                errorMessage: L10n.transcriptionErrorInterrupted
            )
        }

        var finalWords = existingWords
        let activeLocaleId = activeLocale.identifier.replacingOccurrences(of: "_", with: "-")
        let supportsOnDevice = speechRecognizer?.supportsOnDeviceRecognition ?? false
        var engineLabel = L10n.speechEngineApple(
            activeLocaleId,
            onDevice: configuration.preferOnDeviceRecognition && supportsOnDevice
        )

        let lastCoveredSecond = existingWords.last?.endTime ?? 0.0
        let needsClassicChunkAnalysis = forceFullAnalysis || existingWords.isEmpty || (effectiveDuration - lastCoveredSecond > 4.0)
        let whisperReady = configuration.enableWhisperPostProcessing
            && (!configuration.resolvedWhisperAPIKey.isEmpty || AdaptiveAICapability.isLocalServerURL(configuration.whisperEndpointURL))

        var chunkStats: ChunkBatchResult?
        var modernAttemptedAndAvailable = false
        var whisperAttemptedAndSucceeded = false

        if whisperReady {
            do {
                let whisperWords = try await transcribeWithWhisperEndpoint(audioFileURL: audioFileURL, diarizer: diarizer)
                if !whisperWords.isEmpty {
                    finalWords = whisperWords
                    engineLabel = "Whisper AI (\(configuration.whisperModelName)) + PixelVoice DSP"
                    whisperAttemptedAndSucceeded = true
                }
            } catch {
                // Continuar automáticamente al motor local de Apple si Whisper falla o el archivo excede límite
            }
        }

        if !whisperAttemptedAndSucceeded && !Task.isCancelled {
            if configuration.useModernSpeechAnalyzer,
               #available(iOS 26.0, *),
               SpeechTranscriber.isAvailable {
                modernAttemptedAndAvailable = true
                if let modernWords = await transcribeAudioFileWithSpeechAnalyzer(
                    url: audioFileURL,
                    diarizer: diarizer,
                    onProgress: onProgress
                ), !modernWords.isEmpty {
                    finalWords = modernWords
                    let resolvedId = activeLocale.identifier.replacingOccurrences(of: "_", with: "-")
                    engineLabel = L10n.speechEngineSpeechAnalyzer(resolvedId)
                }
            }

            if finalWords.isEmpty && needsClassicChunkAnalysis && !Task.isCancelled {
                await onProgress?(0.20, L10n.speechSplitting45s)
                let batch = await transcribeAudioFileIn45sChunks(
                    url: audioFileURL,
                    totalDuration: effectiveDuration,
                    diarizer: diarizer,
                    onProgress: onProgress
                )
                chunkStats = batch
                if !batch.words.isEmpty {
                    finalWords = batch.words
                }
            }
        }

        if Task.isCancelled || chunkStats?.wasCancelled == true {
            let partialSegments = finalWords.isEmpty ? [] : diarizer.buildSpeakerSegments(
                words: refineCapitalizationAndPunctuation(words: finalWords, locale: activeLocale),
                acousticEvents: acousticEvents
            )
            return PostProcessOutcome(
                segments: partialSegments,
                engineDescription: L10n.transcriptionBadgeInterrupted,
                state: .interrupted,
                errorMessage: L10n.transcriptionErrorInterrupted
            )
        }

        if finalWords.isEmpty {
            await onProgress?(1.0, L10n.speechCompleted)
            let stats = chunkStats
            let allFailed = (stats?.recognizerAvailable == false && !modernAttemptedAndAvailable)
                || ((stats?.fatalErrorsCount ?? 0) > 0 && (stats?.fatalErrorsCount ?? 0) >= max(1, stats?.processedNonSilentChunks ?? 0))

            if allFailed {
                let errText = (stats?.lastErrorMessage.isEmpty == false)
                    ? stats!.lastErrorMessage
                    : L10n.transcriptionErrorUnavailable
                return PostProcessOutcome(
                    segments: [],
                    engineDescription: L10n.transcriptionBadgeFailed,
                    state: .failed,
                    errorMessage: errText
                )
            }

            return PostProcessOutcome(
                segments: [],
                engineDescription: L10n.transcriptionBadgeNoSpeech,
                state: .noSpeechFound,
                errorMessage: ""
            )
        }

        await onProgress?(0.92, L10n.speechAligning)
        let refinedWords = refineCapitalizationAndPunctuation(words: finalWords, locale: activeLocale)
        let segments = diarizer.buildSpeakerSegments(
            words: refinedWords,
            acousticEvents: acousticEvents
        )
        await onProgress?(1.0, L10n.speechCompleted)
        return PostProcessOutcome(
            segments: segments,
            engineDescription: engineLabel,
            state: .completed,
            errorMessage: ""
        )
    }

    @available(iOS 26.0, *)
    private func transcribeAudioFileWithSpeechAnalyzer(
        url: URL,
        diarizer: SpeakerDiarizationService,
        onProgress: (@MainActor (Double, String) -> Void)?
    ) async -> [WordTimestamp]? {
        guard SpeechTranscriber.isAvailable else { return nil }
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: activeLocale) else {
            return nil
        }

        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        do {
            await onProgress?(0.28, L10n.aiRefineRunningReprocess)
            if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installationRequest.downloadAndInstall()
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let resultsTask = Task { () -> [WordTimestamp] in
                var collected: [WordTimestamp] = []
                do {
                    for try await result in transcriber.results {
                        guard result.isFinal else { continue }
                        Self.appendTimedWords(
                            from: result.text,
                            fallbackRange: result.range,
                            diarizer: diarizer,
                            into: &collected
                        )
                    }
                } catch {
                    return collected
                }
                return collected
            }

            await onProgress?(0.55, L10n.speechAligning)
            let audioFile = try AVAudioFile(forReading: url)
            do {
                _ = try await analyzer.analyzeSequence(from: audioFile)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                await analyzer.cancelAndFinishNow()
                resultsTask.cancel()
                return nil
            }

            let output = await resultsTask.value
            return output.isEmpty ? nil : output
        } catch {
            return nil
        }
    }

    @available(iOS 26.0, *)
    private static func appendTimedWords(
        from attributed: AttributedString,
        fallbackRange: CMTimeRange,
        diarizer: SpeakerDiarizationService,
        into words: inout [WordTimestamp]
    ) {
        let fbStart = (fallbackRange.isValid && !fallbackRange.isIndefinite) ? CMTimeGetSeconds(fallbackRange.start) : 0.0
        let fbDur = (fallbackRange.isValid && !fallbackRange.isIndefinite) ? CMTimeGetSeconds(fallbackRange.duration) : 0.3
        let safeFbStart = fbStart.isFinite ? max(0.0, fbStart) : 0.0
        let safeFbEnd = max(safeFbStart + 0.15, (fbDur.isFinite ? safeFbStart + fbDur : safeFbStart + 0.3))

        for run in attributed.runs {
            let rawPiece = String(attributed[run.range].characters)
            let tokens = rawPiece
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            guard !tokens.isEmpty else { continue }

            // Adjuntar signos de puntuación sueltos al token anterior en vez de crear píldoras vacías
            if tokens.count == 1,
               tokens[0].allSatisfy({ $0.isPunctuation }),
               !words.isEmpty {
                words[words.count - 1].word += tokens[0]
                continue
            }

            let cmRange = run.audioTimeRange ?? fallbackRange
            let rStartRaw = (cmRange.isValid && !cmRange.isIndefinite) ? CMTimeGetSeconds(cmRange.start) : safeFbStart
            let rDurRaw = (cmRange.isValid && !cmRange.isIndefinite) ? CMTimeGetSeconds(cmRange.duration) : (safeFbEnd - safeFbStart)
            let runStart = rStartRaw.isFinite ? max(0.0, rStartRaw) : safeFbStart
            let runDur = (rDurRaw.isFinite && rDurRaw > 0.05) ? rDurRaw : 0.25
            let runEnd = runStart + runDur

            let step = (runEnd - runStart) / Double(tokens.count)
            for (idx, token) in tokens.enumerated() {
                let s = runStart + (Double(idx) * step)
                let e = max(s + 0.12, runStart + (Double(idx + 1) * step))
                words.append(
                    WordTimestamp(
                        word: token,
                        startTime: s,
                        endTime: e,
                        confidence: 0.96,
                        speakerId: diarizer.speakerId(at: s)
                    )
                )
            }
        }
    }

    /// Divide un archivo de audio de cualquier duración (ej. 2 minutos o 5 horas de clase) en fragmentos seguros de 45 segundos
    /// para evitar el límite de ~60s de `SFSpeechRecognizer`, omitiendo silencios absolutos para acelerar la transcripción.
    private func transcribeAudioFileIn45sChunks(
        url: URL,
        totalDuration: TimeInterval,
        diarizer: SpeakerDiarizationService,
        onProgress: (@MainActor (Double, String) -> Void)?
    ) async -> ChunkBatchResult {
        configureRecognizer(localeIdentifier: configuration.localeIdentifier)
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            return ChunkBatchResult(
                words: [],
                processedNonSilentChunks: 0,
                recognizerAvailable: false,
                fatalErrorsCount: 1,
                lastErrorMessage: L10n.transcriptionErrorUnavailable,
                wasCancelled: false
            )
        }
        guard let sourceFile = try? AVAudioFile(forReading: url) else {
            return ChunkBatchResult(
                words: [],
                processedNonSilentChunks: 0,
                recognizerAvailable: true,
                fatalErrorsCount: 1,
                lastErrorMessage: L10n.transcriptionErrorReadFile,
                wasCancelled: false
            )
        }

        let format = sourceFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = sourceFile.length
        guard sampleRate > 0, totalFrames > 0 else {
            return ChunkBatchResult(
                words: [],
                processedNonSilentChunks: 0,
                recognizerAvailable: true,
                fatalErrorsCount: 0,
                lastErrorMessage: "",
                wasCancelled: false
            )
        }

        let chunkSeconds: TimeInterval = 45.0
        let framesPerChunk = AVAudioFramePosition(sampleRate * chunkSeconds)
        let totalChunks = max(1, Int(ceil(Double(totalFrames) / Double(framesPerChunk))))

        var accumulatedWords: [WordTimestamp] = []
        var processedNonSilent = 0
        var fatalErrors = 0
        var lastErrorMsg = ""

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PixelVoiceChunks_\(UUID().uuidString.prefix(6))", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        for chunkIndex in 0..<totalChunks {
            if Task.isCancelled {
                return ChunkBatchResult(
                    words: accumulatedWords,
                    processedNonSilentChunks: processedNonSilent,
                    recognizerAvailable: true,
                    fatalErrorsCount: fatalErrors,
                    lastErrorMessage: lastErrorMsg,
                    wasCancelled: true
                )
            }

            let startFrame = AVAudioFramePosition(chunkIndex) * framesPerChunk
            let remainingFrames = totalFrames - startFrame
            guard remainingFrames > 0 else { break }

            let currentChunkFrames = min(framesPerChunk, remainingFrames)
            let chunkStartTimeOffset = Double(startFrame) / sampleRate

            let progressBase = 0.22 + (0.68 * (Double(chunkIndex) / Double(totalChunks)))
            await onProgress?(
                progressBase,
                L10n.speechTranscribingChunk(
                    current: chunkIndex + 1,
                    total: totalChunks,
                    startTime: ExactDateFormatter.standardDuration(chunkStartTimeOffset)
                )
            )

            // Extraer el fragmento de 45s y medir pico de amplitud para saltar silencios absolutos en 0ms
            let chunkURL = tempDir.appendingPathComponent("chunk_\(chunkIndex).wav")
            let extracted = Self.extractPCMChunk(
                from: sourceFile,
                startFrame: startFrame,
                frameCount: currentChunkFrames,
                to: chunkURL
            )
            defer {
                try? FileManager.default.removeItem(at: chunkURL)
            }

            guard extracted.success else { continue }
            guard extracted.peakAmplitude >= 0.0028 else {
                // Silencio digital completo (<-51 dBFS) en este bloque de 45s: omitir sin consumir tiempo de reconocimiento
                continue
            }

            processedNonSilent += 1
            let chunkOutcome = await recognizeSingleChunkURL(
                chunkURL,
                recognizer: recognizer,
                timeOffset: chunkStartTimeOffset,
                diarizer: diarizer
            )
            if !chunkOutcome.words.isEmpty {
                accumulatedWords.append(contentsOf: chunkOutcome.words)
            } else if chunkOutcome.isSystemFailure {
                fatalErrors += 1
                if let errDesc = chunkOutcome.errorDescription, !errDesc.isEmpty {
                    lastErrorMsg = errDesc
                }
            }
        }

        return ChunkBatchResult(
            words: accumulatedWords,
            processedNonSilentChunks: processedNonSilent,
            recognizerAvailable: true,
            fatalErrorsCount: fatalErrors,
            lastErrorMessage: lastErrorMsg,
            wasCancelled: Task.isCancelled
        )
    }

    private static func extractPCMChunk(
        from sourceFile: AVAudioFile,
        startFrame: AVAudioFramePosition,
        frameCount: AVAudioFramePosition,
        to destinationURL: URL
    ) -> (success: Bool, peakAmplitude: Float) {
        let format = sourceFile.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        guard let destFile = try? AVAudioFile(
            forWriting: destinationURL,
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        ) else {
            return (false, 0.0)
        }

        let bufferCapacity: AVAudioFrameCount = 16384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferCapacity) else {
            return (false, 0.0)
        }

        sourceFile.framePosition = startFrame
        var framesRemaining = frameCount
        var peak: Float = 0.0

        while framesRemaining > 0 {
            let framesToRead = AVAudioFrameCount(min(AVAudioFramePosition(bufferCapacity), framesRemaining))
            do {
                try sourceFile.read(into: buffer, frameCount: framesToRead)
                if buffer.frameLength == 0 { break }
                if let ptr = buffer.floatChannelData?[0] {
                    var blockMax: Float = 0.0
                    vDSP_maxmgv(ptr, 1, &blockMax, vDSP_Length(buffer.frameLength))
                    if blockMax > peak { peak = blockMax }
                }
                try destFile.write(from: buffer)
                framesRemaining -= AVAudioFramePosition(buffer.frameLength)
            } catch {
                break
            }
        }
        return (true, peak)
    }

    private func recognizeSingleChunkURL(
        _ chunkURL: URL,
        recognizer: SFSpeechRecognizer,
        timeOffset: TimeInterval,
        diarizer: SpeakerDiarizationService
    ) async -> ChunkRecognizeOutcome {
        let request = SFSpeechURLRecognitionRequest(url: chunkURL)
        request.shouldReportPartialResults = false
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        if configuration.preferOnDeviceRecognition && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        final class SingleChunkStateHolder: @unchecked Sendable {
            let lock = NSLock()
            var hasResumed = false
            var task: SFSpeechRecognitionTask?
            var latestPartialWords: [WordTimestamp] = []
        }

        let holder = SingleChunkStateHolder()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                func finishOnce(_ outcome: ChunkRecognizeOutcome) {
                    holder.lock.lock()
                    defer { holder.lock.unlock() }
                    guard !holder.hasResumed else { return }
                    holder.hasResumed = true
                    continuation.resume(returning: outcome)
                }

                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result = result {
                        var parsed: [WordTimestamp] = []
                        for (idx, seg) in result.bestTranscription.segments.enumerated() {
                            let trimmed = seg.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { continue }

                            let start: TimeInterval
                            let dur: TimeInterval
                            if seg.timestamp > 0 || idx == 0 {
                                start = timeOffset + seg.timestamp
                                dur = max(0.2, seg.duration)
                            } else if let prev = parsed.last {
                                start = prev.endTime + 0.04
                                dur = 0.25
                            } else {
                                start = timeOffset
                                dur = 0.25
                            }

                            parsed.append(
                                WordTimestamp(
                                    word: trimmed,
                                    startTime: start,
                                    endTime: start + dur,
                                    confidence: seg.confidence > 0 ? seg.confidence : 0.92,
                                    speakerId: diarizer.speakerId(at: start)
                                )
                            )
                        }
                        holder.lock.lock()
                        holder.latestPartialWords = parsed
                        holder.lock.unlock()

                        if result.isFinal {
                            finishOnce(ChunkRecognizeOutcome(words: parsed, errorDescription: nil, isSystemFailure: false))
                        }
                    } else if let error = error {
                        holder.lock.lock()
                        let partials = holder.latestPartialWords
                        holder.lock.unlock()

                        let nsError = error as NSError
                        // Código 1110 de kAFAssistantErrorDomain significa "No se detectó habla" (no es un error fatal de red/motor)
                        let isNoSpeechNotice = (nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110)
                            || nsError.localizedDescription.lowercased().contains("no speech detected")
                        finishOnce(
                            ChunkRecognizeOutcome(
                                words: partials,
                                errorDescription: isNoSpeechNotice ? nil : nsError.localizedDescription,
                                isSystemFailure: !isNoSpeechNotice && partials.isEmpty
                            )
                        )
                    }
                }

                holder.lock.lock()
                holder.task = task
                holder.lock.unlock()

                // Timeout de seguridad por fragmento para nunca bloquear una nota larga
                DispatchQueue.global().asyncAfter(deadline: .now() + 25.0) {
                    holder.lock.lock()
                    let partials = holder.latestPartialWords
                    let currentTask = holder.task
                    holder.lock.unlock()
                    currentTask?.cancel()
                    finishOnce(ChunkRecognizeOutcome(words: partials, errorDescription: nil, isSystemFailure: false))
                }
            }
        } onCancel: {
            holder.lock.lock()
            let currentTask = holder.task
            holder.lock.unlock()
            currentTask?.cancel()
        }
    }

    /// Cliente HTTP multiparte compatible con OpenAI Whisper API (`verbose_json` con timestamps por palabra).
    private func transcribeWithWhisperEndpoint(audioFileURL: URL, diarizer: SpeakerDiarizationService) async throws -> [WordTimestamp] {
        guard let endpoint = URL(string: configuration.whisperEndpointURL) else {
            throw URLError(.badURL)
        }
        let audioData = try Data(contentsOf: audioFileURL)
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        let whisperKey = configuration.resolvedWhisperAPIKey
        if !whisperKey.isEmpty {
            request.setValue("Bearer \(whisperKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "model", value: configuration.whisperModelName)
        if configuration.localeIdentifier != TranscriptionConfiguration.automaticLocaleIdentifier,
           let langCode = activeLocale.language.languageCode?.identifier,
           !langCode.isEmpty {
            appendField(name: "language", value: langCode)
        }
        appendField(name: "response_format", value: "verbose_json")
        appendField(name: "timestamp_granularities[]", value: "word")

        let filename = audioFileURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct WhisperVerboseResponse: Decodable {
            struct WhisperWord: Decodable {
                let word: String
                let start: Double
                let end: Double
            }
            let text: String?
            let words: [WhisperWord]?
        }

        let decoded = try JSONDecoder().decode(WhisperVerboseResponse.self, from: responseData)
        guard let whisperWords = decoded.words, !whisperWords.isEmpty else {
            return []
        }

        return whisperWords.map { item in
            let spk = diarizer.speakerId(at: item.start)
            return WordTimestamp(
                word: item.word.trimmingCharacters(in: .whitespacesAndNewlines),
                startTime: item.start,
                endTime: max(item.end, item.start + 0.18),
                confidence: 0.96,
                speakerId: spk
            )
        }
    }

    private func refineCapitalizationAndPunctuation(words: [WordTimestamp], locale: Locale) -> [WordTimestamp] {
        guard !words.isEmpty else { return [] }
        var refined = words
        let langCode = locale.language.languageCode?.identifier.lowercased() ?? ""
        let cjkEndPunctuationLanguages: Set<String> = ["zh", "ja"]
        let skipForcedPeriodLanguages: Set<String> = ["th"]
        let sentenceTerminators: Set<Character> = [".", "?", "!", "。", "？", "！", "…"]
        let allTrailingPunctuation: Set<Character> = [".", "?", "!", ",", ";", ":", "。", "？", "！", "，", "、", "：", "；", "…"]

        for i in refined.indices {
            var currentWord = refined[i].word
            let isFirstWord = (i == 0)
            let isSpeakerChange = (i > 0 && refined[i].speakerId != refined[i - 1].speakerId)
            let isAfterSentenceEnd = (i > 0 && refined[i - 1].word.last.map { sentenceTerminators.contains($0) } == true)
            let isAfterLongGap = (i > 0 && (refined[i].startTime - refined[i - 1].endTime) >= 1.6)

            if isFirstWord || isSpeakerChange || isAfterSentenceEnd || isAfterLongGap {
                if let firstChar = currentWord.first {
                    currentWord = String(firstChar).uppercased(with: locale) + currentWord.dropFirst()
                }
            }

            let isLastOfTurn = (i == refined.count - 1) || (refined[i + 1].speakerId != refined[i].speakerId)
            if isLastOfTurn,
               !skipForcedPeriodLanguages.contains(langCode),
               let lastChar = currentWord.last,
               !allTrailingPunctuation.contains(lastChar) {
                currentWord.append(cjkEndPunctuationLanguages.contains(langCode) ? "。" : ".")
            }

            refined[i].word = currentWord
        }
        return refined
    }
}
