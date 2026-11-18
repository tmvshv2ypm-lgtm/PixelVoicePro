import SwiftUI

/// Papelera general ("Eliminadas recientemente") con retención de 30 días,
/// pre-escucha rápida, restauración a carpetas originales y eliminación definitiva.
struct RecentlyDeletedView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @StateObject private var playerService = AudioPlayerService()

    @State private var playingRecordingID: UUID?
    @State private var recordingPendingPermanentDelete: VoiceRecording?
    @State private var showEmptyTrashConfirmation: Bool = false
    @State private var showRestoreAllConfirmation: Bool = false

    private var maxRowWidth: CGFloat {
        horizontalSizeClass == .regular ? 860 : .infinity
    }

    var body: some View {
        List {
            if viewModel.trashedRecordings.isEmpty {
                emptyTrashState
                    .listRowInsets(EdgeInsets(top: 40, leading: 20, bottom: 20, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                infoBannerRow
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                ForEach(viewModel.trashedRecordings) { recording in
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        TrashedRecordingRowCard(
                            recording: recording,
                            isPlaying: playingRecordingID == recording.id && playerService.isPlaying,
                            accentColor: themeManager.primaryAccent,
                            tagColorProvider: { tag in themeManager.folderColor(for: tag) },
                            onTogglePlay: {
                                togglePreview(for: recording)
                            },
                            onRestore: {
                                restore(recording)
                            },
                            onRequestPermanentDelete: {
                                recordingPendingPermanentDelete = recording
                            }
                        )
                        .frame(maxWidth: maxRowWidth)
                        Spacer(minLength: 0)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            restore(recording)
                        } label: {
                            Label(L10n.trashRestoreAction, systemImage: "arrow.uturn.backward")
                        }
                        .tint(themeManager.primaryAccent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            recordingPendingPermanentDelete = recording
                        } label: {
                            Label(L10n.trashDeleteForeverAction, systemImage: "trash.fill")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(L10n.trashNavTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.trashedRecordings.isEmpty {
                    Menu {
                        Button {
                            showRestoreAllConfirmation = true
                        } label: {
                            Label(L10n.trashRestoreAllAction, systemImage: "arrow.uturn.backward.circle")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showEmptyTrashConfirmation = true
                        } label: {
                            Label(L10n.trashEmptyAction, systemImage: "trash.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body.weight(.semibold))
                    }
                }
            }
        }
        .confirmationDialog(
            L10n.trashConfirmDeleteTitle(recordingPendingPermanentDelete?.title ?? ""),
            isPresented: Binding(
                get: { recordingPendingPermanentDelete != nil },
                set: { if !$0 { recordingPendingPermanentDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.trashDeleteForeverAction, role: .destructive) {
                if let target = recordingPendingPermanentDelete {
                    if playingRecordingID == target.id {
                        playerService.stop()
                        playingRecordingID = nil
                    }
                    viewModel.permanentlyDeleteRecording(target)
                }
                recordingPendingPermanentDelete = nil
            }
            Button(L10n.cancel, role: .cancel) {
                recordingPendingPermanentDelete = nil
            }
        } message: {
            Text(L10n.trashConfirmDeleteMessage)
        }
        .confirmationDialog(
            L10n.trashConfirmEmptyTitle(
                count: viewModel.trashedRecordings.count,
                size: viewModel.formattedTrashedStorageUsed
            ),
            isPresented: $showEmptyTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.trashEmptyAction, role: .destructive) {
                playerService.stop()
                playingRecordingID = nil
                viewModel.emptyTrash()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.trashConfirmDeleteMessage)
        }
        .confirmationDialog(
            L10n.trashConfirmRestoreAllTitle(count: viewModel.trashedRecordings.count),
            isPresented: $showRestoreAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.trashRestoreAllAction) {
                playerService.stop()
                playingRecordingID = nil
                viewModel.restoreAllFromTrash()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.trashRestoreAllMessage)
        }
        .onChange(of: playerService.isPlaying) { _, isPlaying in
            if !isPlaying {
                playingRecordingID = nil
            }
        }
        .onDisappear {
            playerService.stop()
            playingRecordingID = nil
        }
    }

    private var emptyTrashState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.slash")
                .font(.system(size: 42))
                .foregroundStyle(.secondary.opacity(0.75))
            Text(L10n.trashEmptyTitle)
                .font(.headline)
            Text(L10n.trashEmptySubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var infoBannerRow: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.primaryAccent)
                    .frame(width: 30, height: 30)
                    .background(themeManager.primaryAccent.opacity(0.14), in: Circle())

                Text(
                    L10n.trashInfoBanner(
                        count: viewModel.trashedRecordings.count,
                        size: viewModel.formattedTrashedStorageUsed,
                        days: VoiceRecording.trashRetentionDays
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: maxRowWidth, alignment: .leading)
            .liquidGlassRoundedRect(cornerRadius: 16, tint: themeManager.primaryAccent.opacity(0.06), interactive: false)
            Spacer(minLength: 0)
        }
    }

    private func togglePreview(for recording: VoiceRecording) {
        if playingRecordingID == recording.id && playerService.isPlaying {
            playerService.stop()
            playingRecordingID = nil
        } else {
            let url = RecordingStorageService.audioFileURL(for: recording.audioFileName)
            playerService.loadRecording(recording, audioFileURL: url)
            playerService.togglePlayPause()
            playingRecordingID = recording.id
        }
    }

    private func restore(_ recording: VoiceRecording) {
        if playingRecordingID == recording.id {
            playerService.stop()
            playingRecordingID = nil
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            viewModel.restoreRecording(recording)
        }
    }
}

private struct TrashedRecordingRowCard: View {
    let recording: VoiceRecording
    let isPlaying: Bool
    let accentColor: Color
    let tagColorProvider: (TagItem) -> Color
    let onTogglePlay: () -> Void
    let onRestore: () -> Void
    let onRequestPermanentDelete: () -> Void

    private var daysRemaining: Int {
        recording.daysRemainingInTrash
    }

    private var urgencyColor: Color {
        daysRemaining <= 5 ? PixelTheme.recordRed : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onTogglePlay) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 34, height: 34)
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accentColor)
                            .offset(x: isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: 3) {
                    Text(recording.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text(recording.formattedExactCreationDate)
                            .font(.system(.caption2, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Image(systemName: recording.dayPeriod.iconName)
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 20, height: 20)
                            .background(Color(hex: recording.dayPeriod.badgeColorHex).opacity(0.16), in: Circle())
                            .foregroundStyle(Color(hex: recording.dayPeriod.badgeColorHex))
                    }
                }

                Spacer(minLength: 4)

                Text(L10n.trashDaysLeft(daysRemaining))
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(urgencyColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(urgencyColor)
            }

            HStack(spacing: 12) {
                Label(recording.formattedPreciseDuration, systemImage: "waveform")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.primary)

                Text(recording.formattedFileSize)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            if !recording.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recording.tags) { tag in
                            let tagColor = tagColorProvider(tag)
                            HStack(spacing: 4) {
                                Image(systemName: tag.iconName)
                                Text(tag.localizedName)
                            }
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tagColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(tagColor)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                trashActionButton(
                    title: L10n.trashRestoreAction,
                    systemImage: "arrow.uturn.backward.circle.fill",
                    tint: accentColor,
                    fillOpacity: 0.14,
                    action: onRestore
                )

                trashActionButton(
                    title: L10n.trashDeleteForeverAction,
                    systemImage: "trash",
                    tint: PixelTheme.recordRed,
                    fillOpacity: 0.12,
                    action: onRequestPermanentDelete
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
    }

    private func trashActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        fillOpacity: Double,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(tint.opacity(fillOpacity), in: Capsule())
                .foregroundStyle(tint)
        }
        .buttonStyle(.borderless)
    }
}
