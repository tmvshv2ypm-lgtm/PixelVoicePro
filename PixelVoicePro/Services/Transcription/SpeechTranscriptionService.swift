import Foundation
import Speech
import AVFoundation

/// Configuración del motor híbrido de transcripción (Apple Speech en vivo + Whisper API / Local Post-Processing).
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

/// Servicio de Transcripción Inteligente en Español con sincronización palabra por palabra (`WordTimestamp`)
/// y soporte modular para modelos locales (`SFSpeechRecognizer` On-Device) y API compatible con Whisper.
final class SpeechTranscriptionService {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Palabras consolidadas de sesiones previas (para grabaciones largas de más de 1 minuto)
    private var committedWords: [WordTimestamp] = []
    /// Palabras de la ventana activa actual de `SFSpeechRecognizer`
    private var currentSessionWords: [WordTimestamp] = []
    private var sessionTimeOffset: TimeInterval = 0.0

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

    /// Inicia la transcripción en vivo recibiendo buffers desde `AVAudioEngine` y consultando el locutor activo en `diarizer`.
    func startLiveTranscription(diarizer: SpeakerDiarizationService) {
        stopLiveTranscription()
        committedWords.removeAll()
        currentSessionWords.removeAll()
        sessionTimeOffset = 0.0

        configureRecognizer(localeIdentifier: configuration.localeIdentifier)
        startRecognitionSession(diarizer: diarizer, offsetSeconds: 0.0)
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

                    // Conservar el speakerId ya asignado a esa palabra o consultar el diarizador acústico
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
                // Conservar las palabras ya reconocidas si la ventana de SFSpeechRecognizer rota
                if !self.currentSessionWords.isEmpty {
                    self.committedWords.append(contentsOf: self.currentSessionWords)
                    self.currentSessionWords.removeAll()
                }
            }
        }
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func stopLiveTranscription() {
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        if !currentSessionWords.isEmpty {
            committedWords.append(contentsOf: currentSessionWords)
            currentSessionWords.removeAll()
        }
    }

    /// Devuelve todas las palabras capturadas con sus marcas de tiempo y locutor asignado.
    var allCapturedWords: [WordTimestamp] {
        committedWords + currentSessionWords
    }

    // MARK: - Post-Procesamiento Inteligente (On-Device + Soporte Modular Whisper API)

    /// Ejecuta el post-procesamiento al finalizar la grabación:
    /// 1) Si el usuario activó un endpoint Whisper con API Key, consulta el modelo Whisper con granularidad por palabra.
    /// 2) Aplica refinamiento de puntuación en español, capitalización de inicio de oración y alineación con el diarizador.
    func postProcessRecording(
        audioFileURL: URL,
        existingWords: [WordTimestamp],
        diarizer: SpeakerDiarizationService,
        acousticEvents: [AcousticEvent]
    ) async -> (segments: [TranscriptSegment], engineDescription: String) {
        var finalWords = existingWords
        var engineLabel = "Apple Speech On-Device (es) + PixelVoice DSP Diarizer"

        // Si el usuario configuró Whisper API / Servidor Local Whisper
        if configuration.enableWhisperPostProcessing,
           !configuration.whisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let whisperWords = try? await transcribeWithWhisperEndpoint(audioFileURL: audioFileURL, diarizer: diarizer),
           !whisperWords.isEmpty {
            finalWords = whisperWords
            engineLabel = "Whisper AI (\(configuration.whisperModelName)) + PixelVoice DSP Diarizer"
        } else if finalWords.isEmpty {
            // Si no se capturaron palabras en vivo (ej. archivo importado), analizar archivo completo con SFSpeechURLRecognitionRequest
            if let fileWords = await transcribeAudioFileOffline(url: audioFileURL, diarizer: diarizer), !fileWords.isEmpty {
                finalWords = fileWords
            }
        }

        let refinedWords = refineSpanishCapitalizationAndPunctuation(words: finalWords)
        let segments = diarizer.buildSpeakerSegments(
            words: refinedWords,
            acousticEvents: acousticEvents
        )
        return (segments, engineLabel)
    }

    /// Transcribe un archivo de audio existente en disco usando `SFSpeechURLRecognitionRequest`.
    private func transcribeAudioFileOffline(url: URL, diarizer: SpeakerDiarizationService) async -> [WordTimestamp]? {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }

        return await withCheckedContinuation { continuation in
            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }
                if let result = result, result.isFinal {
                    hasResumed = true
                    let words: [WordTimestamp] = result.bestTranscription.segments.map { seg in
                        let start = seg.timestamp
                        let duration = max(0.2, seg.duration)
                        return WordTimestamp(
                            word: seg.substring,
                            startTime: start,
                            endTime: start + duration,
                            confidence: seg.confidence > 0 ? seg.confidence : 0.90,
                            speakerId: diarizer.speakerId(at: start)
                        )
                    }
                    continuation.resume(returning: words)
                } else if error != nil {
                    hasResumed = true
                    continuation.resume(returning: nil)
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

    /// Refina la capitalización al inicio de intervención de cada locutor y tras pausas largas.
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

            // Si la palabra siguiente es de otro locutor o es la última palabra y no tiene signo de puntuación final, añadir punto
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
