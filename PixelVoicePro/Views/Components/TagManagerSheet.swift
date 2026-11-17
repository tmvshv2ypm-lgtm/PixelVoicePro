import SwiftUI

enum TagManagerMode {
    case filterLibrary
    case assignToRecording(selectedTags: Binding<[TagItem]>)
}

/// Gestor unificado de etiquetas: permite seleccionar, crear, ocultar predeterminadas y eliminar personalizadas.
struct TagManagerSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let mode: TagManagerMode
    @Environment(\.dismiss) private var dismiss

    @State private var newTagName: String = ""
    @State private var selectedColorHex: String = "#0A84FF"

    private let colorPalette: [String] = [
        "#0A84FF", "#30D158", "#FF9F0A", "#BF5AF2", "#FF3B30", "#64D2FF", "#FF375F", "#AC8E68"
    ]

    var body: some View {
        NavigationStack {
            List {
                // 1. Etiquetas predeterminadas: solo se pueden ocultar/mostrar, nunca eliminar
                Section {
                    ForEach(viewModel.availableTags.filter { viewModel.isDefaultTag($0) }) { tag in
                        defaultTagRow(tag)
                    }
                } header: {
                    Text(L10n.tagsSectionDefault)
                } footer: {
                    Text(L10n.tagsSectionDefaultFooter)
                }

                // 2. Etiquetas personalizadas creadas por el usuario (sí se pueden eliminar)
                Section(L10n.tagsSectionCustom) {
                    let customTags = viewModel.availableTags.filter { !viewModel.isDefaultTag($0) }
                    if customTags.isEmpty {
                        Text(L10n.tagsEmptyCustom)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(customTags) { tag in
                            customTagRow(tag)
                        }
                    }
                }

                // 3. Creación rápida de etiqueta nueva
                Section(L10n.tagsSectionNew) {
                    TextField(L10n.tagsNewPlaceholder, text: $newTagName)
                        .autocorrectionDisabled()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(colorPalette, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.primary, lineWidth: selectedColorHex == hex ? 2.5 : 0)
                                    )
                                    .onTapGesture {
                                        selectedColorHex = hex
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        createTagAction()
                    } label: {
                        Label(L10n.tagsCreateButton, systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PixelTheme.accentBlue)
                    }
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(L10n.tagsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if case .filterLibrary = mode, viewModel.selectedTagFilter != nil {
                        Button(L10n.tagsClearFilter) {
                            viewModel.selectedTagFilter = nil
                            dismiss()
                        }
                        .font(.subheadline)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    @ViewBuilder
    private func defaultTagRow(_ tag: TagItem) -> some View {
        let isHidden = viewModel.isTagHidden(tag)
        let isSelected = isTagSelected(tag)

        HStack(spacing: 12) {
            Button {
                if isHidden {
                    viewModel.toggleDefaultTagVisibility(tag)
                }
                handleTagSelection(tag)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: tag.iconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tag.color)
                        .frame(width: 24)

                    Text(tag.localizedName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isHidden ? .secondary : .primary)

                    if isHidden {
                        Text(L10n.tagsHiddenBadge)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(PixelTheme.accentBlue)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleDefaultTagVisibility(tag)
                }
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .font(.subheadline)
                    .foregroundStyle(isHidden ? .secondary : PixelTheme.accentBlue)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isHidden ? L10n.tagsShowAccessibility(tag.localizedName) : L10n.tagsHideAccessibility(tag.localizedName))
        }
    }

    @ViewBuilder
    private func customTagRow(_ tag: TagItem) -> some View {
        let isSelected = isTagSelected(tag)

        HStack(spacing: 12) {
            Button {
                handleTagSelection(tag)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: tag.iconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tag.color)
                        .frame(width: 24)

                    Text(tag.localizedName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(PixelTheme.accentBlue)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                deleteCustomTagAction(tag)
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(PixelTheme.recordRed)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tagsDeleteAccessibility(tag.localizedName))
        }
    }

    private func isTagSelected(_ tag: TagItem) -> Bool {
        switch mode {
        case .filterLibrary:
            return false
        case .assignToRecording(let selectedTags):
            return selectedTags.wrappedValue.contains(where: { $0.id == tag.id })
        }
    }

    private func handleTagSelection(_ tag: TagItem) {
        switch mode {
        case .filterLibrary:
            if viewModel.isTagHidden(tag) {
                viewModel.toggleDefaultTagVisibility(tag)
            }
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                viewModel.openFolder(.tag(tag))
            }

        case .assignToRecording(let selectedTags):
            if let idx = selectedTags.wrappedValue.firstIndex(where: { $0.id == tag.id }) {
                selectedTags.wrappedValue.remove(at: idx)
            } else {
                selectedTags.wrappedValue.append(tag)
            }
        }
    }

    private func createTagAction() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let created = viewModel.createCustomTag(name: trimmed, colorHex: selectedColorHex)
        newTagName = ""

        if case .assignToRecording(let selectedTags) = mode {
            if !selectedTags.wrappedValue.contains(where: { $0.id == created.id }) {
                selectedTags.wrappedValue.append(created)
            }
        }
    }

    private func deleteCustomTagAction(_ tag: TagItem) {
        if case .assignToRecording(let selectedTags) = mode {
            selectedTags.wrappedValue.removeAll { $0.id == tag.id }
        }
        viewModel.deleteCustomTag(tag)
    }
}
