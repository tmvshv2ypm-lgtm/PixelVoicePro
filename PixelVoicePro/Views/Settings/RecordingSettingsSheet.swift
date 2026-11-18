import SwiftUI
import Speech

/// Panel de configuración de calidad de grabación (`.m4a` AAC / `.wav` PCM), almacenamiento de la biblioteca
/// y motor híbrido de IA (Apple Speech + Whisper).
struct RecordingSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var recorderService: AudioRecorderService
    @State private var transcriptionConfig: TranscriptionConfiguration = .load()
    @State private var showGroqAppliedNotice: Bool = false

    private var appleAIStatus: AppleIntelligenceAvailabilityStatus {
        AdaptiveAICapability.appleIntelligenceStatus
    }

    private var speechLocaleOptions: [(id: String, name: String)] {
        SpeechTranscriptionService.availableSpeechLocaleOptions()
    }

    private var resolvedSpeechLocale: Locale {
        SpeechTranscriptionService.resolveRecognitionLocale(for: transcriptionConfig.localeIdentifier)
    }

    private var supportsOfflineRecognition: Bool {
        SFSpeechRecognizer(locale: resolvedSpeechLocale)?.supportsOnDeviceRecognition ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.settingsSectionStorage) {
                    HStack {
                        Label(L10n.settingsSavedNotes, systemImage: "waveform.circle.fill")
                        Spacer()
                        Text(L10n.groupNotesCount(viewModel.recordings.count))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PixelTheme.accentBlue)
                    }

                    HStack {
                        Label(L10n.settingsTotalStorage, systemImage: "internaldrive.fill")
                        Spacer()
                        Text(viewModel.formattedTotalStorageUsed)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker(L10n.settingsRecordingFormat, selection: $recorderService.selectedFormat) {
                        ForEach(AudioFormatOption.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.inline)

                    Text(recorderService.selectedFormat.descriptionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker(L10n.settingsSampleRate, selection: $recorderService.selectedSampleRate) {
                        ForEach(SampleRateOption.allCases) { rate in
                            Text(rate.displayLabel).tag(rate)
                        }
                    }
                } header: {
                    Text(L10n.settingsSectionAudio)
                }

                Section {
                    Picker(L10n.settingsSpeechLanguage, selection: $transcriptionConfig.localeIdentifier) {
                        Text(L10n.settingsSpeechAuto)
                            .tag(TranscriptionConfiguration.automaticLocaleIdentifier)

                        Divider()

                        ForEach(speechLocaleOptions, id: \.id) { locale in
                            Text(locale.name).tag(locale.id)
                        }
                    }

                    HStack {
                        Label(L10n.settingsSpeechActiveLabel, systemImage: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(SpeechTranscriptionService.localizedDisplayName(for: resolvedSpeechLocale))
                                .font(.caption.weight(.semibold))
                            Text(supportsOfflineRecognition ? L10n.settingsSpeechOfflineAvailable : L10n.settingsSpeechCloudFallback)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(supportsOfflineRecognition ? .green : .orange)
                        }
                    }

                    Toggle(L10n.settingsSpeechOnDevice, isOn: $transcriptionConfig.preferOnDeviceRecognition)

                    Toggle(isOn: $transcriptionConfig.useModernSpeechAnalyzer) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.settingsSpeechModernEngine)
                            Text(
                                AdaptiveAICapability.isModernSpeechAnalyzerAvailable
                                    ? L10n.settingsSpeechModernEngineReady
                                    : L10n.settingsSpeechModernEngineFallback
                            )
                            .font(.caption2)
                            .foregroundStyle(AdaptiveAICapability.isModernSpeechAnalyzerAvailable ? .green : .secondary)
                        }
                    }
                    .disabled(!AdaptiveAICapability.isModernSpeechAnalyzerAvailable)
                } header: {
                    Text(L10n.settingsSectionSpeechHeader)
                } footer: {
                    Text(L10n.settingsSectionSpeechFooter)
                }

                Section {
                    Picker(L10n.settingsAcousticSensitivity, selection: $transcriptionConfig.acousticSensitivity) {
                        ForEach(TranscriptionConfiguration.AcousticSensitivityLevel.allCases) { level in
                            Text(level.localizedTitle).tag(level)
                        }
                    }
                } header: {
                    Text(L10n.settingsSectionAcousticHeader)
                } footer: {
                    Text(L10n.settingsSectionAcousticFooter)
                }

                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appleAIStatus.isAvailable ? PixelTheme.accentBlue : .secondary)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.settingsAILocalToggle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(appleAIStatus.isHardwareEligible ? .primary : .secondary)
                            Text(appleAIStatus.localizedStatusMessage)
                                .font(.caption2)
                                .foregroundStyle(appleAIStatus.isAvailable ? .green : .secondary)
                        }
                    }
                    .opacity(appleAIStatus.isHardwareEligible ? 1.0 : 0.65)
                    .disabled(!appleAIStatus.isHardwareEligible)

                    Picker(L10n.settingsAIProviderPicker, selection: $transcriptionConfig.aiRefinementProvider) {
                        Text(L10n.aiProviderAutomatic)
                            .tag(TranscriptionConfiguration.AIRefinementProviderPreference.automatic)
                        Text(L10n.aiProviderAppleLocal)
                            .tag(TranscriptionConfiguration.AIRefinementProviderPreference.appleIntelligenceLocal)
                        Text(L10n.aiProviderCloud)
                            .tag(TranscriptionConfiguration.AIRefinementProviderPreference.cloudOpenAICompatible)
                    }

                    Toggle(L10n.settingsAIAutoRefineToggle, isOn: $transcriptionConfig.enableAIRefinementOnFinish)
                        .disabled(!AdaptiveAICapability.canRunAIRefinement(config: transcriptionConfig))
                } header: {
                    Text(L10n.settingsSectionAIHeader)
                } footer: {
                    Text(L10n.settingsSectionAIFooter)
                }

                Section {
                    Button {
                        transcriptionConfig.applyGroqFreePreset()
                        transcriptionConfig.enableWhisperPostProcessing = true
                        transcriptionConfig.save()
                        showGroqAppliedNotice = true
                    } label: {
                        Label(L10n.settingsGroqPresetButton, systemImage: "bolt.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PixelTheme.accentBlue)
                    }

                    if showGroqAppliedNotice {
                        Text(L10n.settingsGroqPresetApplied)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Toggle(L10n.settingsWhisperToggle, isOn: $transcriptionConfig.enableWhisperPostProcessing)

                    if transcriptionConfig.enableWhisperPostProcessing {
                        TextField(L10n.settingsWhisperEndpoint, text: $transcriptionConfig.whisperEndpointURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption)

                        TextField(L10n.settingsWhisperModel, text: $transcriptionConfig.whisperModelName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        SecureField(L10n.settingsWhisperAPIKey, text: $transcriptionConfig.whisperAPIKey)
                    }
                } header: {
                    Text(L10n.settingsSectionWhisperHeader)
                } footer: {
                    Text(L10n.settingsSectionWhisperFooter)
                }

                Section {
                    TextField(L10n.settingsAIChatEndpoint, text: $transcriptionConfig.aiChatEndpointURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.caption)

                    TextField(L10n.settingsAIChatModel, text: $transcriptionConfig.aiChatModelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField(L10n.settingsAIChatAPIKey, text: $transcriptionConfig.aiChatAPIKey)
                } header: {
                    Text(L10n.settingsAIChatHeader)
                } footer: {
                    Text(L10n.settingsAIChatFooter)
                }

                Section(L10n.settingsSectionDates) {
                    HStack {
                        Text(L10n.settingsDateStandard)
                        Spacer()
                        Text(verbatim: "DD/MM/YYYY - HH:MM:SS AM/PM")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(PixelTheme.accentBlue)
                    }
                    HStack {
                        Text(L10n.settingsDateExample)
                        Spacer()
                        Text(ExactDateFormatter.fullExactTimestamp(from: Date()))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: transcriptionConfig.localeIdentifier) { _, _ in
                transcriptionConfig.save()
            }
            .onChange(of: transcriptionConfig.preferOnDeviceRecognition) { _, _ in
                transcriptionConfig.save()
            }
            .onChange(of: transcriptionConfig.enableWhisperPostProcessing) { _, _ in
                transcriptionConfig.save()
            }
            .onChange(of: transcriptionConfig.useModernSpeechAnalyzer) { _, _ in
                transcriptionConfig.save()
            }
            .onChange(of: transcriptionConfig.acousticSensitivity) { _, _ in
                transcriptionConfig.save()
            }
            .onChange(of: transcriptionConfig.enableAIRefinementOnFinish) { _, _ in
                transcriptionConfig.save()
            }
            .onChange(of: transcriptionConfig.aiRefinementProvider) { _, newValue in
                if newValue == .appleIntelligenceLocal && !appleAIStatus.isHardwareEligible {
                    transcriptionConfig.aiRefinementProvider = .automatic
                }
                transcriptionConfig.save()
            }
            .onDisappear {
                transcriptionConfig.save()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) {
                        transcriptionConfig.save()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}
