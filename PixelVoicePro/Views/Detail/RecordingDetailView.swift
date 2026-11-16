import SwiftUI

/// Vista 3 (Detalle y Reproducción Interactiva):
/// Panel superior con pestañas ("Transcripción completa", "Resumen/Marcadores", "Detalles del archivo"),
/// sincronización Karaoke palabra por palabra, buscador local con pines en la onda, renombrado de locutores y reproductor Pro abajo.
struct RecordingDetailView: View {
    enum DetailTab: String, CaseIterable, Identifiable {
        case transcript = "Transcripción"
        case summaryAndBookmarks = "Resumen / Marcadores"
        case fileDetails = "Detalles del Archivo"

        var id: String { rawValue }
    }

    @ObservedObject var viewModel: AppViewModel
    let recording: VoiceRecording
    let initialSeekTimestamp: TimeInterval?
    let initialSearchKeyword: String?

    @StateObject private var playerService = AudioPlayerService()

    @FocusState private var isLocalSearchFocused: Bool
    @State private var selectedTab: DetailTab = .transcript
    @State private var localSearchQuery: String = ""
    @State private var currentSearchHitIndex: Int = 0
    @State private var selectedSpeakerIdForRename: String?
    @State private var isShowingSpeakerRenameSheet: Bool = false
    @State private var isShowingQuickEditSheet: Bool = false
    @State private var isShowingExportSheet: Bool = false
    @State private var newPlaybackBookmarkLabel: String = ""

    private var localSearchHits: [LocalWordSearchHit] {
        recording.searchLocalOccurrences(query: localSearchQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Cabecera Fija con Título Editable y Fecha/Hora Exacta Obligatoria debajo
            detailTopHeader

            // 2. Barra de Búsqueda Local dentro de la Grabación (resalta en texto y en la línea de tiempo del audio)
            localSearchBar

            // 3. Selector de Pestañas Superior
            Picker("Vista de Detalle", selection: $selectedTab) {
                ForEach(DetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // 4. Contenido del Panel Superior según la Pestaña Activa
            Group {
                switch selectedTab {
                case .transcript:
                    karaokeTranscriptTabView
                case .summaryAndBookmarks:
                    summaryAndBookmarksTabView
                case .fileDetails:
                    technicalFileDetailsTabView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // 5. Reproductor Pro Inferior con Onda Interactiva, Velocidad y "Saltar Silencios"
            interactiveBottomPlayerDock
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    selectedSpeakerIdForRename = recording.speakers.first?.id
                    isShowingSpeakerRenameSheet = true
                } label: {
                    Label("Locutores", systemImage: "person.2.wave.2.fill")
                }

                Button {
                    isShowingExportSheet = true
                } label: {
                    Label("Exportar", systemImage: "square.and.arrow.up")
                }
            }
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
            }
            if let jumpTime = initialSeekTimestamp, jumpTime > 0 {
                playerService.seek(to: jumpTime, autoPlay: true)
            }
        }
        .onDisappear {
            playerService.stop()
        }
    }

    // MARK: - 1. Cabecera con Fecha y Hora Exacta Siempre Visible

    private var detailTopHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    isShowingQuickEditSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Text(recording.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Image(systemName: "pencil.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(PixelTheme.accentBlue)
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }

            // Fecha y hora exacta hasta el segundo obligatoria debajo del título (sin peso ni formato técnico repetido)
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption2)
                        .foregroundStyle(PixelTheme.accentBlue)
                    Text(recording.formattedExactCreationDate)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(.primary)
                }

                Image(systemName: recording.dayPeriod.iconName)
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 24)
                    .background(Color(hex: recording.dayPeriod.badgeColorHex).opacity(0.16), in: Circle())
                    .foregroundStyle(Color(hex: recording.dayPeriod.badgeColorHex))

                Spacer()
            }

            // Etiquetas de color activas
            if !recording.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recording.tags) { tag in
                            HStack(spacing: 4) {
                                Image(systemName: tag.iconName)
                                Text(tag.name)
                            }
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(tag.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(tag.color)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    // MARK: - 2. Buscador Local con Navegación de Coincidencias

    private var localSearchBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PixelTheme.accentBlue)

                TextField("Buscar palabra en esta grabación...", text: $localSearchQuery)
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
                                        Text(speaker.displayName)
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
                            Image(systemName: "waveform.and.magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Esta grabación no contiene palabras transcritas.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    } else {
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
                .padding(16)
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
                // 1. Añadir nuevo marcador en el segundo actual de reproducción
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        "Marcadores de Tiempo (Bookmarks · \(recording.bookmarks.count))",
                        systemImage: "bookmark.fill"
                    )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PixelTheme.bookmarkAmber)

                    HStack(spacing: 8) {
                        TextField(
                            "Añadir marcador en \(ExactDateFormatter.exactAudioPosition(playerService.currentTime))...",
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
                            Label("Marcar", systemImage: "plus.circle.fill")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PixelTheme.bookmarkAmber)
                    }

                    if recording.bookmarks.isEmpty {
                        Text("No hay marcadores en esta nota. Puedes añadirlos en vivo mientras grabas o aquí durante la reproducción.")
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
                        "Eventos Acústicos No Verbales (SoundAnalysis · \(recording.acousticEvents.count))",
                        systemImage: "waveform.badge.magnifyingglass"
                    )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PixelTheme.accentCyan)

                    if recording.acousticEvents.isEmpty {
                        Text("No se detectaron eventos no verbales (risas, aplausos, música o pausas largas) en esta grabación.")
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
                                        Text("Confianza IA: \(Int(event.confidence * 100))% · Duración: \(String(format: "%.1fs", event.duration))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Label("Saltar", systemImage: "play.fill")
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
                        Label("Participación por Locutor", systemImage: "person.2.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PixelTheme.accentBlue)
                        Spacer()
                        Button("Renombrar Locutores") {
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
                                Text(spk.displayName)
                                    .font(.caption.weight(.bold))
                                if spk.customName != nil {
                                    Text("(\(spk.defaultLabel))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(spk.wordCount) palabras · \(ExactDateFormatter.standardDuration(spk.totalSpeakingDuration))")
                                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            ProgressView(value: ratio)
                                .tint(spk.color)

                            Text("Frecuencia fundamental media (Pitch F0): \(Int(spk.pitchMeanHz)) Hz")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Pestaña 3: Detalles Técnicos Exhaustivos del Archivo y Exportación

    private var technicalFileDetailsTabView: some View {
        List {
            Section("Cronología Exacta (Sin Ambigüedades)") {
                MetadataRow(title: "Creación Exacta", value: recording.formattedExactCreationDate, monospaced: true)
                MetadataRow(title: "Finalización Exacta", value: recording.formattedExactEndDate, monospaced: true)
                MetadataRow(title: "Fecha de Agrupación", value: recording.dayGroupKey, monospaced: true)
                MetadataRow(title: "Franja del Día", value: recording.dayPeriod.rawValue, monospaced: false)
                MetadataRow(title: "Duración con Centésimas", value: recording.formattedPreciseDuration, monospaced: true)
            }

            Section("Archivo de Audio y Almacenamiento") {
                MetadataRow(title: "Nombre de Archivo", value: recording.audioFileName, monospaced: true)
                MetadataRow(title: "Formato y Códec", value: recording.audioFormat.displayName, monospaced: false)
                MetadataRow(title: "Peso Exacto", value: recording.formattedDetailedFileSize, monospaced: true)
                MetadataRow(title: "Frecuencia de Muestreo", value: "\(Int(recording.sampleRate)) Hz", monospaced: true)
                MetadataRow(title: "Bitrate", value: "\(recording.bitRate / 1000) kbps", monospaced: true)
                MetadataRow(title: "Canales", value: "\(recording.channelCount) (Mono Vocal)", monospaced: false)
                MetadataRow(title: "SHA-256 Integridad", value: String(recording.sha256Hash.prefix(24)) + "...", monospaced: true)
            }

            Section("Motor de IA y Análisis Acústico") {
                MetadataRow(title: "Motor Utilizado", value: recording.transcriptionEngineUsed, monospaced: false)
                MetadataRow(title: "Locutores Detectados", value: "\(recording.speakers.count)", monospaced: true)
                MetadataRow(title: "Eventos Acústicos", value: "\(recording.acousticEvents.count)", monospaced: true)
                MetadataRow(title: "Intervalos de Silencio", value: "\(recording.silenceIntervals.count)", monospaced: true)
            }

            Section("Acciones de Exportación Limpia") {
                Button {
                    isShowingExportSheet = true
                } label: {
                    Label("Abrir Menú de Exportación (Audio, PDF, Markdown, TXT o Paquete)", systemImage: "square.and.arrow.up.fill")
                        .fontWeight(.bold)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 5. Reproductor Pro Inferior con Onda Interactiva, Velocidad y "Saltar Silencios"

    private var interactiveBottomPlayerDock: some View {
        VStack(spacing: 10) {
            // Onda interactiva con pines de eventos acústicos, marcadores y búsqueda local
            InteractiveTimelineWaveformView(
                recording: recording,
                currentTime: playerService.currentTime,
                duration: playerService.duration,
                searchHits: localSearchHits,
                onSeek: { second in
                    playerService.seek(to: second, autoPlay: true)
                }
            )
            .padding(.horizontal, 16)

            // Indicadores de tiempo exacto + estado de "Saltar silencios"
            HStack {
                Text(ExactDateFormatter.preciseChronometer(playerService.currentTime, alwaysShowHours: false))
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(PixelTheme.accentBlue)

                Spacer()

                if playerService.skipSilenceEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.caption2)
                        Text(
                            playerService.isCurrentlySkippingSilence
                                ? "¡Saltando silencio!"
                                : "Silencios ahorrados: \(String(format: "%.1fs", playerService.totalSilenceSavedSeconds))"
                        )
                        .font(.caption2.weight(.bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(PixelTheme.successEmerald.opacity(0.16), in: Capsule())
                    .foregroundStyle(PixelTheme.successEmerald)
                }

                Spacer()

                Text(ExactDateFormatter.preciseChronometer(playerService.duration, alwaysShowHours: false))
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            // Controles de transporte Pro: -10s, -5s, Play/Pause, +5s, +10s
            HStack(spacing: 18) {
                Button {
                    playerService.skip(by: -10.0)
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "gobackward.10")
                            .font(.title3.weight(.semibold))
                        Text("-10s")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .buttonStyle(.plain)

                Button {
                    playerService.skip(by: -5.0)
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "gobackward.5")
                            .font(.title3.weight(.semibold))
                        Text("-5s")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .buttonStyle(.plain)

                Button {
                    playerService.togglePlayPause()
                } label: {
                    Image(systemName: playerService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(PixelTheme.accentBlue)
                        .shadow(color: PixelTheme.accentBlue.opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)

                Button {
                    playerService.skip(by: 5.0)
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "goforward.5")
                            .font(.title3.weight(.semibold))
                        Text("+5s")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .buttonStyle(.plain)

                Button {
                    playerService.skip(by: 10.0)
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "goforward.10")
                            .font(.title3.weight(.semibold))
                        Text("+10s")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
            }

            // Fila inferior del reproductor: Velocidad (0.5x, 1.0x, 1.25x, 1.5x, 2.0x) y Toggle "Saltar silencios"
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(PlaybackSpeedOption.allCases) { speed in
                        let selected = playerService.playbackSpeed == speed
                        Button {
                            playerService.playbackSpeed = speed
                        } label: {
                            Text(speed.label)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(
                                    selected ? PixelTheme.accentBlue : Color.primary.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                                .foregroundStyle(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                Button {
                    playerService.skipSilenceEnabled.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: playerService.skipSilenceEnabled ? "bolt.fill" : "bolt.slash")
                        Text("Saltar silencios")
                    }
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        playerService.skipSilenceEnabled
                            ? PixelTheme.successEmerald
                            : Color.primary.opacity(0.08),
                        in: Capsule()
                    )
                    .foregroundStyle(playerService.skipSilenceEnabled ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
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

                        Text(speaker.displayName)
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
        let normWord = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        let normQuery = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
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
