import SwiftUI

/// Hoja interactiva para renombrar a los locutores identificados (`Locutor 1`, `Locutor 2`, etc.)
/// por el nombre real de la persona y actualizar automáticamente toda la nota de voz y exportaciones.
struct SpeakerRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recording: VoiceRecording
    let initialSpeakerId: String?
    let onSaved: () -> Void

    @State private var editableSpeakers: [SpeakerProfile] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Cambia \"Locutor 1\", \"Locutor 2\", etc. por el nombre real de cada persona. El nombre y color se actualizarán al instante en todos los párrafos de la transcripción, estadísticas y exportaciones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach($editableSpeakers) { $speaker in
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: speaker.colorHex))
                                    .frame(width: 38, height: 38)
                                    .overlay(
                                        Text(speaker.initials)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(speaker.defaultLabel)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                    Text("Pitch vocal medio: \(Int(speaker.pitchMeanHz)) Hz · \(speaker.wordCount) palabras")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            TextField(
                                "Nombre real (ej. Dr. Martínez, Ana, Profesor)",
                                text: Binding(
                                    get: { speaker.customName ?? "" },
                                    set: { speaker.customName = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.body.weight(.semibold))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(PixelTheme.speakerHexPalette, id: \.self) { hex in
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 24, height: 24)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(Color.primary, lineWidth: speaker.colorHex == hex ? 2.5 : 0)
                                            )
                                            .onTapGesture {
                                                speaker.colorHex = hex
                                            }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        HStack {
                            Text(speaker.displayName)
                            if speaker.id == initialSpeakerId {
                                Text("• Seleccionado")
                                    .foregroundStyle(PixelTheme.accentBlue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Identificación de Locutores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar en Toda la Nota") {
                        for item in editableSpeakers {
                            recording.renameSpeaker(
                                speakerId: item.id,
                                newName: item.customName ?? "",
                                newColorHex: item.colorHex
                            )
                        }
                        recording.recalculateSpeakerStatistics()
                        onSaved()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                editableSpeakers = recording.speakers
            }
        }
    }
}
