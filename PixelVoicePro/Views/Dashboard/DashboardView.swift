import SwiftUI

/// Vista 1 (Dashboard / Lista Principal):
/// Incluye buscador global profundo con salto a minuto exacto, filtros por etiquetas de colores y franja horaria,
/// agrupación cronológica estricta con formato `DD/MM/YYYY - HH:MM:SS AM/PM`, renombrado rápido y botón flotante de grabación.
struct DashboardView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var recorderService: AudioRecorderService

    @State private var recordingToExport: VoiceRecording?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 1. Cabecera de Estado y Almacenamiento
                        dashboardHeaderMetrics

                        // 2. Buscador Global Profundo (Busca dentro de todas las transcripciones y muestra minuto exacto)
                        globalSearchBarSection

                        // 3. Filtros por Etiquetas de Colores y Franja Horaria (Mañana / Tarde / Noche)
                        tagAndPeriodFiltersSection

                        // 4. Si hay consulta activa en el Buscador Global, mostrar tarjetas de coincidencia exacta al segundo
                        if !viewModel.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            globalDeepMatchesSection
                        }

                        // 5. Listado Principal Agrupado Cronológicamente con Fecha y Hora Exacta hasta el Segundo
                        chronologicalRecordingsListSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 120) // Espacio para el botón flotante de grabación
                }

                // 6. Botón Flotante Grande y Accesible para Iniciar Nueva Grabación al Instante
                floatingRecordButtonBar
            }
            .navigationTitle("PixelVoice Pro")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.isShowingSettingsSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3")
                            Text(recorderService.selectedFormat.rawValue.uppercased())
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
            }
            .navigationDestination(item: $viewModel.activeNavigationTarget) { target in
                if let recording = viewModel.recording(for: target.recordingId) {
                    RecordingDetailView(
                        viewModel: viewModel,
                        recording: recording,
                        initialSeekTimestamp: target.initialSeekTimestamp,
                        initialSearchKeyword: target.highlightKeyword
                    )
                }
            }
            .fullScreenCover(isPresented: $viewModel.isShowingRecordingBooth) {
                RecordingBoothView(
                    viewModel: viewModel,
                    recorderService: recorderService
                )
            }
            .sheet(item: $viewModel.recordingPendingQuickEdit) { rec in
                QuickRenameAndTagSheet(viewModel: viewModel, recording: rec)
            }
            .sheet(item: $recordingToExport) { rec in
                ExportOptionsSheet(recording: rec)
            }
            .sheet(isPresented: $viewModel.isShowingSettingsSheet) {
                RecordingSettingsSheet(recorderService: recorderService)
            }
        }
    }

    // MARK: - Subvistas del Dashboard

    private var dashboardHeaderMetrics: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BIBLIOTECA DE PRECISIÓN CRONOLÓGICA")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PixelTheme.accentBlue)
                Text("\(viewModel.recordings.count) notas · \(viewModel.formattedTotalStorageUsed) en total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                    .foregroundStyle(PixelTheme.successEmerald)
                Text(ExactDateFormatter.exactTimeOnly(from: Date()))
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }

    private var globalSearchBarSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PixelTheme.accentBlue)
                .font(.body.weight(.semibold))

            TextField("Buscar palabra en todas las notas, locutores o risas...", text: $viewModel.globalSearchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)

            if !viewModel.globalSearchQuery.isEmpty {
                Button {
                    viewModel.globalSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    viewModel.globalSearchQuery.isEmpty ? Color.clear : PixelTheme.accentBlue.opacity(0.55),
                    lineWidth: 1.2
                )
        )
    }

    private var tagAndPeriodFiltersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Filtro por Etiquetas de Colores
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChipButton(
                        title: "Todas",
                        icon: "tray.full.fill",
                        color: PixelTheme.accentBlue,
                        isSelected: viewModel.selectedTagFilter == nil && !viewModel.filterFavoritesOnly
                    ) {
                        viewModel.selectedTagFilter = nil
                        viewModel.filterFavoritesOnly = false
                    }

                    FilterChipButton(
                        title: "Favoritas",
                        icon: "star.fill",
                        color: PixelTheme.bookmarkAmber,
                        isSelected: viewModel.filterFavoritesOnly
                    ) {
                        viewModel.filterFavoritesOnly.toggle()
                    }

                    ForEach(viewModel.availableTags) { tag in
                        FilterChipButton(
                            title: tag.name,
                            icon: tag.iconName,
                            color: tag.color,
                            isSelected: viewModel.selectedTagFilter?.id == tag.id
                        ) {
                            if viewModel.selectedTagFilter?.id == tag.id {
                                viewModel.selectedTagFilter = nil
                            } else {
                                viewModel.selectedTagFilter = tag
                            }
                        }
                    }
                }
            }

            // Filtro rápido por Franja del Día (Mañana / Tarde / Noche) para distinguir varias notas del mismo día
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Franja:")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach(DayPeriod.allCases) { period in
                        let selected = viewModel.filterDayPeriod == period
                        Button {
                            viewModel.filterDayPeriod = selected ? nil : period
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: period.iconName)
                                Text(period.rawValue)
                            }
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .foregroundStyle(selected ? .white : Color(hex: period.badgeColorHex))
                            .background(
                                Capsule()
                                    .fill(selected ? Color(hex: period.badgeColorHex) : Color(hex: period.badgeColorHex).opacity(0.14))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var globalDeepMatchesSection: some View {
        let matches = viewModel.globalDeepSearchMatches
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    "Coincidencias Exactas en el Texto (\(matches.count))",
                    systemImage: "text.magnifyingglass"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(PixelTheme.accentBlue)

                Spacer()

                Text("Toca para saltar al segundo exacto")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if matches.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No se encontró \"\(viewModel.globalSearchQuery)\" en ninguna grabación.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(matches.prefix(12)) { match in
                    Button {
                        viewModel.openRecordingFromSearchMatch(match)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(match.recordingTitle)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer()

                                // Muestra el minuto y segundo exacto en que se pronunció la palabra
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 8))
                                    Text("Minuto \(match.formattedExactMinute)")
                                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(PixelTheme.accentBlue, in: Capsule())
                                .foregroundStyle(.white)
                            }

                            Text(match.recordingExactDate)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)

                            HStack(alignment: .top, spacing: 6) {
                                if let speaker = match.speakerName {
                                    Text("\(speaker):")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(PixelTheme.accentCyan)
                                }
                                Text("\"\(match.contextSnippet)\"")
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(PixelTheme.accentBlue.opacity(0.09))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(PixelTheme.accentBlue.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var chronologicalRecordingsListSection: some View {
        let groups = viewModel.chronologicalDayGroups
        return VStack(alignment: .leading, spacing: 20) {
            if groups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 44))
                        .foregroundStyle(PixelTheme.accentBlue.opacity(0.7))
                    Text("No hay grabaciones que coincidan con el filtro")
                        .font(.headline)
                    Text("Pulsa el botón rojo inferior para grabar una nueva nota de voz con fecha y hora exacta al segundo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 42)
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        // Cabecera de agrupación por fecha exacta (nunca dice "Hoy" ni "Ayer" sin fecha completa)
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(PixelTheme.accentBlue)
                            Text(group.headerTitle)
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            Text("\(group.recordings.count) nota(s)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.07), in: Capsule())
                        }
                        .padding(.top, 4)

                        ForEach(group.recordings) { recording in
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
                                    recordingToExport = recording
                                },
                                onDelete: {
                                    viewModel.deleteRecording(recording)
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var floatingRecordButtonBar: some View {
        HStack {
            Button {
                viewModel.isShowingRecordingBooth = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.24))
                            .frame(width: 36, height: 36)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 16, height: 16)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Nueva Grabación Inteligente")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Transcripción en vivo · Diarización · SoundAnalysis")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                    }

                    Spacer()

                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(
                    LinearGradient(
                        colors: [PixelTheme.recordRed, Color(hex: "#DC2626")],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .shadow(color: PixelTheme.recordRed.opacity(0.42), radius: 14, x: 0, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

// MARK: - Tarjeta Individual de Grabación con Formato Obligatorio DD/MM/YYYY - HH:MM:SS AM/PM

private struct RecordingListCardView: View {
    let recording: VoiceRecording
    let onOpen: () -> Void
    let onQuickRenameAndTag: () -> Void
    let onToggleFavorite: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Fila 1: Título + Botones de Renombrado Rápido, Favorito y Menú
            HStack(alignment: .top, spacing: 8) {
                Button(action: onOpen) {
                    Text(recording.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)

                Spacer()

                // Botón de un toque para renombrar y asignar etiquetas de color rápidamente
                Button(action: onQuickRenameAndTag) {
                    Image(systemName: "pencil.and.outline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PixelTheme.accentBlue)
                        .padding(6)
                        .background(PixelTheme.accentBlue.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Renombrar y etiquetar nota")

                Button(action: onToggleFavorite) {
                    Image(systemName: recording.isFavorite ? "star.fill" : "star")
                        .font(.subheadline)
                        .foregroundStyle(recording.isFavorite ? PixelTheme.bookmarkAmber : .secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        onQuickRenameAndTag()
                    } label: {
                        Label("Renombrar y Etiquetas", systemImage: "tag.fill")
                    }
                    Button {
                        onExport()
                    } label: {
                        Label("Exportar (Audio / PDF / MD / TXT)", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Eliminar Grabación", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }

            // Fila 2 (PRIORIDAD MÁXIMA): Fecha y Hora Exacta hasta el Segundo: DD/MM/YYYY - HH:MM:SS AM/PM
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundStyle(PixelTheme.accentBlue)
                    Text(recording.formattedExactCreationDate)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(PixelTheme.accentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                // Etiqueta de franja del día (Mañana, Tarde, Noche)
                HStack(spacing: 4) {
                    Image(systemName: recording.dayPeriod.iconName)
                    Text(recording.dayPeriod.rawValue)
                }
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: recording.dayPeriod.badgeColorHex).opacity(0.16), in: Capsule())
                .foregroundStyle(Color(hex: recording.dayPeriod.badgeColorHex))

                Spacer()
            }

            // Fila 3: Metadatos Exactos de Duración, Peso del Archivo y Formato
            HStack(spacing: 12) {
                Label(recording.formattedPreciseDuration, systemImage: "waveform")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.primary)

                Label(recording.formattedFileSize, systemImage: "internaldrive.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(recording.audioFormat.shortBadge)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.secondary)

                Spacer()

                if !recording.bookmarks.isEmpty {
                    Label("\(recording.bookmarks.count)", systemImage: "bookmark.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PixelTheme.bookmarkAmber)
                }
            }

            // Fila 4: Mini Onda de Audio con colores de eventos acústicos
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    CompactCardWaveformPreview(
                        samples: recording.waveformSamples,
                        events: recording.acousticEvents,
                        duration: recording.duration
                    )

                    // Vista previa de la transcripción
                    if !recording.fullTranscriptText.isEmpty {
                        Text(recording.fullTranscriptText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .buttonStyle(.plain)

            // Fila 5: Chips de Etiquetas de Color, Locutores y Eventos Acústicos ([😂 Risas], [🎵 Música])
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Etiquetas de color
                    ForEach(recording.tags) { tag in
                        HStack(spacing: 4) {
                            Image(systemName: tag.iconName)
                            Text(tag.name)
                        }
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tag.color.opacity(0.16), in: Capsule())
                        .foregroundStyle(tag.color)
                    }

                    // Locutores identificados
                    ForEach(recording.speakers) { speaker in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(speaker.color)
                                .frame(width: 6, height: 6)
                            Text(speaker.displayName)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(speaker.color.opacity(0.12), in: Capsule())
                        .foregroundStyle(speaker.color)
                    }

                    // Eventos acústicos detectados (Risas, Aplausos, Música, Pausas)
                    ForEach(recording.acousticEvents.prefix(4)) { event in
                        Text(event.compactBadgeLabel)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(event.type.color.opacity(0.16), in: Capsule())
                            .foregroundStyle(event.type.color)
                    }
                }
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
}

private struct FilterChipButton: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? .white : color)
            .background(
                Capsule()
                    .fill(isSelected ? color : color.opacity(0.13))
            )
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
