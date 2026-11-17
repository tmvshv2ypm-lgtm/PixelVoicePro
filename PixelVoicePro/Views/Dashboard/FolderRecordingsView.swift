import SwiftUI

/// Pantalla dedicada para explorar las grabaciones dentro de una carpeta cuadrada de Voice Notes
/// (Todas, Favoritas o cualquier carpeta temática/personalizada).
struct FolderRecordingsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var viewModel: AppViewModel
    let folder: FolderDestination
    let onExport: (VoiceRecording) -> Void

    @State private var selectedDayPeriod: DayPeriod?

    var body: some View {
        let groups = viewModel.chronologicalDayGroups(for: folder, dayPeriod: selectedDayPeriod)

        ZStack(alignment: .bottom) {
            List {
                // Filtro rápido de franja horaria dentro de la carpeta
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DayPeriod.allCases) { period in
                            let selected = selectedDayPeriod == period
                            AppleMailFilterPill(
                                title: period.localizedTitle,
                                icon: period.iconName,
                                color: Color(hex: period.badgeColorHex),
                                isSelected: selected
                            ) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                    selectedDayPeriod = selected ? nil : period
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if groups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: folder.iconName)
                            .font(.system(size: 42))
                            .foregroundStyle(folder.color.opacity(0.75))
                        Text(L10n.folderEmptyTitle(folder.title))
                            .font(.headline)
                        Text(L10n.folderEmptySubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.recordings) { recording in
                                HStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    RecordingListCardView(
                                        recording: recording,
                                        onOpen: {
                                            viewModel.openRecording(recording)
                                        },
                                        onQuickRenameAndTag: {
                                            viewModel.recordingPendingQuickEdit = recording
                                        },
                                        onToggleFavorite: {
                                            viewModel.toggleFavorite(recording)
                                        },
                                        onExport: {
                                            onExport(recording)
                                        },
                                        onDelete: {
                                            viewModel.deleteRecording(recording)
                                        }
                                    )
                                    .frame(maxWidth: horizontalSizeClass == .regular ? 860 : .infinity)
                                    Spacer(minLength: 0)
                                }
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        viewModel.deleteRecording(recording)
                                    } label: {
                                        Label(L10n.delete, systemImage: "trash.fill")
                                    }

                                    Button {
                                        viewModel.toggleFavorite(recording)
                                    } label: {
                                        Label(
                                            recording.isFavorite ? L10n.remove : L10n.favorite,
                                            systemImage: recording.isFavorite ? "star.slash.fill" : "star.fill"
                                        )
                                    }
                                    .tint(PixelTheme.bookmarkAmber)

                                    Button {
                                        viewModel.recordingPendingQuickEdit = recording
                                    } label: {
                                        Label(L10n.tags, systemImage: "folder.badge.plus")
                                    }
                                    .tint(PixelTheme.accentBlue)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        onExport(recording)
                                    } label: {
                                        Label(L10n.export, systemImage: "square.and.arrow.up.fill")
                                    }
                                    .tint(.indigo)
                                }
                            }
                        } header: {
                            HStack {
                                Spacer(minLength: 0)
                                HStack {
                                    Image(systemName: "calendar.badge.clock")
                                        .foregroundStyle(PixelTheme.accentBlue)
                                    Text(group.headerTitle)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(L10n.groupNotesCount(group.recordings.count))
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.07), in: Capsule())
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: horizontalSizeClass == .regular ? 860 : .infinity)
                                Spacer(minLength: 0)
                            }
                            .textCase(nil)
                            .padding(.vertical, 2)
                        }
                        .listSectionSeparator(.hidden)
                    }
                }

                Color.clear
                    .frame(height: 92)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 8)

            FloatingRecordButtonBar {
                let initialTags = folder.associatedTag.map { [$0] } ?? []
                viewModel.startRecordingSession(initialTags: initialTags)
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(folder.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.isShowingSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                }
                .accessibilityLabel(L10n.settingsTitle)
            }
        }
    }
}
