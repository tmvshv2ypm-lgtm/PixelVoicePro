import SwiftUI
import UIKit

/// Wrapper de SwiftUI para presentar `UIActivityViewController` nativo de iOS.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Menú de exportación limpia para compartir solo el audio, solo la transcripción (PDF, Markdown, TXT) o el paquete completo.
struct ExportOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recording: VoiceRecording

    @State private var selectedOption: ExportFormatSelection = .transcriptPDF
    @State private var generatedURLs: [URL] = []
    @State private var isPresentingSystemShareSheet: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recording.title)
                            .font(.headline)
                        Text(recording.formattedExactCreationDate)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(PixelTheme.accentBlue)
                        Text("Duración: \(recording.formattedPreciseDuration) · Peso: \(recording.formattedFileSize) · \(recording.speakers.count) locutor(es)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Resumen de Grabación a Exportar")
                }

                Section("Selecciona el Formato de Exportación") {
                    ForEach(ExportFormatSelection.allCases) { option in
                        Button {
                            selectedOption = option
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: option.iconName)
                                    .font(.title3)
                                    .foregroundStyle(selectedOption == option ? PixelTheme.accentBlue : .secondary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.rawValue)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.primary)
                                    Text(option.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selectedOption == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(PixelTheme.accentBlue)
                                        .font(.title3)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if selectedOption == .transcriptMarkdown || selectedOption == .transcriptPlainText {
                    Section("Vista Previa del Documento Generado") {
                        ScrollView {
                            Text(
                                selectedOption == .transcriptMarkdown
                                    ? ExportService.buildMarkdown(for: recording)
                                    : ExportService.buildPlainText(for: recording)
                            )
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        .frame(maxHeight: 190)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Exportar y Compartir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        prepareAndShare()
                    } label: {
                        Label("Compartir Ahora", systemImage: "square.and.arrow.up")
                            .fontWeight(.bold)
                    }
                }
            }
            .sheet(isPresented: $isPresentingSystemShareSheet) {
                ActivityShareSheet(activityItems: generatedURLs)
            }
        }
    }

    private func prepareAndShare() {
        do {
            let sourceURL = RecordingStorageService.audioFileURL(for: recording.audioFileName)
            let urls = try ExportService.generateExportURLs(
                for: recording,
                sourceAudioURL: sourceURL,
                selection: selectedOption
            )
            generatedURLs = urls
            errorMessage = nil
            isPresentingSystemShareSheet = true
        } catch {
            errorMessage = "No se pudo generar el paquete de exportación: \(error.localizedDescription)"
        }
    }
}
