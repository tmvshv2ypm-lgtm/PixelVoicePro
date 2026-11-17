import SwiftUI
import Speech

/// Panel de configuración de calidad de grabación (`.m4a` AAC / `.wav` PCM), almacenamiento de la biblioteca
/// y motor híbrido de IA (Apple Speech + Whisper).
struct RecordingSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var recorderService: AudioRecorderService
    @State private var transcriptionConfig: TranscriptionConfiguration = .load()

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
                } header: {
                    Text(L10n.settingsSectionSpeechHeader)
                } footer: {
                    Text(L10n.settingsSectionSpeechFooter)
                }

                Section {
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
