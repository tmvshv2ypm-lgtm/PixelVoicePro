import SwiftUI

/// Panel de configuración de calidad de grabación (`.m4a` AAC / `.wav` PCM) y motor híbrido de IA (Apple Speech + Whisper).
struct RecordingSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var recorderService: AudioRecorderService
    @State private var transcriptionConfig: TranscriptionConfiguration = .load()

    private let supportedSpanishLocales: [(id: String, name: String)] = [
        ("es-ES", "Español (España)"),
        ("es-MX", "Español (México)"),
        ("es-419", "Español (Latinoamérica)"),
        ("es-CO", "Español (Colombia)"),
        ("es-AR", "Español (Argentina)"),
        ("es-US", "Español (Estados Unidos)")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Formato de Grabación", selection: $recorderService.selectedFormat) {
                        ForEach(AudioFormatOption.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.inline)

                    Text(recorderService.selectedFormat.descriptionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Frecuencia de Muestreo", selection: $recorderService.selectedSampleRate) {
                        ForEach(SampleRateOption.allCases) { rate in
                            Text(rate.displayLabel).tag(rate)
                        }
                    }
                } header: {
                    Text("Motor de Audio AVFoundation")
                }

                Section {
                    Picker("Variante de Español", selection: $transcriptionConfig.localeIdentifier) {
                        ForEach(supportedSpanishLocales, id: \.id) { locale in
                            Text(locale.name).tag(locale.id)
                        }
                    }

                    Toggle("Priorizar Reconocimiento On-Device (Offline)", isOn: $transcriptionConfig.preferOnDeviceRecognition)
                } header: {
                    Text("Transcripción en Tiempo Real (Framework Speech)")
                } footer: {
                    Text("El modo On-Device procesa la voz directamente en el Neural Engine del iPhone con latencia cero y privacidad total.")
                }

                Section {
                    Toggle("Activar Post-Procesamiento Whisper API / Local", isOn: $transcriptionConfig.enableWhisperPostProcessing)

                    if transcriptionConfig.enableWhisperPostProcessing {
                        TextField("Endpoint URL", text: $transcriptionConfig.whisperEndpointURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption)

                        TextField("Modelo (ej. whisper-1 o whisper-large-v3)", text: $transcriptionConfig.whisperModelName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        SecureField("Clave API (Bearer Token)", text: $transcriptionConfig.whisperAPIKey)
                    }
                } header: {
                    Text("Módulo Híbrido Whisper AI (Opcional)")
                } footer: {
                    Text("Puedes conectar la API oficial de OpenAI Whisper o un servidor Whisper local en tu red para refinar las marcas de tiempo palabra por palabra al finalizar cada grabación.")
                }

                Section("Formato Estricto de Fechas y Horas") {
                    HStack {
                        Text("Estándar activo")
                        Spacer()
                        Text("DD/MM/YYYY - HH:MM:SS AM/PM")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(PixelTheme.accentBlue)
                    }
                    HStack {
                        Text("Ejemplo en vivo")
                        Spacer()
                        Text(ExactDateFormatter.fullExactTimestamp(from: Date()))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Ajustes de PixelVoice Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        transcriptionConfig.save()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}
