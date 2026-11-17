import SwiftUI
import UIKit

/// Vista 1 (Dashboard / Lista Principal):
/// Diseño limpio estilo Apple Mail con filtros colapsables por ícono, buscador global sin bloqueo de teclado,
/// tarjetas minimalistas con fecha y hora exacta al segundo (`DD/MM/YYYY - HH:MM:SS AM/PM`) y botón limpio "Nueva Grabación".
struct DashboardView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var recorderService: AudioRecorderService

    @FocusState private var isSearchFieldFocused: Bool
    @Namespace private var tagButtonNamespace
    @State private var isSearchExpanded: Bool = false
    @State private var recordingToExport: VoiceRecording?
    @State private var showTagManagerSheet: Bool = false

    private var shouldShowSearchBar: Bool {
        isSearchExpanded || !viewModel.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 1. List como raíz para que el título grande nativo ("PixelVoice Pro") y Swipe Actions funcionen al 100%
                List {
                    if viewModel.isBackgroundProcessingActive {
                        backgroundProcessingBanner
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    appleMailStyleFiltersSection
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if !viewModel.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Section {
                            globalDeepMatchesSection
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    chronologicalRecordingsListRows

                    Color.clear
                        .frame(height: 92)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 8)
                .scrollBounceBehavior(.always, axes: .vertical)
                .scrollDismissesKeyboard(.interactively)
                .onSafePullDownReleaseReveal(threshold: 46.0) {
                    if !isSearchExpanded {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        openSearchBar()
                    }
                }

                // Tocar fuera de la barra cuando está desplegada y sin texto la cierra automáticamente
                if shouldShowSearchBar && viewModel.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeSearchBar()
                        }
                        .zIndex(5)
                }

                // Botón Flotante Circular Liquid Glass (estilo Apple Voice Memos)
                floatingRecordButtonBar
                    .zIndex(2)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if shouldShowSearchBar {
                    globalSearchBarSection
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.86), value: shouldShowSearchBar)
            .animation(.easeInOut(duration: 0.25), value: viewModel.isBackgroundProcessingActive)
            .onAppear {
                isSearchFieldFocused = false
            }
            .navigationTitle("PixelVoice Pro")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        toggleSearchBar()
                    } label: {
                        Image(systemName: shouldShowSearchBar ? "xmark" : "magnifyingglass")
                            .font(.body.weight(.medium))
                    }
                    .accessibilityLabel(shouldShowSearchBar ? "Cerrar búsqueda" : "Buscar notas")

                    if !shouldShowSearchBar {
                        Button {
                            dismissKeyboard()
                            viewModel.isShowingSettingsSheet = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.medium))
                        }
                        .accessibilityLabel("Ajustes")
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
            .sheet(isPresented: $showTagManagerSheet) {
                TagManagerSheet(viewModel: viewModel, mode: .filterLibrary)
                    .morphZoomSheetTransition(sourceID: "TAG_MANAGER_SOURCE", in: tagButtonNamespace)
            }
        }
    }

    private var backgroundProcessingBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.75)
                    .tint(PixelTheme.accentBlue)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Procesando \(viewModel.backgroundProcessingTitle)")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    if !viewModel.backgroundProcessingStatus.isEmpty {
                        Text(viewModel.backgroundProcessingStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                Text("\(Int(viewModel.backgroundProcessingProgress * 100))%")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(PixelTheme.accentBlue)
            }

            ProgressView(value: viewModel.backgroundProcessingProgress, total: 1.0)
                .tint(PixelTheme.accentBlue)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .liquidGlassCapsule(tint: PixelTheme.accentBlue.opacity(0.14), interactive: false)
    }

    private func openSearchBar() {
        isSearchExpanded = true
    }

    private func closeSearchBar() {
        dismissKeyboard()
        viewModel.globalSearchQuery = ""
        isSearchExpanded = false
    }

    private func toggleSearchBar() {
        if shouldShowSearchBar {
            closeSearchBar()
        } else {
            openSearchBar()
        }
    }

    private func dismissKeyboard() {
        if isSearchFieldFocused {
            isSearchFieldFocused = false
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Subvistas del Dashboard

    private var globalSearchBarSection: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PixelTheme.accentBlue)
                    .font(.subheadline.weight(.semibold))

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
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Color.clear
                    .liquidGlassCapsule(
                        tint: isSearchFieldFocused ? PixelTheme.accentBlue.opacity(0.14) : nil,
                        interactive: false
                    )
            )
            .task {
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled, isSearchExpanded else { return }
                isSearchFieldFocused = true
            }

            Button("Cancelar") {
                closeSearchBar()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PixelTheme.accentBlue)
            .lineLimit(1)
            .fixedSize()
        }
    }

    private var appleMailStyleFiltersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Fila 1 (Categorías): Comportamiento colapsable estilo Apple Mail
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    AppleMailFilterPill(
                        title: "Todas",
                        icon: "tray.full.fill",
                        color: PixelTheme.accentBlue,
                        isSelected: viewModel.selectedTagFilter == nil && !viewModel.filterFavoritesOnly
                    ) {
                        if isSearchFieldFocused { dismissKeyboard() }
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
                        if isSearchFieldFocused { dismissKeyboard() }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            viewModel.filterFavoritesOnly.toggle()
                        }
                    }

                    if let activeTag = viewModel.selectedTagFilter {
                        AppleMailFilterPill(
                            title: activeTag.name,
                            icon: activeTag.iconName,
                            color: activeTag.color,
                            isSelected: true
                        ) {
                            if isSearchFieldFocused { dismissKeyboard() }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                viewModel.selectedTagFilter = nil
                            }
                        }
                    }

                    Button {
                        if isSearchFieldFocused { dismissKeyboard() }
                        showTagManagerSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 34, height: 34)
                            .liquidGlassCircle(interactive: false)
                    }
                    .buttonStyle(.borderless)
                    .morphTransitionSource(id: "TAG_MANAGER_SOURCE", in: tagButtonNamespace)
                    .accessibilityLabel("Seleccionar, crear u ocultar etiquetas")
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()

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
                            if isSearchFieldFocused { dismissKeyboard() }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                viewModel.filterDayPeriod = selected ? nil : period
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
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

    @ViewBuilder
    private var chronologicalRecordingsListRows: some View {
        let groups = viewModel.chronologicalDayGroups
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
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            ForEach(groups) { group in
                Section {
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
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteRecording(recording)
                            } label: {
                                Label("Eliminar", systemImage: "trash.fill")
                            }

                            Button {
                                viewModel.toggleFavorite(recording)
                            } label: {
                                Label(
                                    recording.isFavorite ? "Quitar" : "Favorita",
                                    systemImage: recording.isFavorite ? "star.slash.fill" : "star.fill"
                                )
                            }
                            .tint(PixelTheme.bookmarkAmber)

                            Button {
                                dismissKeyboard()
                                viewModel.recordingPendingQuickEdit = recording
                            } label: {
                                Label("Etiquetas", systemImage: "folder.badge.plus")
                            }
                            .tint(PixelTheme.accentBlue)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                dismissKeyboard()
                                recordingToExport = recording
                            } label: {
                                Label("Exportar", systemImage: "square.and.arrow.up.fill")
                            }
                            .tint(.indigo)
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(PixelTheme.accentBlue)
                        Text(group.headerTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(group.recordings.count) nota(s)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                    .padding(.vertical, 2)
                }
                .listSectionSeparator(.hidden)
            }
        }
    }

    private var floatingRecordButtonBar: some View {
        HStack {
            Spacer()
            Button {
                dismissKeyboard()
                viewModel.isShowingRecordingBooth = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 74, height: 74)
                        .liquidGlassCircle(tint: PixelTheme.recordRed.opacity(0.16))

                    Circle()
                        .fill(PixelTheme.recordRed)
                        .frame(width: 52, height: 52)
                        .shadow(color: PixelTheme.recordRed.opacity(0.38), radius: 10, x: 0, y: 4)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nueva Grabación")
            Spacer()
        }
        .padding(.bottom, 16)
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
                Text(recording.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer()

                Button(action: onQuickRenameAndTag) {
                    Image(systemName: "pencil.and.outline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PixelTheme.accentBlue)
                        .padding(6)
                        .background(PixelTheme.accentBlue.opacity(0.12), in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Renombrar y etiquetar nota")

                Button(action: onToggleFavorite) {
                    Image(systemName: recording.isFavorite ? "star.fill" : "star")
                        .font(.subheadline)
                        .foregroundStyle(recording.isFavorite ? PixelTheme.bookmarkAmber : .secondary)
                        .padding(6)
                }
                .buttonStyle(.borderless)

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

                if recording.isProcessingBackground {
                    Label("Analizando...", systemImage: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PixelTheme.accentBlue)
                }

                Spacer()

                if !recording.bookmarks.isEmpty {
                    Label("\(recording.bookmarks.count)", systemImage: "bookmark.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PixelTheme.bookmarkAmber)
                }
            }

            // Fila 4: Mini Onda de Audio + Extracto de Transcripción
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
                            Text(speaker.compactLabel)
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
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
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
        .buttonStyle(.borderless)
    }
}
