import SwiftUI
import UIKit

/// Vista 1 (Dashboard / Lista Principal):
/// Diseño limpio estilo Apple Mail con filtros colapsables por ícono, buscador global sin bloqueo de teclado,
/// tarjetas minimalistas con fecha y hora exacta al segundo (`DD/MM/YYYY - HH:MM:SS AM/PM`) y botón limpio "Nueva Grabación".
struct DashboardView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var recorderService: AudioRecorderService

    @FocusState private var isSearchFieldFocused: Bool
    @State private var recordingToExport: VoiceRecording?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // 1. Buscador Global Profundo con gestión limpia de foco de teclado
                        globalSearchBarSection

                        // 2. Barras de Filtros Desplegables Estilo Apple Mail (Categorías y Horario)
                        appleMailStyleFiltersSection

                        // 3. Si hay consulta activa en el Buscador Global, mostrar tarjetas de coincidencia exacta al segundo
                        if !viewModel.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            globalDeepMatchesSection
                        }

                        // 4. Listado Principal Agrupado Cronológicamente con Fecha y Hora Exacta hasta el Segundo
                        chronologicalRecordingsListSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 110)
                }
                .scrollDismissesKeyboard(.immediately)
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissKeyboard()
                        }
                )

                // 5. Botón Flotante Inferior Limpio: "Nueva Grabación"
                floatingRecordButtonBar
            }
            .onAppear {
                dismissKeyboard()
            }
            .navigationTitle("PixelVoice Pro")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismissKeyboard()
                        viewModel.isShowingSettingsSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 34, height: 34)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Ajustes")
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
            .onChange(of: viewModel.activeNavigationTarget) { _, _ in
                dismissKeyboard()
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
                RecordingSettingsSheet(
                    viewModel: viewModel,
                    recorderService: recorderService
                )
            }
        }
    }

    private func dismissKeyboard() {
        isSearchFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Subvistas del Dashboard

    private var globalSearchBarSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PixelTheme.accentBlue)
                .font(.body.weight(.semibold))

            TextField("Buscar palabra en todas las notas...", text: $viewModel.globalSearchQuery)
                .focused($isSearchFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    dismissKeyboard()
                }
                .font(.subheadline)

            if !viewModel.globalSearchQuery.isEmpty {
                Button {
                    viewModel.globalSearchQuery = ""
                    dismissKeyboard()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else if isSearchFieldFocused {
                Button("Listo") {
                    dismissKeyboard()
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(PixelTheme.accentBlue)
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
                    isSearchFieldFocused || !viewModel.globalSearchQuery.isEmpty
                        ? PixelTheme.accentBlue.opacity(0.55)
                        : Color.clear,
                    lineWidth: 1.2
                )
        )
    }

    private var appleMailStyleFiltersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Fila 1 (Categorías): Comportamiento colapsable estilo Apple Mail
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    AppleMailFilterPill(
                        title: "Todas",
                        icon: "tray.full.fill",
                        color: PixelTheme.accentBlue,
                        isSelected: viewModel.selectedTagFilter == nil && !viewModel.filterFavoritesOnly
                    ) {
                        dismissKeyboard()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            viewModel.selectedTagFilter = nil
                            viewModel.filterFavoritesOnly = false
                        }
                    }

                    AppleMailFilterPill(
                        title: "Favoritas",
                        icon: "star.fill",
                        color: PixelTheme.bookmarkAmber,
                        isSelected: viewModel.filterFavoritesOnly
                    ) {
                        dismissKeyboard()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            viewModel.filterFavoritesOnly.toggle()
                        }
                    }

                    ForEach(viewModel.availableTags) { tag in
                        AppleMailFilterPill(
                            title: tag.name,
                            icon: tag.iconName,
                            color: tag.color,
                            isSelected: viewModel.selectedTagFilter?.id == tag.id
                        ) {
                            dismissKeyboard()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                if viewModel.selectedTagFilter?.id == tag.id {
                                    viewModel.selectedTagFilter = nil
                                } else {
                                    viewModel.selectedTagFilter = tag
                                }
                            }
                        }
                    }
                }
            }

            // Fila 2 (Horario: Mañana / Tarde / Noche): Sin la palabra "Franja:" y colapsable estilo Apple Mail
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DayPeriod.allCases) { period in
                        let selected = viewModel.filterDayPeriod == period
                        AppleMailFilterPill(
                            title: period.rawValue,
                            icon: period.iconName,
                            color: Color(hex: period.badgeColorHex),
                            isSelected: selected
                        ) {
                            dismissKeyboard()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                viewModel.filterDayPeriod = selected ? nil : period
                            }
                        }
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
                    "Coincidencias Exactas (\(matches.count))",
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
                        dismissKeyboard()
                        viewModel.openRecordingFromSearchMatch(match)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(match.recordingTitle)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer()

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
                    Text("No hay grabaciones disponibles")
                        .font(.headline)
                    Text("Pulsa el botón rojo inferior para iniciar una nueva grabación.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 42)
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 12) {
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
                                    dismissKeyboard()
                                    viewModel.openRecording(recording)
                                },
                                onQuickRenameAndTag: {
                                    dismissKeyboard()
                                    viewModel.recordingPendingQuickEdit = recording
                                },
                                onToggleFavorite: {
                                    viewModel.toggleFavorite(recording)
                                },
                                onExport: {
                                    dismissKeyboard()
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
                dismissKeyboard()
                viewModel.isShowingRecordingBooth = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.24))
                            .frame(width: 34, height: 34)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                    }

                    Spacer()

                    Text("Nueva Grabación")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
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

// MARK: - Tarjeta Individual de Grabación Limpia (Formato DD/MM/YYYY - HH:MM:SS AM/PM + Ícono de Franja + Duración)

private struct RecordingListCardView: View {
    let recording: VoiceRecording
    let onOpen: () -> Void
    let onQuickRenameAndTag: () -> Void
    let onToggleFavorite: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Fila 1: Título Secuencial Limpio (ej. "Grabación 1") + Botones de Acción
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

            // Fila 2: Fecha y Hora Exacta hasta el Segundo (DD/MM/YYYY - HH:MM:SS AM/PM) + Puro Ícono de Franja Horaria (☀️ / 🌅 / 🌙)
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundStyle(PixelTheme.accentBlue)
                    Text(recording.formattedExactCreationDate)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(PixelTheme.accentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                // Únicamente el ícono de la franja horaria (sin el texto "Mañana / Tarde / Noche")
                Image(systemName: recording.dayPeriod.iconName)
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(Color(hex: recording.dayPeriod.badgeColorHex).opacity(0.16), in: Circle())
                    .foregroundStyle(Color(hex: recording.dayPeriod.badgeColorHex))

                Spacer()
            }

            // Fila 3: Únicamente la Duración Exacta (sin peso ni formato técnico exterior)
            HStack(spacing: 12) {
                Label(recording.formattedPreciseDuration, systemImage: "waveform")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if !recording.bookmarks.isEmpty {
                    Label("\(recording.bookmarks.count)", systemImage: "bookmark.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PixelTheme.bookmarkAmber)
                }
            }

            // Fila 4: Mini Onda de Audio + Extracto de Transcripción
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    CompactCardWaveformPreview(
                        samples: recording.waveformSamples,
                        events: recording.acousticEvents,
                        duration: recording.duration
                    )

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

            // Fila 5: Chips de Etiquetas de Color, Locutores y Eventos Acústicos
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
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

/// Píldora de filtro desplegable estilo Apple Mail:
/// Muestra [Ícono + Texto] únicamente cuando está activa/seleccionada; cuando está inactiva muestra solo [Ícono].
private struct AppleMailFilterPill: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isSelected ? 6 : 0) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))

                if isSelected {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .padding(.horizontal, isSelected ? 14 : 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : color)
            .background(
                Capsule()
                    .fill(isSelected ? color : Color.primary.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? color : Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
