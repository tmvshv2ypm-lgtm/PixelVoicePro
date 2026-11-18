import SwiftUI

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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @ObservedObject var viewModel: AppViewModel
    let recording: VoiceRecording
    let initialSeekTimestamp: TimeInterval?
    let initialSearchKeyword: String?

    private var isCompactVertical: Bool {
        verticalSizeClass == .compact
    }

    @StateObject private var playerService = AudioPlayerService()

    @FocusState private var isLocalSearchFocused: Bool
    @State private var selectedTab: DetailTab = .player
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

                // 2. Barra discreta si esta nota aún está terminando su análisis en 2º plano
                if recording.isProcessingBackground && viewModel.isBackgroundProcessingActive {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(PixelTheme.accentBlue)
                        Text(viewModel.backgroundProcessingStatus.isEmpty ? L10n.processingBackgroundShort : viewModel.backgroundProcessingStatus)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(viewModel.backgroundProcessingProgress * 100))%")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(PixelTheme.accentBlue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(PixelTheme.accentBlue.opacity(0.08))
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
        }
        .sheet(isPresented: $isShowingSpeakerRenameSheet) {
            SpeakerRenameSheet(
                recording: recording,
                initialSpeakerId: selectedSpeakerIdForRename,
                onSaved: {
                    viewModel.saveChanges()
                }
            )
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
                                .fill(isSelected ? PixelTheme.accentBlue : Color.clear)
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
                        .fill(PixelTheme.accentBlue)
                        .frame(width: 40, height: 40)
                        .liquidGlassCircle(tint: PixelTheme.accentBlue)
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
                            .foregroundStyle(PixelTheme.accentBlue)
                    }

                    Spacer()

                    Image(systemName: "waveform")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PixelTheme.accentBlue)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                            .foregroundStyle(PixelTheme.accentBlue)
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
                        .foregroundStyle(PixelTheme.accentBlue)
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
                                HStack(spacing: 4) {
                                    Image(systemName: tag.iconName)
                                    Text(tag.localizedName)
                                }
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(tag.color.opacity(0.15), in: Capsule())
                                .foregroundStyle(tag.color)
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
                    .foregroundStyle(PixelTheme.accentBlue)

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
                        .foregroundStyle(hits.isEmpty ? .red : PixelTheme.accentBlue)

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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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

                    if recording.segments.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: recording.isProcessingBackground ? "sparkles" : "waveform.and.magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(recording.isProcessingBackground ? PixelTheme.accentBlue : .secondary)
                            Text(
                                recording.isProcessingBackground
                                    ? L10n.detailTranscribingBg
                                    : L10n.detailNoTranscript
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
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
                if let targetId = newSegId, playerService.isPlaying {
                    withAnimation(.easeInOut(duration: 0.25)) {
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
                            .foregroundStyle(PixelTheme.accentBlue)
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
                                    .foregroundStyle(PixelTheme.accentBlue)
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
                                    .foregroundStyle(PixelTheme.accentBlue)
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
                                            .foregroundStyle(PixelTheme.accentBlue)
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
                    .foregroundStyle(PixelTheme.accentCyan)

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
                            .foregroundStyle(PixelTheme.accentBlue)
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
                .foregroundStyle(PixelTheme.accentBlue)

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
                        .fill(PixelTheme.accentBlue)
                        .frame(width: playSize, height: playSize)
                        .liquidGlassCircle(tint: PixelTheme.accentBlue)
                        .shadow(color: PixelTheme.accentBlue.opacity(0.45), radius: 14, x: 0, y: 6)

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
                                tint: selected ? PixelTheme.accentBlue : nil
                            )
                            .foregroundStyle(selected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                playerService.skipSilenceEnabled.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: playerService.skipSilenceEnabled ? "bolt.fill" : "bolt.slash")
                    Text(L10n.playerSkipSilences)
                        .lineLimit(1)
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 16)
                .padding(.vertical, compact ? 8 : 9)
                .liquidGlassCapsule(
                    tint: playerService.skipSilenceEnabled ? PixelTheme.successEmerald : nil
                )
                .foregroundStyle(playerService.skipSilenceEnabled ? .white : .primary)
            }
            .buttonStyle(.plain)
        }
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
