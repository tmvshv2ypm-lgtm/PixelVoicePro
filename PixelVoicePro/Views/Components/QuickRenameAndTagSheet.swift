import SwiftUI

/// Hoja de renombrado rápido y asignación de etiquetas de colores (Tags).
/// Mantiene siempre visible la fecha y hora exacta de creación hasta el segundo (`DD/MM/YYYY - HH:MM:SS AM/PM`) debajo del título.
struct QuickRenameAndTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    let recording: VoiceRecording

    @State private var editedTitle: String = ""
    @State private var selectedTags: [TagItem] = []
    @State private var showTagManagerSheet: Bool = false

    private var compactQuickTags: [TagItem] {
        var result = selectedTags
        for tag in viewModel.visibleAvailableTags where !result.contains(where: { $0.id == tag.id }) {
            if result.count >= max(2, selectedTags.count) && result.count >= 2 {
                break
            }
            result.append(tag)
            if result.count == 2 && selectedTags.isEmpty {
                break
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.quickCustomTitleHeader)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)

                        TextField(L10n.quickTitlePlaceholder, text: $editedTitle)
                            .font(.title3.weight(.bold))
                            .textFieldStyle(.roundedBorder)

                        // Fecha y hora exacta de creación obligatoria siempre visible debajo del título
                        HStack(spacing: 6) {
                            Image(systemName: "clock.badge.checkmark.fill")
                                .foregroundStyle(themeManager.primaryAccent)
                            Text(recording.formattedExactCreationDate)
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            Label(recording.dayPeriod.localizedTitle, systemImage: recording.dayPeriod.iconName)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: recording.dayPeriod.badgeColorHex).opacity(0.16), in: Capsule())
                                .foregroundStyle(Color(hex: recording.dayPeriod.badgeColorHex))
                        }
                        .padding(.top, 4)

                        HStack(spacing: 12) {
                            Label(L10n.quickDurationLabel(recording.formattedPreciseDuration), systemImage: "timer")
                            Label(L10n.quickSizeLabel(recording.formattedFileSize), systemImage: "internaldrive")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(L10n.tags) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(compactQuickTags) { tag in
                                let isSelected = selectedTags.contains(where: { $0.id == tag.id })
                                let tagColor = themeManager.folderColor(for: tag)
                                Button {
                                    toggleSelection(for: tag)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: tag.iconName)
                                            .font(.caption.weight(.bold))
                                        Text(tag.localizedName)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption2)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(isSelected ? .white : tagColor)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? tagColor : tagColor.opacity(0.14))
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                showTagManagerSheet = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.subheadline.weight(.bold))
                                    .frame(width: 34, height: 34)
                                    .liquidGlassCircle()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.quickManageTagsAccessibility)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(L10n.quickNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) {
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
            .sheet(isPresented: $showTagManagerSheet) {
                TagManagerSheet(
                    viewModel: viewModel,
                    mode: .assignToRecording(selectedTags: $selectedTags)
                )
                .tint(nil)
            }
            .onAppear {
                editedTitle = recording.title
                selectedTags = recording.tags
            }
        }
        .tint(themeManager.primaryAccent)
    }

    private func toggleSelection(for tag: TagItem) {
        if let idx = selectedTags.firstIndex(where: { $0.id == tag.id }) {
            selectedTags.remove(at: idx)
        } else {
            selectedTags.append(tag)
        }
    }
}
