import SwiftUI

/// Hoja de renombrado rápido y asignación de etiquetas de colores (Tags).
/// Mantiene siempre visible la fecha y hora exacta de creación hasta el segundo (`DD/MM/YYYY - HH:MM:SS AM/PM`) debajo del título.
struct QuickRenameAndTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel
    let recording: VoiceRecording

    @State private var editedTitle: String = ""
    @State private var selectedTags: [TagItem] = []
    @State private var newCustomTagName: String = ""
    @State private var selectedCustomColorHex: String = "#3B82F6"

    private let customColorPalette: [String] = [
        "#3B82F6", "#10B981", "#F59E0B", "#EC4899", "#8B5CF6", "#06B6D4", "#EF4444", "#14B8A6"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TÍTULO PERSONALIZADO DE LA NOTA")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)

                        TextField("Ej. Clase de Sistemas Distribuidos...", text: $editedTitle)
                            .font(.title3.weight(.bold))
                            .textFieldStyle(.roundedBorder)

                        // Fecha y hora exacta de creación obligatoria siempre visible debajo del título
                        HStack(spacing: 6) {
                            Image(systemName: "clock.badge.checkmark.fill")
                                .foregroundStyle(PixelTheme.accentBlue)
                            Text(recording.formattedExactCreationDate)
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            Label(recording.dayPeriod.rawValue, systemImage: recording.dayPeriod.iconName)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: recording.dayPeriod.badgeColorHex).opacity(0.16), in: Capsule())
                                .foregroundStyle(Color(hex: recording.dayPeriod.badgeColorHex))
                        }
                        .padding(.top, 4)

                        HStack(spacing: 12) {
                            Label("Duración: \(recording.formattedPreciseDuration)", systemImage: "timer")
                            Label("Peso: \(recording.formattedFileSize)", systemImage: "internaldrive")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Etiquetas de Colores (Tags)") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                        ForEach(viewModel.availableTags) { tag in
                            let isSelected = selectedTags.contains(where: { $0.id == tag.id })
                            Button {
                                toggleSelection(for: tag)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: tag.iconName)
                                        .font(.caption.weight(.bold))
                                    Text(tag.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer(minLength: 2)
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .foregroundStyle(isSelected ? .white : tag.color)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? tag.color : tag.color.opacity(0.14))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(tag.color.opacity(0.45), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Crear Nueva Etiqueta Personalizada") {
                    HStack {
                        TextField("Nombre (ej. Examen Final, Tesis)", text: $newCustomTagName)
                        Button("Añadir") {
                            let created = viewModel.createCustomTag(
                                name: newCustomTagName,
                                colorHex: selectedCustomColorHex
                            )
                            if !selectedTags.contains(where: { $0.id == created.id }) {
                                selectedTags.append(created)
                            }
                            newCustomTagName = ""
                        }
                        .disabled(newCustomTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.borderedProminent)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(customColorPalette, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.primary, lineWidth: selectedCustomColorHex == hex ? 2.5 : 0)
                                    )
                                    .onTapGesture {
                                        selectedCustomColorHex = hex
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Título y Etiquetas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        viewModel.updateRecordingTitleAndTags(
                            recording,
                            newTitle: editedTitle,
                            newTags: selectedTags
                        )
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                editedTitle = recording.title
                selectedTags = recording.tags
            }
        }
    }

    private func toggleSelection(for tag: TagItem) {
        if let idx = selectedTags.firstIndex(where: { $0.id == tag.id }) {
            selectedTags.remove(at: idx)
        } else {
            selectedTags.append(tag)
        }
    }
}
