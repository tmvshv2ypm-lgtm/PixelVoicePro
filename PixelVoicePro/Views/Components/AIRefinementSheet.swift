import SwiftUI

/// Panel interactivo de post-procesamiento bajo demanda:
/// 1) Re-analiza el audio completo con SpeechAnalyzer / Whisper + SoundAnalysis (risas, suspiros, pausas).
/// 2) Refina puntuación, claridad o genera resumen inteligente adaptándose al hardware (Apple Intelligence local o IA en nube).
struct AIRefinementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel
    let recording: VoiceRecording

    @State private var config: TranscriptionConfiguration = .load()
    @State private var isRunning: Bool = false
    @State private var progressMessage: String = ""
    @State private var resultBanner: String?
    @State private var errorMessage: String?

    private var appleAIStatus: AppleIntelligenceAvailabilityStatus {
        AdaptiveAICapability.appleIntelligenceStatus
    }

    private var canRunLLMRefinement: Bool {
        AdaptiveAICapability.canRunAIRefinement(config: config)
    }

    private var activeSpeechEngineName: String {
        if config.enableWhisperPostProcessing,
           (!config.resolvedWhisperAPIKey.isEmpty || AdaptiveAICapability.isLocalServerURL(config.whisperEndpointURL)) {
            return "Whisper AI (\(config.whisperModelName))"
        }
        let resolvedLocale = SpeechTranscriptionService.resolveRecognitionLocale(for: config.localeIdentifier)
        let localeId = resolvedLocale.identifier.replacingOccurrences(of: "_", with: "-")
        if config.useModernSpeechAnalyzer && AdaptiveAICapability.isModernSpeechAnalyzerAvailable {
            return L10n.speechEngineSpeechAnalyzer(localeId)
        }
        return L10n.speechEngineApple(localeId, onDevice: config.preferOnDeviceRecognition)
    }

    private var activeLLMEngineName: String {
        AdaptiveAICapability.activeRefinementEngineLabel(for: config)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.aiRefineDeviceCapabilities) {
                    capabilityRow(
                        icon: "waveform.and.mic",
                        title: "SpeechAnalyzer (iOS 26+)",
                        subtitle: AdaptiveAICapability.isModernSpeechAnalyzerAvailable
                            ? L10n.settingsSpeechModernEngineReady
                            : L10n.settingsSpeechModernEngineFallback,
                        tint: AdaptiveAICapability.isModernSpeechAnalyzerAvailable ? .green : .orange,
                        enabled: AdaptiveAICapability.isModernSpeechAnalyzerAvailable
                    )

                    capabilityRow(
                        icon: "sparkles",
                        title: L10n.settingsAILocalToggle,
                        subtitle: appleAIStatus.localizedStatusMessage,
                        tint: appleAIStatus.isAvailable ? .green : .secondary,
                        enabled: appleAIStatus.isHardwareEligible
                    )
                    .disabled(!appleAIStatus.isHardwareEligible)
                }

                Section {
                    actionButton(
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        tint: PixelTheme.accentBlue,
                        title: L10n.aiRefineActionReprocessTitle,
                        subtitle: L10n.aiRefineActionReprocessSub(activeSpeechEngineName)
                    ) {
                        runReprocessAudio()
                    }
                    .disabled(isRunning)

                    actionButton(
                        icon: "text.badge.checkmark",
                        tint: .indigo,
                        title: L10n.aiRefineActionFixTextTitle,
                        subtitle: L10n.aiRefineActionFixTextSub(activeLLMEngineName)
                    ) {
                        runAIRefinement(mode: .fixTranscriptOnly)
                    }
                    .disabled(isRunning || !canRunLLMRefinement || recording.segments.isEmpty)

                    actionButton(
                        icon: "list.bullet.rectangle.portrait.fill",
                        tint: .purple,
                        title: L10n.aiRefineActionSummaryTitle,
                        subtitle: L10n.aiRefineActionSummarySub(activeLLMEngineName)
                    ) {
                        runAIRefinement(mode: .generateSummaryOnly)
                    }
                    .disabled(isRunning || !canRunLLMRefinement || recording.segments.isEmpty)

                    actionButton(
                        icon: "wand.and.stars",
                        tint: PixelTheme.successEmerald,
                        title: L10n.aiRefineActionFullTitle,
                        subtitle: L10n.aiRefineActionSummarySub(activeLLMEngineName)
                    ) {
                        runAIRefinement(mode: .fixTranscriptAndSummarize)
                    }
                    .disabled(isRunning || !canRunLLMRefinement || recording.segments.isEmpty)
                }

                if !canRunLLMRefinement {
                    Section {
                        Text(
                            appleAIStatus.isHardwareEligible
                                ? L10n.aiRefineOpenSettingsHint
                                : L10n.aiRefineNeedsCloudOrLocal
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if isRunning {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(PixelTheme.accentBlue)
                            Text(progressMessage)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let banner = resultBanner {
                    Section {
                        Label(banner, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PixelTheme.successEmerald)
                    }
                }

                if let err = errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L10n.aiRefineTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                config = .load()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .disabled(isRunning)
                }
            }
        }
    }

    private func capabilityRow(icon: String, title: String, subtitle: String, tint: Color, enabled: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(enabled ? tint : .secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(enabled ? .primary : .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(enabled ? tint : .secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func actionButton(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }
            .padding(.vertical, 4)
        }
    }

    private func runReprocessAudio() {
        errorMessage = nil
        resultBanner = nil
        isRunning = true
        progressMessage = L10n.aiRefineRunningReprocess

        Task {
            do {
                let engine = try await viewModel.reprocessRecordingAudio(recording)
                resultBanner = "\(L10n.aiRefineCompleted) (\(engine))"
            } catch {
                errorMessage = error.localizedDescription
            }
            isRunning = false
        }
    }

    private func runAIRefinement(mode: AIRefinementMode) {
        errorMessage = nil
        resultBanner = nil
        isRunning = true
        progressMessage = (mode == .generateSummaryOnly) ? L10n.aiRefineRunningSummary : L10n.aiRefineRunningFixText

        Task {
            do {
                let engine = try await viewModel.refineRecordingWithAI(recording, mode: mode)
                resultBanner = "\(L10n.aiRefineCompleted) (\(engine))"
            } catch {
                errorMessage = error.localizedDescription
            }
            isRunning = false
        }
    }
}
