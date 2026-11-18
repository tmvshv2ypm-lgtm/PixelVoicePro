import Foundation
import Speech
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Estado real en tiempo de ejecución de Apple Intelligence (`FoundationModels`) según hardware, iOS y configuración del sistema.
enum AppleIntelligenceAvailabilityStatus: Equatable {
    case available
    case deviceNotEligible
    case notEnabledInSystem
    case modelDownloadingOrNotReady
    case unsupportedOSVersion

    var isAvailable: Bool {
        self == .available
    }

    var isHardwareEligible: Bool {
        switch self {
        case .available, .notEnabledInSystem, .modelDownloadingOrNotReady:
            return true
        case .deviceNotEligible, .unsupportedOSVersion:
            return false
        }
    }

    var localizedStatusMessage: String {
        switch self {
        case .available:
            return L10n.settingsAILocalAvailable
        case .deviceNotEligible:
            return L10n.settingsAILocalDeviceIneligible
        case .notEnabledInSystem:
            return L10n.settingsAILocalDisabledInSystem
        case .modelDownloadingOrNotReady:
            return L10n.settingsAILocalDownloading
        case .unsupportedOSVersion:
            return L10n.settingsAILocalOlderOS
        }
    }
}

/// Detector dinámico de capacidades de IA del iPhone/iPad actual sin fijar listas rígidas de dispositivos.
enum AdaptiveAICapability {
    static var appleIntelligenceStatus: AppleIntelligenceAvailabilityStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .deviceNotEligible
                case .appleIntelligenceNotEnabled:
                    return .notEnabledInSystem
                case .modelNotReady:
                    return .modelDownloadingOrNotReady
                @unknown default:
                    return .deviceNotEligible
                }
            }
        }
        #endif
        return .unsupportedOSVersion
    }

    static var isAppleIntelligenceAvailable: Bool {
        appleIntelligenceStatus.isAvailable
    }

    static var isModernSpeechAnalyzerAvailable: Bool {
        if #available(iOS 26.0, *) {
            return SpeechTranscriber.isAvailable
        }
        return false
    }

    static func canRunAIRefinement(config: TranscriptionConfiguration) -> Bool {
        let hasCloudKey = !config.resolvedAIChatAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || isLocalServerURL(config.aiChatEndpointURL)
        switch config.aiRefinementProvider {
        case .automatic:
            return isAppleIntelligenceAvailable || hasCloudKey
        case .appleIntelligenceLocal:
            return isAppleIntelligenceAvailable
        case .cloudOpenAICompatible:
            return hasCloudKey
        }
    }

    static func activeRefinementEngineLabel(for config: TranscriptionConfiguration) -> String {
        switch config.aiRefinementProvider {
        case .appleIntelligenceLocal:
            return L10n.aiEngineAppleIntelligence
        case .cloudOpenAICompatible:
            return L10n.aiEngineCloudLabel(config.aiChatModelName)
        case .automatic:
            if isAppleIntelligenceAvailable {
                return L10n.aiEngineAppleIntelligence
            }
            return L10n.aiEngineCloudLabel(config.aiChatModelName)
        }
    }

    static func isLocalServerURL(_ rawURL: String) -> Bool {
        let low = rawURL.lowercased()
        return low.contains("127.0.0.1") || low.contains("localhost") || low.contains("192.168.") || low.contains("10.")
    }
}

enum AIRefinementMode {
    case fixTranscriptOnly
    case generateSummaryOnly
    case fixTranscriptAndSummarize
}

struct IntelligentRefinementOutcome {
    var refinedSegments: [TranscriptSegment]?
    var summaryText: String?
    var engineUsed: String
}

/// Servicio adaptativo de post-procesamiento inteligente:
/// - Usa Apple `FoundationModels` local y offline gratis en iPhone 15 Pro / 16 / 17 Pro Max o iPad M1+.
/// - Usa API compatible OpenAI/Groq (por ejemplo `llama-3.3-70b-versatile` en capa gratuita) en modelos previos como iPhone 11 Pro Max.
final class IntelligentRefinementService {
    func refineRecording(
        segments: [TranscriptSegment],
        locale: Locale,
        config: TranscriptionConfiguration,
        mode: AIRefinementMode
    ) async throws -> IntelligentRefinementOutcome {
        guard !segments.isEmpty else {
            throw NSError(
                domain: "PixelVoicePro.AI",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: L10n.aiErrorNoTranscript]
            )
        }

        let targetLanguageName = SpeechTranscriptionService.localizedDisplayName(for: locale)
        let backend = try resolveBackend(for: config)

        var newSegments: [TranscriptSegment]?
        if mode == .fixTranscriptOnly || mode == .fixTranscriptAndSummarize {
            newSegments = try await polishSegments(
                segments,
                languageName: targetLanguageName,
                backend: backend,
                config: config
            )
        }

        var summary: String?
        if mode == .generateSummaryOnly || mode == .fixTranscriptAndSummarize {
            let sourceSegments = newSegments ?? segments
            summary = try await generateSummary(
                for: sourceSegments,
                languageName: targetLanguageName,
                backend: backend,
                config: config
            )
        }

        let engineLabel: String
        switch backend {
        case .appleIntelligence:
            engineLabel = L10n.aiEngineAppleIntelligence
        case .cloudAPI:
            engineLabel = L10n.aiEngineCloudLabel(config.aiChatModelName)
        }

        return IntelligentRefinementOutcome(
            refinedSegments: newSegments,
            summaryText: summary,
            engineUsed: engineLabel
        )
    }

    private enum ResolvedBackend {
        case appleIntelligence
        case cloudAPI
    }

    private func resolveBackend(for config: TranscriptionConfiguration) throws -> ResolvedBackend {
        let cloudReady = !config.resolvedAIChatAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || AdaptiveAICapability.isLocalServerURL(config.aiChatEndpointURL)

        switch config.aiRefinementProvider {
        case .appleIntelligenceLocal:
            guard AdaptiveAICapability.isAppleIntelligenceAvailable else {
                throw NSError(
                    domain: "PixelVoicePro.AI",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: L10n.aiErrorLocalHardware]
                )
            }
            return .appleIntelligence

        case .cloudOpenAICompatible:
            guard cloudReady else {
                throw NSError(
                    domain: "PixelVoicePro.AI",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: L10n.aiErrorMissingConfig]
                )
            }
            return .cloudAPI

        case .automatic:
            if AdaptiveAICapability.isAppleIntelligenceAvailable {
                return .appleIntelligence
            }
            if cloudReady {
                return .cloudAPI
            }
            throw NSError(
                domain: "PixelVoicePro.AI",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: L10n.aiErrorMissingConfig]
            )
        }
    }

    // MARK: - Pulido de Transcripción Preservando Tiempos Karaoke

    private func polishSegments(
        _ segments: [TranscriptSegment],
        languageName: String,
        backend: ResolvedBackend,
        config: TranscriptionConfiguration
    ) async throws -> [TranscriptSegment] {
        var updated = segments
        let batchCharLimit = (backend == .appleIntelligence) ? 1400 : 4200

        var startIdx = 0
        while startIdx < segments.count {
            var endIdx = startIdx
            var accumulatedChars = 0
            while endIdx < segments.count {
                let len = segments[endIdx].text.count + 24
                if endIdx > startIdx && accumulatedChars + len > batchCharLimit {
                    break
                }
                accumulatedChars += len
                endIdx += 1
            }

            let batch = Array(segments[startIdx..<endIdx])
            let numberedInput = batch.enumerated().map { idx, seg in
                "[\(idx)] \(seg.text)"
            }.joined(separator: "\n")

            let instructions = """
            You are an expert transcription editor for voice notes in \(languageName).
            Fix only punctuation, capitalization, sentence boundaries, and obvious speech-to-text recognition mistakes using surrounding context.
            Keep the exact meaning, keep the language as \(languageName), and return ONLY the lines in the exact format `[index] corrected text` with every original index preserved on its own line.
            Do not add explanations or extra text.
            """

            let prompt = """
            Correct punctuation and speech-to-text typos in these transcript segments:

            \(numberedInput)
            """

            let response = try await runPrompt(
                instructions: instructions,
                prompt: prompt,
                backend: backend,
                config: config
            )

            let parsedLines = parseIndexedLines(from: response, expectedCount: batch.count)
            for localIdx in 0..<batch.count {
                guard let cleanedText = parsedLines[localIdx]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !cleanedText.isEmpty else {
                    continue
                }
                let globalIdx = startIdx + localIdx
                updated[globalIdx] = realignSegment(updated[globalIdx], withCleanedText: cleanedText)
            }

            startIdx = endIdx
        }

        return updated
    }

    private func parseIndexedLines(from response: String, expectedCount: Int) -> [Int: String] {
        var result: [Int: String] = [:]
        for rawLine in response.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("["),
                  let closeIdx = trimmed.firstIndex(of: "]") else { continue }
            let idxStr = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeIdx])
            guard let idx = Int(idxStr), idx >= 0, idx < expectedCount else { continue }
            let body = String(trimmed[trimmed.index(after: closeIdx)...]).trimmingCharacters(in: .whitespaces)
            if !body.isEmpty {
                result[idx] = body
            }
        }
        return result
    }

    private func realignSegment(_ segment: TranscriptSegment, withCleanedText cleaned: String) -> TranscriptSegment {
        let newTokens = L10n.tokenizeSampleSentence(cleaned)
        guard !newTokens.isEmpty else { return segment }

        let oldWords = segment.words
        let segStart = segment.startTime
        let segEnd = max(segStart + 0.3, segment.endTime)

        var newWordTimestamps: [WordTimestamp] = []
        if newTokens.count == oldWords.count {
            for (token, oldWord) in zip(newTokens, oldWords) {
                newWordTimestamps.append(
                    WordTimestamp(
                        word: token,
                        startTime: oldWord.startTime,
                        endTime: oldWord.endTime,
                        confidence: oldWord.confidence,
                        speakerId: segment.speakerId
                    )
                )
            }
        } else {
            let step = (segEnd - segStart) / Double(newTokens.count)
            for (idx, token) in newTokens.enumerated() {
                let s = segStart + (Double(idx) * step)
                let e = max(s + 0.14, segStart + (Double(idx + 1) * step))
                newWordTimestamps.append(
                    WordTimestamp(
                        word: token,
                        startTime: s,
                        endTime: e,
                        confidence: 0.94,
                        speakerId: segment.speakerId
                    )
                )
            }
        }

        return TranscriptSegment(
            id: segment.id,
            speakerId: segment.speakerId,
            startTime: segStart,
            endTime: segEnd,
            text: L10n.smartJoinWords(newWordTimestamps.map(\.word)),
            words: newWordTimestamps,
            inlineEvents: segment.inlineEvents
        )
    }

    // MARK: - Generación de Resumen y Puntos Clave

    private func generateSummary(
        for segments: [TranscriptSegment],
        languageName: String,
        backend: ResolvedBackend,
        config: TranscriptionConfiguration
    ) async throws -> String {
        let fullText = segments.map(\.text).joined(separator: "\n")
        let maxChars = (backend == .appleIntelligence) ? 5500 : 18000

        let condensedInput: String
        if fullText.count <= maxChars {
            condensedInput = fullText
        } else if backend == .appleIntelligence {
            // Para sesiones muy largas en modelo local (~3B), resumir por bloques y sintetizar
            var partials: [String] = []
            var offset = fullText.startIndex
            while offset < fullText.endIndex {
                let end = fullText.index(offset, offsetBy: 4500, limitedBy: fullText.endIndex) ?? fullText.endIndex
                let slice = String(fullText[offset..<end])
                let partSummary = try await runPrompt(
                    instructions: "Summarize this transcript excerpt concisely in \(languageName) with bullet points.",
                    prompt: slice,
                    backend: backend,
                    config: config
                )
                partials.append(partSummary)
                offset = end
            }
            condensedInput = String(partials.joined(separator: "\n\n").prefix(5500))
        } else {
            condensedInput = String(fullText.prefix(maxChars))
        }

        let instructions = """
        You are an assistant that summarizes voice notes in \(languageName).
        Write strictly in \(languageName).
        Organize the output cleanly into:
        - A concise 2-sentence overview
        - Key points (bullet list)
        - Action items or next steps (only if applicable)
        Keep it clear, accurate, and grounded only in the transcript.
        """

        let prompt = """
        Summarize the following voice note transcript:

        \(condensedInput)
        """

        return try await runPrompt(
            instructions: instructions,
            prompt: prompt,
            backend: backend,
            config: config
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Ejecución Unificada (Apple Intelligence vs Cloud OpenAI/Groq)

    private func runPrompt(
        instructions: String,
        prompt: String,
        backend: ResolvedBackend,
        config: TranscriptionConfiguration
    ) async throws -> String {
        switch backend {
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                return response.content
            }
            #endif
            throw NSError(
                domain: "PixelVoicePro.AI",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: L10n.aiErrorLocalHardware]
            )

        case .cloudAPI:
            return try await callOpenAICompatibleChat(
                instructions: instructions,
                prompt: prompt,
                config: config
            )
        }
    }

    private func callOpenAICompatibleChat(
        instructions: String,
        prompt: String,
        config: TranscriptionConfiguration
    ) async throws -> String {
        guard let url = URL(string: config.aiChatEndpointURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw URLError(.badURL)
        }

        let apiKey = config.resolvedAIChatAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        struct ChatRequest: Encodable {
            struct Message: Encodable {
                let role: String
                let content: String
            }
            let model: String
            let temperature: Double
            let messages: [Message]
        }

        let payload = ChatRequest(
            model: config.aiChatModelName,
            temperature: 0.2,
            messages: [
                .init(role: "system", content: instructions),
                .init(role: "user", content: prompt)
            ]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            let serverMsg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(
                domain: "PixelVoicePro.AI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(String(serverMsg.prefix(220)))"]
            )
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }
}
