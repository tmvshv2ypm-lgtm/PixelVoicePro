import SwiftUI
import UIKit

/// Vista 3 (Detalle y Reproducción Interactiva):
/// Panel superior con pestañas ("Transcripción completa", "Resumen/Marcadores", "Detalles del archivo"),
/// sincronización Karaoke palabra por palabra, buscador local con pines en la onda, renombrado de locutores y reproductor Pro abajo.
struct RecordingDetailView: View {
    enum DetailTab: String, CaseIterable, Identifiable {
        case player = "Audio"
        case transcript = "Transcripción"
        case summaryAndBookmarks = "Resumen"
        case fileDetails = "Detalles"

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .player: return L10n.tabAudio
            case .transcript: return L10n.tabTranscript
            case .summaryAndBookmarks: return L10n.tabSummary
            case .fileDetails: return L10n.tabDetails
            }
        }
    }

    enum TranscriptDisplayMode: String, CaseIterable, Identifiable {
        case bySpeaker
        case continuousNote

        var id: String { rawValue }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    let recording: VoiceRecording
    let initialSeekTimestamp: TimeInterval?
    let initialSearchKeyword: String?

    private var isCompactVertical: Bool {
        verticalSizeClass == .compact
    }

    @StateObject private var playerService = AudioPlayerService()

    @FocusState private var isLocalSearchFocused: Bool
    @State private var selectedTab: DetailTab = .player
    @State private var transcriptDisplayMode: TranscriptDisplayMode = .bySpeaker
    @State private var didCopyContinuousNote: Bool = false
    @State private var localSearchQuery: String = ""
    @State private var currentSearchHitIndex: Int = 0
    @State private var selectedSpeakerIdForRename: String?
    @State private var isShowingSpeakerRenameSheet: Bool = false
    @State private var isShowingQuickEditSheet: Bool = false
    @State private var isShowingExportSheet: Bool = false
    @State private var isShowingAIRefinementSheet: Bool = false
    @State private var newPlaybackBookmarkLabel: String = ""

    private var localSearchHits: [LocalWordSearchHit] {
        recording.searchLocalOccurrences(query: localSearchQuery)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // 1. Cabecera compacta con Título Editable y Fecha/Hora Exacta
                detailTopHeader

                // 2. Barra de estado y progreso en tiempo real si la transcripción está en curso
                if isProcessingThisNote {
                    let isActivelyThisNote = viewModel.activeProcessingRecordingID == recording.id
                        || (viewModel.activeProcessingRecordingID == nil && viewModel.isBackgroundProcessingActive)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(themeManager.primaryAccent)
                            Text(L10n.bgTranscriptionKeepOpen)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if isActivelyThisNote && !viewModel.backgroundProcessingStatus.isEmpty {
                                Text("· \(viewModel.backgroundProcessingStatus)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if isActivelyThisNote {
                                Text("\(Int(viewModel.backgroundProcessingProgress * 100))%")
                                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                                    .foregroundStyle(themeManager.primaryAccent)
                            }
                        }

                        if isActivelyThisNote {
                            ProgressView(value: viewModel.backgroundProcessingProgress, total: 1.0)
                                .tint(themeManager.primaryAccent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(themeManager.primaryAccent.opacity(0.08))
                }

                // 3. Pestañas limpias sin truncar: Audio, Transcripción, Resumen, Detalles
                detailTopTabBar

                // 4. Buscador local únicamente en la vista de Transcripción
                if selectedTab == .transcript {
                    localSearchBar
                        .transition(.opacity)
                }

                // 5. Vista activa a pantalla completa con transición suave
                Group {
                    switch selectedTab {
                    case .player:
                        fullScreenAudioPlayerView
                            .transition(.opacity.combined(with: .scale(scale: 0.99)))
                    case .transcript:
                        karaokeTranscriptTabView
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    case .summaryAndBookmarks:
                        summaryAndBookmarksTabView
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    case .fileDetails:
                        technicalFileDetailsTabView
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.easeInOut(duration: 0.22), value: selectedTab)

            // Mini reproductor flotante Liquid Glass cuando se visualiza Transcripción, Resumen o Detalles
            if selectedTab != .player {
                floatingLiquidGlassMiniPlayer
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 16)
                    .padding(.bottom, isCompactVertical ? 6 : 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingAIRefinementSheet = true
                } label: {
                    Label(L10n.toolbarRefineAI, systemImage: "sparkles")
                }

                Button {
                    selectedSpeakerIdForRename = recording.speakers.first?.id
                    isShowingSpeakerRenameSheet = true
                } label: {
                    Label(L10n.toolbarSpeakers, systemImage: "person.2.wave.2.fill")
                }

                Button {
                    isShowingExportSheet = true
                } label: {
                    Label(L10n.export, systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $isShowingAIRefinementSheet) {
            AIRefinementSheet(viewModel: viewModel, recording: recording)
                .tint(nil)
        }
        .sheet(isPresented: $isShowingSpeakerRenameSheet) {
            SpeakerRenameSheet(
                recording: recording,
                initialSpeakerId: selectedSpeakerIdForRename,
                onSaved: {
                    viewModel.saveChanges()
                }
            )
            .tint(nil)
        }
        .sheet(isPresented: $isShowingQuickEditSheet) {
            QuickRenameAndTagSheet(viewModel: viewModel, recording: recording)
        }
        .sheet(isPresented: $isShowingExportSheet) {
            ExportOptionsSheet(recording: recording)
        }
        .onAppear {
            let url = RecordingStorageService.audioFileURL(for: recording.audioFileName)
            playerService.loadRecording(recording, audioFileURL: url)

            if let keyword = initialSearchKeyword, !keyword.isEmpty {
                localSearchQuery = keyword
                selectedTab = .transcript
            }
            if let jumpTime = initialSeekTimestamp, jumpTime > 0 {
                playerService.seek(to: jumpTime, autoPlay: true)
            }
        }
        .onDisappear {
            playerService.stop()
        }
    }

    private var detailTopTabBar: some View {
        HStack(spacing: 6) {
            ForEach(DetailTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        selectedTab = tab
                        if tab != .transcript {
                            isLocalSearchFocused = false
                        }
                    }
                } label: {
                    Text(tab.localizedTitle)
                        .font(.caption.weight(isSelected ? .bold : .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isSelected ? themeManager.primaryAccent : Color.clear)
                        )
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        .frame(maxWidth: horizontalSizeClass == .regular ? 760 : .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, isCompactVertical ? 4 : 8)
    }

    private var floatingLiquidGlassMiniPlayer: some View {
        HStack(spacing: 12) {
            Button {
                playerService.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(themeManager.primaryAccent)
                        .frame(width: 40, height: 40)
                        .liquidGlassCircle(tint: themeManager.primaryAccent)
                    Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .offset(x: playerService.isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    selectedTab = .player
                }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(ExactDateFormatter.preciseChronometer(playerService.currentTime, alwaysShowHours: false)) / \(ExactDateFormatter.preciseChronometer(playerService.duration, alwaysShowHours: false))")
                            .font(.system(.caption2, design: .monospaced).weight(.semibold))
                            .foregroundStyle(themeManager.primaryAccent)
                    }

                    Spacer()

                    Image(systemName: "waveform")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(themeManager.primaryAccent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                playerService.repeatEnabled.toggle()
            } label: {
                Image(systemName: "repeat")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(playerService.repeatEnabled ? .white : .secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(playerService.repeatEnabled ? themeManager.primaryAccent : Color.primary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.playerRepeat)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassCapsule()
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
    }

    // MARK: - 1. Cabecera con Fecha y Hora Exacta Siempre Visible

    private var detailTopHeader: some View {
        VStack(alignment: .leading, spacing: isCompactVertical ? 4 : 6) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    isShowingQuickEditSheet = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(recording.title)
                            .font(isCompactVertical ? .title3.weight(.bold) : .largeTitle.weight(.bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(isCompactVertical ? 1 : 2)
                            .minimumScaleFactor(0.72)
                        Image(systemName: "pencil.circle.fill")
                            .font(isCompactVertical ? .subheadline : .title3)
                            .foregroundStyle(themeManager.primaryAccent)
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }

            // Única línea compacta: Fecha y hora exacta + ícono franja (☀️/🌅/🌙) + etiquetas de la nota
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption2)
                        .foregroundStyle(themeManager.primaryAccent)
                    Text(recording.formattedExactCreationDate)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .fixedSize(horizontal: true, vertical: false)

                Image(systemName: recording.dayPeriod.iconName)
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 24)
                    .background(Color(hex: recording.dayPeriod.badgeColorHex).opacity(0.16), in: Circle())
                    .foregroundStyle(Color(hex: recording.dayPeriod.badgeColorHex))

                if !recording.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(recording.tags) { tag in
                                let tagColor = themeManager.folderColor(for: tag)
                                HStack(spacing: 4) {
                                    Image(systemName: tag.iconName)
                                    Text(tag.localizedName)
                                }
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(tagColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(tagColor)
                            }
                        }
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, isCompactVertical ? 2 : 4)
        .frame(maxWidth: horizontalSizeClass == .regular ? 920 : .infinity)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 2. Buscador Local con Navegación de Coincidencias

    private var localSearchBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(themeManager.primaryAccent)

                TextField(L10n.detailSearchPlaceholder, text: $localSearchQuery)
                    .focused($isLocalSearchFocused)
                    .font(.caption)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        isLocalSearchFocused = false
                    }
                    .onChange(of: localSearchQuery) { _, _ in
                        currentSearchHitIndex = 0
                    }

                if !localSearchQuery.isEmpty {
                    let hits = localSearchHits
                    Text(hits.isEmpty ? "0" : "\(currentSearchHitIndex + 1)/\(hits.count)")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(hits.isEmpty ? .red : themeManager.primaryAccent)

                    Button {
                        guard !hits.isEmpty else { return }
                        currentSearchHitIndex = (currentSearchHitIndex - 1 + hits.count) % hits.count
                        playerService.seek(to: hits[currentSearchHitIndex].timestamp, autoPlay: true)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.bold))
                    }
                    .disabled(hits.isEmpty)

                    Button {
                        guard !hits.isEmpty else { return }
                        currentSearchHitIndex = (currentSearchHitIndex + 1) % hits.count
                        playerService.seek(to: hits[currentSearchHitIndex].timestamp, autoPlay: true)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .disabled(hits.isEmpty)

                    Button {
                        localSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: horizontalSizeClass == .regular ? 860 : .infinity)
    }

    // MARK: - Pestaña 1: Transcripción Interactiva Sincronizada (Karaoke-Style)

    private var karaokeTranscriptTabView: some View {
        let paragraphs = transcriptDisplayMode == .continuousNote
            ? buildContinuousParagraphs(from: recording.segments)
            : []

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !recording.segments.isEmpty {
                        Picker("", selection: $transcriptDisplayMode) {
                            Text(L10n.transcriptModeSpeakers).tag(TranscriptDisplayMode.bySpeaker)
                            Text(L10n.transcriptModeContinuous).tag(TranscriptDisplayMode.continuousNote)
                        }
                        .pickerStyle(.segmented)
                    }

                    if transcriptDisplayMode == .bySpeaker && !recording.speakers.isEmpty {
                        // Leyenda rápida de locutores con botón de renombrado directo
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recording.speakers) { speaker in
                                    Button {
                                        selectedSpeakerIdForRename = speaker.id
                                        isShowingSpeakerRenameSheet = true
                                    } label: {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(speaker.color)
                                                .frame(width: 8, height: 8)
                                            Text(speaker.compactLabel)
                                                .font(.caption2.weight(.bold))
                                            Image(systemName: "pencil")
                                                .font(.system(size: 9))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(speaker.color.opacity(0.14), in: Capsule())
                                        .foregroundStyle(speaker.color)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if recording.segments.isEmpty {
                        transcriptionEmptyOrStatusCard
                    } else {
                        if recording.transcriptionState == .interrupted || recording.transcriptionState == .failed {
                            partialRetryBanner
                        }

                        if transcriptDisplayMode == .continuousNote {
                            continuousNoteTranscriptView(paragraphs: paragraphs)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(recording.segments) { segment in
                                    KaraokeSegmentCardView(
                                        segment: segment,
                                        speaker: recording.speakerProfile(for: segment.speakerId),
                                        isSegmentActive: playerService.activeSegmentId == segment.id,
                                        activeWordId: playerService.activeWordId,
                                        activeAcousticEventId: playerService.activeAcousticEventId,
                                        localSearchQuery: localSearchQuery,
                                        onTapWord: { wordTimestamp in
                                            playerService.seek(to: wordTimestamp.startTime, autoPlay: true)
                                        },
                                        onTapSegmentHeader: {
                                            playerService.seek(to: segment.startTime, autoPlay: true)
                                        },
                                        onTapRenameSpeaker: {
                                            selectedSpeakerIdForRename = segment.speakerId
                                            isShowingSpeakerRenameSheet = true
                                        },
                                        onTapAcousticEvent: { event in
                                            playerService.seek(to: event.timestamp, autoPlay: true)
                                        }
                                    )
                                    .id(segment.id)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 84)
                .frame(maxWidth: horizontalSizeClass == .regular ? 860 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
            .onTapGesture {
                isLocalSearchFocused = false
            }
            .onChange(of: playerService.activeSegmentId) { _, newSegId in
                guard let targetId = newSegId, playerService.isPlaying else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    if transcriptDisplayMode == .continuousNote {
                        if let paragraphMatch = paragraphs.first(where: { $0.segmentIDs.contains(targetId) }) {
                            proxy.scrollTo(paragraphMatch.id, anchor: .center)
                        }
                    } else {
                        proxy.scrollTo(targetId, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Pestaña 2: Resumen, Marcadores en Vivo y Eventos Acústicos

    private var summaryAndBookmarksTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 0. Resumen Inteligente / Post-Procesamiento con IA bajo demanda
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(L10n.aiSummarySectionTitle, systemImage: "sparkles")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(themeManager.primaryAccent)
                        Spacer()
                        Button(L10n.toolbarRefineAI) {
                            isShowingAIRefinementSheet = true
                        }
                        .font(.caption.weight(.bold))
                    }

                    let trimmedSummary = recording.aiSummaryText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedSummary.isEmpty {
                        Button {
                            isShowingAIRefinementSheet = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "wand.and.stars")
                                    .foregroundStyle(themeManager.primaryAccent)
                                Text(L10n.aiSummaryEmptyHint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(trimmedSummary)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if !recording.aiRefinementEngine.isEmpty {
                                Text(recording.aiRefinementEngine)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(themeManager.primaryAccent)
                            }
                        }
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                // 1. Añadir nuevo marcador en el segundo actual de reproducción
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        L10n.detailBookmarks,
                        systemImage: "bookmark.fill"
                    )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PixelTheme.bookmarkAmber)

                    HStack(spacing: 8) {
                        TextField(
                            L10n.detailAddBookmarkAt(ExactDateFormatter.exactAudioPosition(playerService.currentTime)),
                            text: $newPlaybackBookmarkLabel
                        )
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)

                        Button {
                            recording.addBookmark(
                                at: playerService.currentTime,
                                label: newPlaybackBookmarkLabel
                            )
                            newPlaybackBookmarkLabel = ""
                            viewModel.saveChanges()
                        } label: {
                            Label(L10n.mark, systemImage: "plus.circle.fill")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PixelTheme.bookmarkAmber)
                    }

                    if recording.bookmarks.isEmpty {
                        Text(L10n.detailNoBookmarks)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(recording.bookmarks) { bm in
                            HStack {
                                Button {
                                    playerService.seek(to: bm.timestamp, autoPlay: true)
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(bm.formattedTimestamp)
                                            .font(.system(.caption, design: .monospaced).weight(.bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(PixelTheme.bookmarkAmber.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                                            .foregroundStyle(PixelTheme.bookmarkAmber)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(bm.label)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.primary)
                                            if !bm.note.isEmpty {
                                                Text(bm.note)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "play.circle.fill")
                                            .foregroundStyle(themeManager.primaryAccent)
                                    }
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    recording.removeBookmark(id: bm.id)
                                    viewModel.saveChanges()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                // 2. Eventos Acústicos Detectados (SoundAnalysis: Risas, Música, Aplausos, Pausas)
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        L10n.detailAcousticEvents,
                        systemImage: "waveform.badge.magnifyingglass"
                    )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(themeManager.primaryAccent)

                    if recording.acousticEvents.isEmpty {
                        Text(L10n.detailNoAcousticEvents)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recording.acousticEvents) { event in
                            Button {
                                playerService.seek(to: event.timestamp, autoPlay: true)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(event.type.emoji)
                                        .font(.title3)
                                        .frame(width: 34, height: 34)
                                        .background(event.type.color.opacity(0.18), in: Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.formattedInlineTag)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(event.type.color)
                                        Text(L10n.detailAIConfidenceDuration(confidencePct: Int(event.confidence * 100), durationText: String(format: "%.1f", event.duration)))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Label(L10n.jump, systemImage: "play.fill")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(event.type.color.opacity(0.15), in: Capsule())
                                        .foregroundStyle(event.type.color)
                                }
                                .padding(10)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 3. Estadísticas de Intervención por Locutor (Speaker Diarization)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(L10n.detailSpeakerParticipation, systemImage: "person.2.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(themeManager.primaryAccent)
                        Spacer()
                        Button(L10n.detailRenameSpeakers) {
                            selectedSpeakerIdForRename = recording.speakers.first?.id
                            isShowingSpeakerRenameSheet = true
                        }
                        .font(.caption.weight(.bold))
                    }

                    ForEach(recording.speakers) { spk in
                        let ratio = recording.duration > 0 ? min(1.0, spk.totalSpeakingDuration / recording.duration) : 0.5
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Circle()
                                    .fill(spk.color)
                                    .frame(width: 10, height: 10)
                                Text(spk.compactLabel)
                                    .font(.caption.weight(.bold))
                                if spk.customName != nil {
                                    Text("(\(spk.shortBadgeCode))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(L10n.detailWordsDuration(wordCount: spk.wordCount, durationText: ExactDateFormatter.standardDuration(spk.totalSpeakingDuration)))
                                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            ProgressView(value: ratio)
                                .tint(spk.color)

                            Text(L10n.detailMeanPitch(Int(spk.pitchMeanHz)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 84)
            .frame(maxWidth: horizontalSizeClass == .regular ? 860 : .infinity)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Pestaña 3: Detalles Técnicos del Archivo y Exportación

    private var technicalFileDetailsTabView: some View {
        List {
            Section(L10n.detailSectionTimeline) {
                MetadataRow(title: L10n.detailExactCreated, value: recording.formattedExactCreationDate, monospaced: true)
                MetadataRow(title: L10n.detailExactEnded, value: recording.formattedExactEndDate, monospaced: true)
                MetadataRow(title: L10n.detailGroupDate, value: recording.dayGroupKey, monospaced: true)
                MetadataRow(title: L10n.detailDayPeriod, value: recording.dayPeriod.localizedTitle, monospaced: false)
                MetadataRow(title: L10n.detailDurationPrecise, value: recording.formattedPreciseDuration, monospaced: true)
            }

            Section(L10n.detailSectionStorage) {
                MetadataRow(title: L10n.detailFileName, value: recording.audioFileName, monospaced: true)
                MetadataRow(title: L10n.detailFormatCodec, value: recording.audioFormat.displayName, monospaced: false)
                MetadataRow(title: L10n.detailExactSize, value: recording.formattedDetailedFileSize, monospaced: true)
                MetadataRow(title: L10n.detailSampleRate, value: "\(Int(recording.sampleRate)) Hz", monospaced: true)
                MetadataRow(title: L10n.detailBitrate, value: "\(recording.bitRate / 1000) kbps", monospaced: true)
                MetadataRow(title: L10n.detailChannels, value: L10n.detailChannelsMono(recording.channelCount), monospaced: false)
                MetadataRow(title: L10n.detailSHA256, value: recording.sha256Hash.isEmpty ? L10n.detailCalculating : String(recording.sha256Hash.prefix(24)) + "...", monospaced: true)
            }

            Section(L10n.detailSectionAI) {
                MetadataRow(title: L10n.detailEngineUsed, value: recording.transcriptionEngineUsed, monospaced: false)
                MetadataRow(title: L10n.detailDetectedSpeakers, value: "\(recording.speakers.count)", monospaced: true)
                MetadataRow(title: L10n.detailAcousticEvents, value: "\(recording.acousticEvents.count)", monospaced: true)
                MetadataRow(title: L10n.detailSilenceIntervals, value: "\(recording.silenceIntervals.count)", monospaced: true)
            }

            Section(L10n.detailSectionExport) {
                Button {
                    isShowingExportSheet = true
                } label: {
                    Label(L10n.detailExportButton, systemImage: "square.and.arrow.up.fill")
                        .fontWeight(.bold)
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 76)
        }
    }

    // MARK: - 5. Reproductor a Pantalla Completa (Apple Music / Voice Memos)

    private var fullScreenAudioPlayerView: some View {
        Group {
            if isCompactVertical {
                HStack(alignment: .center, spacing: 16) {
                    VStack(spacing: 8) {
                        InteractiveTimelineWaveformView(
                            recording: recording,
                            currentTime: playerService.currentTime,
                            duration: playerService.duration,
                            searchHits: localSearchHits,
                            onSeek: { second in
                                playerService.seek(to: second, autoPlay: true)
                            },
                            isFullScreenExpanded: true,
                            minWaveformHeight: 84
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        playerTimeAndSkipBanner(horizontalPadding: 14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(spacing: 14) {
                        playerTransportControls(compact: true)
                        playerSpeedAndSkipSilences(compact: true)
                    }
                    .frame(maxWidth: 330)
                    .padding(.vertical, 6)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 18) {
                    // Onda interactiva de ancho completo sin caja gris
                    InteractiveTimelineWaveformView(
                        recording: recording,
                        currentTime: playerService.currentTime,
                        duration: playerService.duration,
                        searchHits: localSearchHits,
                        onSeek: { second in
                            playerService.seek(to: second, autoPlay: true)
                        },
                        isFullScreenExpanded: true
                    )
                    .frame(maxWidth: horizontalSizeClass == .regular ? 960 : .infinity, maxHeight: .infinity)
                    .padding(.top, 6)

                    playerTimeAndSkipBanner(horizontalPadding: 22)
                        .frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)

                    playerTransportControls(compact: false)

                    playerSpeedAndSkipSilences(compact: false)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func playerTimeAndSkipBanner(horizontalPadding: CGFloat) -> some View {
        HStack {
            Text(ExactDateFormatter.preciseChronometer(playerService.currentTime, alwaysShowHours: false))
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(themeManager.primaryAccent)

            Spacer()

            if playerService.skipSilenceEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.caption2)
                    Text(
                        playerService.isCurrentlySkippingSilence
                            ? L10n.playerSkippingSilence
                            : L10n.playerSavedSeconds(String(format: "%.1f", playerService.totalSilenceSavedSeconds))
                    )
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .liquidGlassCapsule(tint: PixelTheme.successEmerald.opacity(0.25), interactive: false)
                .foregroundStyle(PixelTheme.successEmerald)
            }

            Spacer()

            Text(ExactDateFormatter.preciseChronometer(playerService.duration, alwaysShowHours: false))
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, horizontalPadding)
    }

    private func playerTransportControls(compact: Bool) -> some View {
        let playSize: CGFloat = compact ? 58 : 72
        let skipSize: CGFloat = compact ? 38 : 44
        let spacing: CGFloat = compact ? 12 : 22

        return HStack(spacing: spacing) {
            Button {
                playerService.skip(by: -10.0)
            } label: {
                Image(systemName: "gobackward.10")
                    .font((compact ? Font.title3 : Font.title2).weight(.semibold))
                    .frame(width: skipSize, height: skipSize)
            }
            .buttonStyle(.plain)

            Button {
                playerService.skip(by: -5.0)
            } label: {
                Image(systemName: "gobackward.5")
                    .font((compact ? Font.title3 : Font.title2).weight(.semibold))
                    .frame(width: skipSize, height: skipSize)
            }
            .buttonStyle(.plain)

            Button {
                playerService.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(themeManager.primaryAccent)
                        .frame(width: playSize, height: playSize)
                        .liquidGlassCircle(tint: themeManager.primaryAccent)
                        .shadow(color: themeManager.primaryAccent.opacity(0.45), radius: 14, x: 0, y: 6)

                    Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                        .font((compact ? Font.title2 : Font.title).weight(.bold))
                        .foregroundStyle(.white)
                        .offset(x: playerService.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)

            Button {
                playerService.skip(by: 5.0)
            } label: {
                Image(systemName: "goforward.5")
                    .font((compact ? Font.title3 : Font.title2).weight(.semibold))
                    .frame(width: skipSize, height: skipSize)
            }
            .buttonStyle(.plain)

            Button {
                playerService.skip(by: 10.0)
            } label: {
                Image(systemName: "goforward.10")
                    .font((compact ? Font.title3 : Font.title2).weight(.semibold))
                    .frame(width: skipSize, height: skipSize)
            }
            .buttonStyle(.plain)
        }
    }

    private func playerSpeedAndSkipSilences(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 12) {
            HStack(spacing: compact ? 6 : 8) {
                ForEach(PlaybackSpeedOption.allCases) { speed in
                    let selected = playerService.playbackSpeed == speed
                    Button {
                        playerService.playbackSpeed = speed
                    } label: {
                        Text(speed.label)
                            .font(.system(size: compact ? 12 : 13, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, compact ? 9 : 12)
                            .padding(.vertical, compact ? 6 : 8)
                            .liquidGlassCapsule(
                                tint: selected ? themeManager.primaryAccent : nil
                            )
                            .foregroundStyle(selected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: compact ? 8 : 10) {
                    skipSilencePill(compact: compact)
                    voiceIsolationPill(compact: compact)
                    repeatPill(compact: compact)
                }
                VStack(spacing: 8) {
                    HStack(spacing: compact ? 8 : 10) {
                        skipSilencePill(compact: compact)
                        voiceIsolationPill(compact: compact)
                    }
                    repeatPill(compact: compact)
                }
                VStack(spacing: 8) {
                    skipSilencePill(compact: compact)
                    voiceIsolationPill(compact: compact)
                    repeatPill(compact: compact)
                }
            }
        }
    }

    private func skipSilencePill(compact: Bool) -> some View {
        audioEnhancementPill(
            title: L10n.playerSkipSilences,
            systemImage: playerService.skipSilenceEnabled ? "bolt.fill" : "bolt.slash",
            isEnabled: playerService.skipSilenceEnabled,
            activeTint: PixelTheme.successEmerald,
            compact: compact
        ) {
            playerService.skipSilenceEnabled.toggle()
        }
    }

    private func voiceIsolationPill(compact: Bool) -> some View {
        audioEnhancementPill(
            title: L10n.playerVoiceIsolation,
            systemImage: playerService.voiceIsolationEnabled ? "person.wave.2.fill" : "person.wave.2",
            isEnabled: playerService.voiceIsolationEnabled,
            activeTint: themeManager.primaryAccent,
            compact: compact
        ) {
            playerService.voiceIsolationEnabled.toggle()
        }
    }

    private func repeatPill(compact: Bool) -> some View {
        audioEnhancementPill(
            title: L10n.playerRepeat,
            systemImage: "repeat",
            isEnabled: playerService.repeatEnabled,
            activeTint: PixelTheme.accentIndigo,
            compact: compact
        ) {
            playerService.repeatEnabled.toggle()
        }
    }

    // MARK: - Vista Continua Tipo Nota de Transcripción (Sin IA requerida)

    private struct ContinuousTranscriptParagraph: Identifiable {
        let id: UUID
        let startTime: TimeInterval
        let segmentIDs: Set<UUID>
        let segments: [TranscriptSegment]
        let plainText: String
    }

    private func continuousNoteTranscriptView(paragraphs: [ContinuousTranscriptParagraph]) -> some View {
        let totalWords = recording.segments.reduce(0) { sum, seg in
            sum + max(seg.words.count, seg.text.split(separator: " ").count)
        }
        let fullNoteText = paragraphs.map(\.plainText).joined(separator: "\n\n")

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label(
                    "\(totalWords)",
                    systemImage: "doc.plaintext"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    UIPasteboard.general.string = fullNoteText
                    withAnimation(.easeInOut(duration: 0.2)) {
                        didCopyContinuousNote = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            didCopyContinuousNote = false
                        }
                    }
                } label: {
                    Label(
                        didCopyContinuousNote ? L10n.transcriptCopied : L10n.transcriptCopyAll,
                        systemImage: didCopyContinuousNote ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(didCopyContinuousNote ? .white : themeManager.primaryAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .liquidGlassCapsule(
                        tint: didCopyContinuousNote ? PixelTheme.successEmerald : themeManager.primaryAccent.opacity(0.14)
                    )
                }
                .buttonStyle(.plain)
            }

            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(paragraphs) { paragraph in
                    VStack(alignment: .leading, spacing: 4) {
                        if paragraphs.count > 1 {
                            Button {
                                playerService.seek(to: paragraph.startTime, autoPlay: true)
                            } label: {
                                Text(ExactDateFormatter.exactAudioPosition(paragraph.startTime))
                                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }

                        Text(attributedParagraphText(for: paragraph))
                            .font(.body)
                            .lineSpacing(6)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id(paragraph.id)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
        }
    }

    private func buildContinuousParagraphs(from segments: [TranscriptSegment]) -> [ContinuousTranscriptParagraph] {
        guard !segments.isEmpty else { return [] }
        var result: [ContinuousTranscriptParagraph] = []
        var buffer: [TranscriptSegment] = []
        var wordCount = 0

        func flushBuffer() {
            guard let first = buffer.first else { return }
            var plain = ""
            for seg in buffer {
                let text = seg.words.isEmpty
                    ? seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    : LocalizationHelper.smartJoinWords(seg.words.map(\.word))
                guard !text.isEmpty else { continue }
                if LocalizationHelper.needsSpaceBetween(previous: plain, next: text) {
                    plain += " " + text
                } else {
                    plain += text
                }
            }
            result.append(
                ContinuousTranscriptParagraph(
                    id: first.id,
                    startTime: first.startTime,
                    segmentIDs: Set(buffer.map(\.id)),
                    segments: buffer,
                    plainText: plain
                )
            )
            buffer.removeAll(keepingCapacity: true)
            wordCount = 0
        }

        for seg in segments {
            if let prev = buffer.last {
                let gap = seg.startTime - prev.endTime
                let prevTrimmed = prev.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let endsSentence = prevTrimmed.last.map { ".?!…。？！".contains($0) } ?? false
                if gap >= 2.0 || (wordCount >= 55 && endsSentence) || wordCount >= 95 {
                    flushBuffer()
                }
            }
            buffer.append(seg)
            wordCount += max(seg.words.count, seg.text.split(separator: " ").count)
        }
        flushBuffer()
        return result
    }

    private func attributedParagraphText(for paragraph: ContinuousTranscriptParagraph) -> AttributedString {
        var output = AttributedString("")
        var plainSoFar = ""
        let query = localSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        for segment in paragraph.segments {
            if !segment.words.isEmpty {
                for word in segment.words {
                    let token = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !token.isEmpty else { continue }
                    if LocalizationHelper.needsSpaceBetween(previous: plainSoFar, next: token) {
                        output.append(AttributedString(" "))
                        plainSoFar += " "
                    }
                    var attr = AttributedString(token)
                    if playerService.activeWordId == word.id {
                        attr.foregroundColor = themeManager.primaryAccent
                        attr.backgroundColor = themeManager.primaryAccent.opacity(0.20)
                        attr.font = .body.weight(.semibold)
                    } else if !query.isEmpty, token.localizedCaseInsensitiveContains(query) {
                        attr.backgroundColor = Color.yellow.opacity(0.38)
                    }
                    output.append(attr)
                    plainSoFar += token
                }
            } else {
                let segText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !segText.isEmpty else { continue }
                if LocalizationHelper.needsSpaceBetween(previous: plainSoFar, next: segText) {
                    output.append(AttributedString(" "))
                    plainSoFar += " "
                }
                var segAttr = AttributedString(segText)
                if !query.isEmpty {
                    var cursor = segText.startIndex
                    while cursor < segText.endIndex,
                          let match = segText.range(
                            of: query,
                            options: [.caseInsensitive, .diacriticInsensitive],
                            range: cursor..<segText.endIndex
                          ) {
                        if let lo = AttributedString.Index(match.lowerBound, within: segAttr),
                           let hi = AttributedString.Index(match.upperBound, within: segAttr) {
                            segAttr[lo..<hi].backgroundColor = Color.yellow.opacity(0.38)
                        }
                        cursor = match.upperBound
                    }
                }
                output.append(segAttr)
                plainSoFar += segText
            }
        }
        return output
    }

    private func audioEnhancementPill(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        activeTint: Color,
        compact: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, compact ? 8 : 9)
            .liquidGlassCapsule(
                tint: isEnabled ? activeTint : nil
            )
            .foregroundStyle(isEnabled ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tarjetas de Estado y Reintento de Transcripción

    private var isProcessingThisNote: Bool {
        recording.transcriptionState == .processing
            || (recording.isProcessingBackground && viewModel.isBackgroundProcessingActive)
    }

    private var transcriptionEmptyOrStatusCard: some View {
        let state = recording.transcriptionState
        let tint = state.badgeColor(
            themeAccent: themeManager.primaryAccent,
            isProcessingBackground: isProcessingThisNote
        )
        let titleText: String = {
            if isProcessingThisNote {
                return L10n.bgTranscriptionKeepOpen
            }
            return state.badgeText(isProcessingBackground: false) ?? L10n.detailNoTranscript
        }()
        let subtitleText: String? = {
            if isProcessingThisNote {
                if viewModel.activeProcessingRecordingID == recording.id,
                   !viewModel.backgroundProcessingStatus.isEmpty {
                    return viewModel.backgroundProcessingStatus
                }
                return nil
            }
            if !recording.transcriptionErrorMessage.isEmpty {
                return recording.transcriptionErrorMessage
            }
            return state != .completed ? state.defaultDetailMessage : nil
        }()

        return VStack(spacing: 12) {
            if isProcessingThisNote {
                ProgressView()
                    .tint(themeManager.primaryAccent)
            } else {
                Image(systemName: state == .completed ? "waveform.and.magnifyingglass" : state.badgeIcon)
                    .font(.largeTitle)
                    .foregroundStyle(tint)
            }

            Text(titleText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isProcessingThisNote ? .primary : tint)
                .multilineTextAlignment(.center)

            if let subtitleText {
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            if !isProcessingThisNote {
                retryTranscriptionButton(
                    title: state == .tooShort ? L10n.transcriptionRetryShortForce : L10n.transcriptionRetryButton,
                    bypassShortAudioFilter: state == .tooShort
                )
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .liquidGlassRoundedRect(cornerRadius: 20, interactive: false)
    }

    private var partialRetryBanner: some View {
        let state = recording.transcriptionState
        let tint = state.badgeColor(themeAccent: themeManager.primaryAccent)
        return HStack(spacing: 10) {
            Image(systemName: state.badgeIcon)
                .foregroundStyle(tint)
            Text(
                !recording.transcriptionErrorMessage.isEmpty
                    ? recording.transcriptionErrorMessage
                    : state.defaultDetailMessage
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            Spacer(minLength: 6)
            retryTranscriptionButton(
                title: L10n.transcriptionRetryButton,
                bypassShortAudioFilter: true
            )
        }
        .padding(12)
        .liquidGlassRoundedRect(cornerRadius: 16, tint: tint.opacity(0.10), interactive: false)
    }

    private func retryTranscriptionButton(title: String, bypassShortAudioFilter: Bool) -> some View {
        Button {
            viewModel.retryTranscription(
                for: recording,
                bypassShortAudioFilter: bypassShortAudioFilter
            )
        } label: {
            Label(title, systemImage: "arrow.clockwise")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .liquidGlassCapsule(tint: themeManager.primaryAccent)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tarjeta de Párrafo de Locutor con Palabras Interactivas (Karaoke) y Etiquetas [😂 Risas - 02:14]

private struct KaraokeSegmentCardView: View {
    let segment: TranscriptSegment
    let speaker: SpeakerProfile
    let isSegmentActive: Bool
    let activeWordId: UUID?
    let activeAcousticEventId: UUID?
    let localSearchQuery: String
    let onTapWord: (WordTimestamp) -> Void
    let onTapSegmentHeader: () -> Void
    let onTapRenameSpeaker: () -> Void
    let onTapAcousticEvent: (AcousticEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cabecera del Locutor + Timestamp Exacto del Bloque
            HStack(spacing: 8) {
                Button(action: onTapRenameSpeaker) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(speaker.color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(speaker.initials)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            )

                        Text(speaker.compactLabel)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(speaker.color)

                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onTapSegmentHeader) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                        Text("\(ExactDateFormatter.exactAudioPosition(segment.startTime)) - \(ExactDateFormatter.exactAudioPosition(segment.endTime))")
                            .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Flujo de palabras interactivo (Karaoke): tocar cualquier palabra salta a ese segundo exacto
            if !segment.words.isEmpty {
                WrappingWordsFlowLayout(spacing: 5, lineSpacing: 6) {
                    ForEach(segment.words) { wordItem in
                        let isWordPlaying = (activeWordId == wordItem.id)
                        let isSearchMatch = matchesLocalSearch(wordItem.word)

                        Button {
                            onTapWord(wordItem)
                        } label: {
                            Text(wordItem.word)
                                .font(.body.weight(isWordPlaying || isSearchMatch ? .bold : .regular))
                                .padding(.horizontal, isWordPlaying || isSearchMatch ? 5 : 2)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(
                                            isWordPlaying
                                                ? speaker.color
                                                : (isSearchMatch ? Color.yellow.opacity(0.45) : Color.clear)
                                        )
                                )
                                .foregroundStyle(isWordPlaying ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !segment.text.isEmpty {
                Button(action: onTapSegmentHeader) {
                    Text(segment.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            // Etiquetas interactivas de Eventos Acústicos incrustados (ej. [😂 Risas - 02:14], [🎵 Música])
            if !segment.inlineEvents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(segment.inlineEvents) { event in
                            let isEventActive = (activeAcousticEventId == event.id)
                            Button {
                                onTapAcousticEvent(event)
                            } label: {
                                HStack(spacing: 5) {
                                    Text(event.formattedInlineTag)
                                        .font(.caption.weight(.bold))
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(isEventActive ? event.type.color : event.type.color.opacity(0.16))
                                )
                                .foregroundStyle(isEventActive ? .white : event.type.color)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(event.type.color.opacity(0.5), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    isSegmentActive
                        ? speaker.color.opacity(0.09)
                        : Color(uiColor: .secondarySystemGroupedBackground)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isSegmentActive ? speaker.color.opacity(0.65) : Color.primary.opacity(0.07),
                    lineWidth: isSegmentActive ? 1.6 : 1.0
                )
        )
    }

    private func matchesLocalSearch(_ word: String) -> Bool {
        let trimmed = localSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normWord = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let normQuery = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return normWord.contains(normQuery)
    }
}

/// Layout fluido (`Layout` protocol nativo de SwiftUI) para alinear palabras interactivas tipo Karaoke con salto de línea automático.
struct WrappingWordsFlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}

private struct MetadataRow: View {
    let title: String
    let value: String
    let monospaced: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced).weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}
