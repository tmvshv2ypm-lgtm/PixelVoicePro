import Foundation
import Speech
import AVFoundation

/// Configuración del motor híbrido de transcripción (Apple Speech en vivo + Post-procesamiento por fragmentos de 45s + Whisper API).
struct TranscriptionConfiguration: Codable {
    var localeIdentifier: String = "es-ES"
    var preferOnDeviceRecognition: Bool = true
    var enableWhisperPostProcessing: Bool = false
    var whisperEndpointURL: String = "https://api.openai.com/v1/audio/transcriptions"
    var whisperAPIKey: String = ""
    var whisperModelName: String = "whisper-1"

    static let storageKey = "com.pixelvoicepro.transcription.config"

    static func load() -> TranscriptionConfiguration {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(TranscriptionConfiguration.self, from: data) else {
            return TranscriptionConfiguration()
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// Servicio de Transcripción Inteligente en Español con sincronización palabra por palabra (`WordTimestamp`),
/// modo de ahorro de batería plegable en vivo y pipeline de post-procesamiento completo por fragmentos seguros de 45 segundos.
final class SpeechTranscriptionService {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

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

    func configureRecognizer(localeIdentifier: String) {
        if let primary = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) {
            speechRecognizer = primary
        } else if let fallbackES = SFSpeechRecognizer(locale: Locale(identifier: "es-419")) {
            speechRecognizer = fallbackES
        } else if let fallbackSpain = SFSpeechRecognizer(locale: Locale(identifier: "es-ES")) {
            speechRecognizer = fallbackSpain
        } else {
            speechRecognizer = SFSpeechRecognizer()
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

    /// Procesa el archivo de audio completo al finalizar la grabación:
    /// Divide automáticamente el audio en fragmentos seguros de 45 segundos para superar el límite de tiempo de `SFSpeechRecognizer`,
    /// alinea cada palabra con la diarización de locutores y los eventos acústicos, y reporta progreso en vivo.
    func postProcessRecording(
        audioFileURL: URL,
        totalDuration: TimeInterval,
        existingWords: [WordTimestamp],
        diarizer: SpeakerDiarizationService,
        acousticEvents: [AcousticEvent],
        onProgress: (@MainActor (Double, String) -> Void)? = nil
    ) async -> (segments: [TranscriptSegment], engineDescription: String) {
        var finalWords = existingWords
        var engineLabel = "Apple Speech On-Device (es) + PixelVoice 45s Chunk Pipeline"

        // Determinar cuánto de la grabación ya fue cubierto en vivo vs cuánto falta transcribir del archivo completo
        let lastCoveredSecond = existingWords.last?.endTime ?? 0.0
        let needsFullFileChunkAnalysis = existingWords.isEmpty || (totalDuration - lastCoveredSecond > 4.0)

        if configuration.enableWhisperPostProcessing,
           !configuration.whisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let whisperWords = try? await transcribeWithWhisperEndpoint(audioFileURL: audioFileURL, diarizer: diarizer),
           !whisperWords.isEmpty {
            finalWords = whisperWords
            engineLabel = "Whisper AI (\(configuration.whisperModelName)) + PixelVoice DSP Diarizer"
        } else if needsFullFileChunkAnalysis {
            await onProgress?(0.20, "Dividiendo audio en fragmentos seguros de 45s para transcripción completa...")
            let chunkedWords = await transcribeAudioFileIn45sChunks(
                url: audioFileURL,
                totalDuration: totalDuration,
                diarizer: diarizer,
                onProgress: onProgress
            )
            if !chunkedWords.isEmpty {
                finalWords = chunkedWords
            }
        }

        await onProgress?(0.92, "Alineando locutores, signos de puntuación y eventos acústicos...")
        let refinedWords = refineSpanishCapitalizationAndPunctuation(words: finalWords)
        let segments = diarizer.buildSpeakerSegments(
            words: refinedWords,
            acousticEvents: acousticEvents
        )
        await onProgress?(1.0, "¡Procesamiento completado!")
        return (segments, engineLabel)
    }

    /// Divide un archivo de audio de cualquier duración (ej. 2 minutos o 3 horas de clase) en fragmentos seguros de 45 segundos
    /// para evitar el límite de ~60s de `SFSpeechRecognizer` y transcribir el 100% del audio de principio a fin.
    private func transcribeAudioFileIn45sChunks(
        url: URL,
        totalDuration: TimeInterval,
        diarizer: SpeakerDiarizationService,
        onProgress: (@MainActor (Double, String) -> Void)?
    ) async -> [WordTimestamp] {
        configureRecognizer(localeIdentifier: configuration.localeIdentifier)
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return [] }
        guard let sourceFile = try? AVAudioFile(forReading: url) else { return [] }

        let format = sourceFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = sourceFile.length
        guard sampleRate > 0, totalFrames > 0 else { return [] }

        let chunkSeconds: TimeInterval = 45.0
        let framesPerChunk = AVAudioFramePosition(sampleRate * chunkSeconds)
        let totalChunks = max(1, Int(ceil(Double(totalFrames) / Double(framesPerChunk))))

        var accumulatedWords: [WordTimestamp] = []
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PixelVoiceChunks_\(UUID().uuidString.prefix(6))", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        for chunkIndex in 0..<totalChunks {
            let startFrame = AVAudioFramePosition(chunkIndex) * framesPerChunk
            let remainingFrames = totalFrames - startFrame
            guard remainingFrames > 0 else { break }

            let currentChunkFrames = min(framesPerChunk, remainingFrames)
            let chunkStartTimeOffset = Double(startFrame) / sampleRate

            let progressBase = 0.22 + (0.68 * (Double(chunkIndex) / Double(totalChunks)))
            await onProgress?(
                progressBase,
                "Transcribiendo fragmento \(chunkIndex + 1) de \(totalChunks) (\(ExactDateFormatter.standardDuration(chunkStartTimeOffset)))..."
            )

            // Extraer el fragmento de 45s a un archivo temporal .wav ligero para SFSpeechURLRecognitionRequest
            let chunkURL = tempDir.appendingPathComponent("chunk_\(chunkIndex).wav")
            if Self.extractPCMChunk(
                from: sourceFile,
                startFrame: startFrame,
                frameCount: currentChunkFrames,
                to: chunkURL
            ) {
                if let chunkWords = await recognizeSingleChunkURL(
                    chunkURL,
                    recognizer: recognizer,
                    timeOffset: chunkStartTimeOffset,
                    diarizer: diarizer
                ) {
                    accumulatedWords.append(contentsOf: chunkWords)
                }
                try? FileManager.default.removeItem(at: chunkURL)
            }
        }

        return accumulatedWords
    }

    private static func extractPCMChunk(
        from sourceFile: AVAudioFile,
        startFrame: AVAudioFramePosition,
        frameCount: AVAudioFramePosition,
        to destinationURL: URL
    ) -> Bool {
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
            return false
        }

        let bufferCapacity: AVAudioFrameCount = 16384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferCapacity) else {
            return false
        }

        sourceFile.framePosition = startFrame
        var framesRemaining = frameCount

        while framesRemaining > 0 {
            let framesToRead = AVAudioFrameCount(min(AVAudioFramePosition(bufferCapacity), framesRemaining))
            do {
                try sourceFile.read(into: buffer, frameCount: framesToRead)
                if buffer.frameLength == 0 { break }
                try destFile.write(from: buffer)
                framesRemaining -= AVAudioFramePosition(buffer.frameLength)
            } catch {
                break
            }
        }
        return true
    }

    private func recognizeSingleChunkURL(
        _ chunkURL: URL,
        recognizer: SFSpeechRecognizer,
        timeOffset: TimeInterval,
        diarizer: SpeakerDiarizationService
    ) async -> [WordTimestamp]? {
        let request = SFSpeechURLRecognitionRequest(url: chunkURL)
        request.shouldReportPartialResults = false
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        if configuration.preferOnDeviceRecognition && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return await withCheckedContinuation { continuation in
            var hasResumed = false
            var latestPartialWords: [WordTimestamp] = []

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
                    latestPartialWords = parsed

                    if result.isFinal && !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: parsed)
                    }
                } else if error != nil && !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: latestPartialWords.isEmpty ? nil : latestPartialWords)
                }
            }

            // Timeout de seguridad por fragmento para nunca bloquear el cierre
            DispatchQueue.global().asyncAfter(deadline: .now() + 25.0) {
                if !hasResumed {
                    hasResumed = true
                    task.cancel()
                    continuation.resume(returning: latestPartialWords)
                }
            }
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
        request.setValue("Bearer \(configuration.whisperAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "model", value: configuration.whisperModelName)
        appendField(name: "language", value: "es")
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

    private func refineSpanishCapitalizationAndPunctuation(words: [WordTimestamp]) -> [WordTimestamp] {
        guard !words.isEmpty else { return [] }
        var refined = words

        for i in refined.indices {
            var currentWord = refined[i].word
            let isFirstWord = (i == 0)
            let isSpeakerChange = (i > 0 && refined[i].speakerId != refined[i - 1].speakerId)
            let isAfterSentenceEnd = (i > 0 && (refined[i - 1].word.hasSuffix(".") || refined[i - 1].word.hasSuffix("?") || refined[i - 1].word.hasSuffix("!")))
            let isAfterLongGap = (i > 0 && (refined[i].startTime - refined[i - 1].endTime) >= 1.6)

            if isFirstWord || isSpeakerChange || isAfterSentenceEnd || isAfterLongGap {
                if let firstChar = currentWord.first {
                    currentWord = String(firstChar).uppercased() + currentWord.dropFirst()
                }
            }

            let isLastOfTurn = (i == refined.count - 1) || (refined[i + 1].speakerId != refined[i].speakerId)
            if isLastOfTurn,
               let lastChar = currentWord.last,
               ![Character("."), Character("?"), Character("!"), Character(","), Character(";"), Character(":")].contains(lastChar) {
                currentWord.append(".")
            }

            refined[i].word = currentWord
        }
        return refined
    }
}
