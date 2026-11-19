import SwiftUI
import UIKit

/// Vista 1 (Home de Carpetas Liquid Glass — Voice Notes):
/// Título grande alineado a la izquierda, cuadrícula de carpetas cuadradas translúcidas con Liquid Glass,
/// gestor de carpetas mediante el botón `+` (para crear, mostrar u ocultar categorías con el ojito)
/// y expansión fluida en la barra superior Liquid Glass para búsqueda global.
struct DashboardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var recorderService: AudioRecorderService
    @ObservedObject private var themeManager = ThemeManager.shared

    @FocusState private var isSearchFieldFocused: Bool
    @Namespace private var tagButtonNamespace
    @Namespace private var topGlassNamespace

    @State private var isSearchExpanded: Bool = false
    @State private var recordingToExport: VoiceRecording?
    @State private var showTagManagerSheet: Bool = false

    private var shouldShowSearchBar: Bool {
        isSearchExpanded || !viewModel.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isCompactVertical: Bool {
        verticalSizeClass == .compact
    }

    private var isRegularCanvas: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

    private var maxReadableContentWidth: CGFloat {
        horizontalSizeClass == .regular ? 1040 : .infinity
    }

    private func adaptiveFolderColumns(for containerWidth: CGFloat, horizontalPadding: CGFloat) -> [GridItem] {
        let spacing: CGFloat = 14
        let constrainedWidth = horizontalSizeClass == .regular ? min(containerWidth, maxReadableContentWidth) : containerWidth
        let usableWidth = max(240, constrainedWidth - (horizontalPadding * 2))

        let columnCount: Int
        if usableWidth < 500 {
            // Portrait iPhones (incluyendo Zoom Grande) y iPad Slide Over: siempre 2 columnas limpias
            columnCount = 2
        } else if isRegularCanvas {
            // iPad vertical u horizontal: 3 a 5 columnas balanceadas (~190–225pt por carpeta)
            columnCount = max(3, min(5, Int((usableWidth + spacing) / 205.0)))
        } else {
            // iPhone en modo horizontal (Landscape): 3 a 4 columnas manteniendo el tamaño casi idéntico al vertical
            columnCount = max(3, min(5, Int((usableWidth + spacing) / 160.0)))
        }

        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }

    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            GeometryReader { geo in
                let hPadding: CGFloat = horizontalSizeClass == .regular ? 28 : 16
                let columns = adaptiveFolderColumns(for: geo.size.width, horizontalPadding: hPadding)

                ZStack(alignment: .bottom) {
                    // Fondo ambiental sutil para dar refracción y profundidad real a las carpetas Liquid Glass
                    ambientGlassBackdrop

                    ScrollView {
                        VStack(alignment: .leading, spacing: isCompactVertical ? 12 : 16) {
                            // Título Grande nativo alineado a la izquierda ("Voice Notes")
                            Text(verbatim: "Voice Notes")
                                .font(isCompactVertical ? .title2.weight(.bold) : .largeTitle.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, isCompactVertical ? 0 : 2)

                            // Barra discreta de post-procesamiento en segundo plano
                            if viewModel.isBackgroundProcessingActive {
                                backgroundProcessingBanner
                                    .transition(.opacity)
                            }

                            // Resultados de búsqueda global o cuadrícula adaptativa de carpetas Liquid Glass
                            if !viewModel.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                globalDeepSearchResultsView
                            } else {
                                VStack(spacing: 14) {
                                    liquidGlassFoldersGridSection(columns: columns)

                                    if !viewModel.trashedRecordings.isEmpty {
                                        recentlyDeletedHomePill
                                            .transition(.move(edge: .bottom).combined(with: .opacity))
                                    }
                                }
                                .animation(.spring(response: 0.30, dampingFraction: 0.86), value: viewModel.trashedRecordings.isEmpty)
                            }
                        }
                        .padding(.horizontal, hPadding)
                        .padding(.bottom, isCompactVertical ? 90 : 112)
                        .frame(maxWidth: maxReadableContentWidth)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)

                    // Tocar cualquier zona fuera de la barra expandida la cierra automáticamente
                    if shouldShowSearchBar && viewModel.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                closeSearchBar()
                            }
                            .zIndex(4)
                    }

                    // Botón flotante circular Liquid Glass para grabar desde el Home
                    FloatingRecordButtonBar {
                        dismissKeyboard()
                        viewModel.startRecordingSession()
                    }
                    .zIndex(2)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                morphingTopGlassBar
                    .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
                    .padding(.top, isCompactVertical ? 4 : 6)
                    .padding(.bottom, isCompactVertical ? 4 : 6)
                    .frame(maxWidth: maxReadableContentWidth)
                    .frame(maxWidth: .infinity)
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.isBackgroundProcessingActive)
            .onAppear {
                isSearchFieldFocused = false
            }
            .navigationTitle(Text(verbatim: "Voice Notes"))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: FolderDestination.self) { folder in
                FolderRecordingsView(
                    viewModel: viewModel,
                    folder: folder,
                    onExport: { rec in
                        recordingToExport = rec
                    }
                )
            }
            .navigationDestination(for: RecordingNavigationTarget.self) { target in
                if let recording = viewModel.recording(for: target.recordingId) {
                    RecordingDetailView(
                        viewModel: viewModel,
                        recording: recording,
                        initialSeekTimestamp: target.initialSeekTimestamp,
                        initialSearchKeyword: target.highlightKeyword
                    )
                }
            }
            .onChange(of: viewModel.navigationPath.count) { _, _ in
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
                    .tint(nil)
                    .morphZoomSheetTransition(sourceID: "TAG_MANAGER_SOURCE", in: tagButtonNamespace)
            }
        }
    }

    // MARK: - Fondo Ambiental Sutil

    private var ambientGlassBackdrop: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            Circle()
                .fill(themeManager.primaryAccent.opacity(0.09))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -110, y: -220)

            Circle()
                .fill(themeManager.secondaryGlow.opacity(0.07))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 130, y: 140)
        }
        .ignoresSafeArea()
    }

    // MARK: - Barra Superior con Expansión Liquid Glass de Lupa a Buscador

    @ViewBuilder
    private var morphingTopGlassBar: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if !shouldShowSearchBar {
                        Spacer(minLength: 0)
                    }

                    // Contenedor Liquid Glass de búsqueda que se alarga arriba al tocar la lupa
                    HStack(spacing: 8) {
                        Button {
                            if !shouldShowSearchBar {
                                openSearchBar()
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(shouldShowSearchBar ? themeManager.primaryAccent : .primary)
                                .frame(width: shouldShowSearchBar ? 28 : 42, height: 42)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.searchAccessibility)

                        if shouldShowSearchBar {
                            TextField(L10n.searchPrompt, text: $viewModel.globalSearchQuery)
                                .focused($isSearchFieldFocused)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit {
                                    dismissKeyboard()
                                }
                                .font(.subheadline)
                                .transition(.opacity)

                            Button {
                                closeSearchBar()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.searchCloseAccessibility)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, shouldShowSearchBar ? 12 : 0)
                    .frame(maxWidth: shouldShowSearchBar ? .infinity : 42, minHeight: 42, maxHeight: 44)
                    .glassEffect(
                        shouldShowSearchBar ? .regular : .regular.interactive(),
                        in: .capsule
                    )
                    .glassEffectID("TOP_SEARCH_PILL", in: topGlassNamespace)

                    // Engranaje de Ajustes: se oculta temporalmente mientras la búsqueda está expandida
                    if !shouldShowSearchBar {
                        Button {
                            dismissKeyboard()
                            viewModel.isShowingSettingsSheet = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.semibold))
                                .frame(width: 42, height: 42)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .glassEffectID("TOP_SETTINGS_GEAR", in: topGlassNamespace)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                        .accessibilityLabel(L10n.settingsTitle)
                    }
                }
            }
        } else {
            HStack(spacing: 10) {
                if !shouldShowSearchBar {
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button {
                        if !shouldShowSearchBar {
                            openSearchBar()
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(shouldShowSearchBar ? themeManager.primaryAccent : .primary)
                            .frame(width: shouldShowSearchBar ? 28 : 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.searchAccessibility)

                    if shouldShowSearchBar {
                        TextField(L10n.searchPrompt, text: $viewModel.globalSearchQuery)
                            .focused($isSearchFieldFocused)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .font(.subheadline)

                        Button {
                            closeSearchBar()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.searchCloseAccessibility)
                    }
                }
                .padding(.horizontal, shouldShowSearchBar ? 12 : 0)
                .frame(maxWidth: shouldShowSearchBar ? .infinity : 42, minHeight: 42, maxHeight: 44)
                .liquidGlassCapsule(interactive: false)

                if !shouldShowSearchBar {
                    Button {
                        dismissKeyboard()
                        viewModel.isShowingSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.semibold))
                            .frame(width: 42, height: 42)
                            .liquidGlassCircle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.settingsTitle)
                }
            }
        }
    }

    private func openSearchBar() {
        withAnimation(.snappy(duration: 0.34)) {
            isSearchExpanded = true
        }
    }

    private func closeSearchBar() {
        dismissKeyboard()
        withAnimation(.snappy(duration: 0.32)) {
            viewModel.globalSearchQuery = ""
            isSearchExpanded = false
        }
    }

    private func dismissKeyboard() {
        if isSearchFieldFocused {
            isSearchFieldFocused = false
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Cuadrícula de Carpetas Cuadradas Liquid Glass

    private func liquidGlassFoldersGridSection(columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            FolderLiquidGlassCard(
                title: FolderDestination.all.title,
                iconName: FolderDestination.all.iconName,
                color: themeManager.folderColor(forDestination: .all),
                count: viewModel.recordingCount(for: .all)
            ) {
                viewModel.openFolder(.all)
            }

            FolderLiquidGlassCard(
                title: FolderDestination.favorites.title,
                iconName: FolderDestination.favorites.iconName,
                color: themeManager.folderColor(forDestination: .favorites),
                count: viewModel.recordingCount(for: .favorites)
            ) {
                viewModel.openFolder(.favorites)
            }

            ForEach(viewModel.visibleAvailableTags) { tag in
                let destination = FolderDestination.tag(tag)
                FolderLiquidGlassCard(
                    title: tag.localizedName,
                    iconName: tag.iconName,
                    color: themeManager.folderColor(for: tag),
                    count: viewModel.recordingCount(for: destination)
                ) {
                    viewModel.openFolder(destination)
                }
            }

            // Botón "+" minimalista integrado con exactamente las mismas proporciones que cada carpeta
            Button {
                showTagManagerSheet = true
            } label: {
                LiquidGlassGridTile(
                    tint: themeManager.manageFoldersTileColor.opacity(0.08),
                    interactive: true,
                    alignment: .center
                ) {
                    ZStack {
                        Circle()
                            .fill(themeManager.manageFoldersTileColor.opacity(0.14))
                            .frame(width: 52, height: 52)
                        Image(systemName: "plus")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(themeManager.manageFoldersTileColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .morphTransitionSource(id: "TAG_MANAGER_SOURCE", in: tagButtonNamespace)
            .accessibilityLabel(L10n.foldersManageAccessibility)
        }
    }

    private var recentlyDeletedHomePill: some View {
        NavigationLink {
            RecentlyDeletedView(viewModel: viewModel)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(PixelTheme.recordRed.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PixelTheme.recordRed)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.trashHomeTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(L10n.trashHomeSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                HStack(spacing: 6) {
                    Text("\(viewModel.trashedRecordings.count)")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08), in: Capsule())

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .liquidGlassRoundedRect(cornerRadius: 18, tint: PixelTheme.recordRed.opacity(0.07), interactive: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Resultados de Búsqueda Global

    private var globalDeepSearchResultsView: some View {
        let matches = viewModel.globalDeepSearchMatches
        let matchingRecordings = viewModel.globalSearchMatchingRecordings

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.searchExactMatches(matches.count), systemImage: "text.magnifyingglass")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(themeManager.primaryAccent)
                Spacer()
                Text(L10n.searchTapToJump)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if matches.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(L10n.searchNoResults(viewModel.globalSearchQuery))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlassRoundedRect(cornerRadius: 16, interactive: false)
            } else {
                ForEach(matches.prefix(10)) { match in
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
                                    Text(L10n.searchMinuteBadge(match.formattedExactMinute))
                                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(themeManager.primaryAccent, in: Capsule())
                                .foregroundStyle(.white)
                            }

                            Text(match.recordingExactDate)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)

                            HStack(alignment: .top, spacing: 6) {
                                if let speaker = match.speakerName {
                                    Text("\(speaker):")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(themeManager.primaryAccent)
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
                                .fill(themeManager.primaryAccent.opacity(0.09))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(themeManager.primaryAccent.opacity(0.32), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if !matchingRecordings.isEmpty {
                    Text(L10n.searchMatchingNotes(matchingRecordings.count))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    ForEach(matchingRecordings) { rec in
                        RecordingListCardView(
                            recording: rec,
                            onOpen: {
                                dismissKeyboard()
                                viewModel.openRecording(rec)
                            },
                            onQuickRenameAndTag: {
                                dismissKeyboard()
                                viewModel.recordingPendingQuickEdit = rec
                            },
                            onToggleFavorite: {
                                viewModel.toggleFavorite(rec)
                            },
                            onExport: {
                                dismissKeyboard()
                                recordingToExport = rec
                            },
                            onDelete: {
                                viewModel.deleteRecording(rec)
                            }
                        )
                    }
                }
            }
        }
    }

    private var backgroundProcessingBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.75)
                    .tint(themeManager.primaryAccent)

                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.bgTranscriptionKeepOpen)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    let subtitle = viewModel.backgroundProcessingStatus.isEmpty
                        ? viewModel.backgroundProcessingTitle
                        : "\(viewModel.backgroundProcessingTitle) · \(viewModel.backgroundProcessingStatus)"
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                Text("\(Int(viewModel.backgroundProcessingProgress * 100))%")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(themeManager.primaryAccent)
            }

            ProgressView(value: viewModel.backgroundProcessingProgress, total: 1.0)
                .tint(themeManager.primaryAccent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .liquidGlassCapsule(tint: themeManager.primaryAccent.opacity(0.14), interactive: false)
    }
}

// MARK: - Contenedor y Tarjeta Cuadrada Liquid Glass del Home

/// Contenedor base de cuadrícula que garantiza proporciones idénticas en todas las tarjetas
/// sin importar el tamaño de pantalla o el Zoom de pantalla (Predeterminado / Grande).
private struct LiquidGlassGridTile<Content: View>: View {
    let tint: Color
    let interactive: Bool
    let alignment: Alignment
    @ViewBuilder let content: () -> Content

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(1.02, contentMode: .fit)
            .overlay {
                content()
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .liquidGlassRoundedRect(cornerRadius: 24, tint: tint, interactive: interactive)
    }
}

private struct FolderLiquidGlassCard: View {
    let title: String
    let iconName: String
    let color: Color
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LiquidGlassGridTile(
                tint: color.opacity(0.14),
                interactive: true,
                alignment: .leading
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        ZStack {
                            Circle()
                                .fill(color.opacity(0.22))
                                .frame(width: 46, height: 46)
                            Image(systemName: iconName)
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(color)
                        }

                        Spacer(minLength: 6)

                        Text("\(count)")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }

                    Spacer(minLength: 6)

                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)

                    Text(L10n.folderRecordingCount(count))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Botón Flotante Circular Liquid Glass de Grabación (Compartido entre Home y Carpetas)

struct FloatingRecordButtonBar: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let onTapRecord: () -> Void

    private var isCompactVertical: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        let outerSize: CGFloat = isCompactVertical ? 64 : 74
        let innerSize: CGFloat = isCompactVertical ? 46 : 52

        HStack {
            Spacer()
            Button(action: onTapRecord) {
                ZStack {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: outerSize, height: outerSize)
                        .liquidGlassCircle(tint: PixelTheme.recordRed.opacity(0.16))

                    Circle()
                        .fill(PixelTheme.recordRed)
                        .frame(width: innerSize, height: innerSize)
                        .shadow(color: PixelTheme.recordRed.opacity(0.38), radius: 10, x: 0, y: 4)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.newRecordingAccessibility)
            Spacer()
        }
        .padding(.bottom, isCompactVertical ? 8 : 16)
    }
}

// MARK: - Presentación UI Compartida de Estados de Transcripción

extension TranscriptionProcessingState {
    func badgeText(isProcessingBackground: Bool) -> String? {
        switch self {
        case .processing:
            return L10n.processingShort
        case .interrupted:
            return L10n.transcriptionBadgeInterrupted
        case .failed:
            return L10n.transcriptionBadgeFailed
        case .noSpeechFound:
            return L10n.transcriptionBadgeNoSpeech
        case .tooShort:
            return L10n.transcriptionBadgeTooShort
        case .completed:
            return isProcessingBackground ? L10n.processingShort : nil
        }
    }

    var badgeIcon: String {
        switch self {
        case .processing, .completed:
            return "sparkles"
        case .interrupted:
            return "arrow.clockwise.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .noSpeechFound:
            return "waveform.slash"
        case .tooShort:
            return "timer"
        }
    }

    func badgeColor(themeAccent: Color, isProcessingBackground: Bool = false) -> Color {
        if isProcessingBackground {
            return themeAccent
        }
        switch self {
        case .processing:
            return themeAccent
        case .interrupted:
            return PixelTheme.bookmarkAmber
        case .failed:
            return PixelTheme.recordRed
        case .noSpeechFound, .tooShort, .completed:
            return .secondary
        }
    }

    var defaultDetailMessage: String {
        switch self {
        case .processing:
            return L10n.detailTranscribingBg
        case .completed:
            return L10n.detailNoTranscript
        case .noSpeechFound:
            return L10n.transcriptionStateNoSpeechDetail
        case .tooShort:
            return L10n.transcriptionStateTooShortDetail
        case .interrupted:
            return L10n.transcriptionErrorInterrupted
        case .failed:
            return L10n.transcriptionStateFailedDetail
        }
    }
}

// MARK: - Tarjeta Individual de Grabación Limpia (Compartida en Carpetas y Búsqueda Global)

struct RecordingListCardView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let recording: VoiceRecording
    let onOpen: () -> Void
    let onQuickRenameAndTag: () -> Void
    let onToggleFavorite: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    private var hasFooterChips: Bool {
        !recording.tags.isEmpty || !recording.speakers.isEmpty || !recording.acousticEvents.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Bloque 1: Título + Acciones y fila organizada de Fecha/Franja (izq) <-> Hora exacta (der)
            VStack(alignment: .leading, spacing: 10) {
                headerTitleAndActionsRow
                datePeriodAndTimeRow
            }

            // Bloque 2: Bloque compacto de Duración/Estado + Mini Onda dentro de contenedor suave
            audioStripCard

            // Bloque 3: Extracto de Transcripción legible con respiro
            if !recording.fullTranscriptText.isEmpty {
                Text(recording.fullTranscriptText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2.5)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 2)
            }

            // Bloque 4: Pie ordenado de Etiquetas, Locutores y Eventos Acústicos (solo si hay elementos)
            if hasFooterChips {
                footerChipsSection
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
    }

    private var headerTitleAndActionsRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(recording.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Spacer(minLength: 10)

            HStack(spacing: 4) {
                Button(action: onQuickRenameAndTag) {
                    Image(systemName: "pencil.and.outline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.primaryAccent)
                        .padding(6)
                        .background(themeManager.primaryAccent.opacity(0.12), in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.quickEditAccessibility)

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
                        Label(L10n.renameAndTags, systemImage: "tag.fill")
                    }
                    Button {
                        onExport()
                    } label: {
                        Label(L10n.exportMenuAction, systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(L10n.deleteRecordingAction, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }
        }
    }

    private var datePeriodAndTimeRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                dateWithPeriodPill
                Spacer(minLength: 8)
                timeBadgePill
            }
            VStack(alignment: .leading, spacing: 6) {
                dateWithPeriodPill
                timeBadgePill
            }
        }
    }

    private var dateWithPeriodPill: some View {
        let periodColor = Color(hex: recording.dayPeriod.badgeColorHex)
        return HStack(spacing: 6) {
            Image(systemName: recording.dayPeriod.iconName)
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(periodColor.opacity(0.18), in: Circle())
                .foregroundStyle(periodColor)

            Text(recording.formattedExactDateOnly)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 30)
        .background(periodColor.opacity(0.10), in: Capsule())
    }

    private var timeBadgePill: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.fill")
                .font(.caption2)
                .foregroundStyle(themeManager.primaryAccent)
            Text(recording.formattedExactTimeOnly)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(themeManager.primaryAccent.opacity(0.12), in: Capsule())
    }

    private var audioStripCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(recording.formattedPreciseDuration, systemImage: "waveform")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.primary)

                if let badgeLabel = recording.transcriptionState.badgeText(isProcessingBackground: recording.isProcessingBackground) {
                    Label(badgeLabel, systemImage: recording.transcriptionState.badgeIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            recording.transcriptionState.badgeColor(
                                themeAccent: themeManager.primaryAccent,
                                isProcessingBackground: recording.isProcessingBackground
                            )
                        )
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if !recording.bookmarks.isEmpty {
                    Label("\(recording.bookmarks.count)", systemImage: "bookmark.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PixelTheme.bookmarkAmber)
                }
            }

            CompactCardWaveformPreview(
                samples: recording.waveformSamples,
                events: recording.acousticEvents,
                duration: recording.duration
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.75)
        )
    }

    private var footerChipsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
                .opacity(0.45)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(recording.tags) { tag in
                        let tagColor = themeManager.folderColor(for: tag)
                        HStack(spacing: 4) {
                            Image(systemName: tag.iconName)
                            Text(tag.localizedName)
                        }
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(tagColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(tagColor)
                    }

                    ForEach(recording.speakers) { speaker in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(speaker.color)
                                .frame(width: 6, height: 6)
                            Text(speaker.compactLabel)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(speaker.color.opacity(0.12), in: Capsule())
                        .foregroundStyle(speaker.color)
                    }

                    ForEach(recording.acousticEvents.prefix(4)) { event in
                        Text(event.compactBadgeLabel)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(event.type.color.opacity(0.16), in: Capsule())
                            .foregroundStyle(event.type.color)
                    }
                }
            }
        }
    }
}

/// Píldora de filtro desplegable para franjas horarias dentro de cada carpeta.
struct AppleMailFilterPill: View {
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
