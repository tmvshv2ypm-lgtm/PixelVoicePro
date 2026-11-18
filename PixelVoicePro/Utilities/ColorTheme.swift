import SwiftUI
import UIKit

extension Color {
    /// Inicializa un `Color` de SwiftUI a partir de un código hexadecimal (`#RRGGBB` o `RRGGBB`).
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 99, 102, 241)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }

    /// Convierte un código hexadecimal a `UIColor` para el renderizador de PDF.
    static func uiColor(fromHex hex: String) -> UIColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8) & 0xFF) / 255.0
        let b = CGFloat(int & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}

/// Paleta de diseño minimalista estilo Apple con soporte nativo para Dark Mode y Liquid Glass.
enum PixelTheme {
    static let accentBlue = Color(hex: "#3B82F6")
    static let accentCyan = Color(hex: "#06B6D4")
    static let accentIndigo = Color(hex: "#6366F1")
    static let recordRed = Color(hex: "#EF4444")
    static let bookmarkAmber = Color(hex: "#F59E0B")
    static let successEmerald = Color(hex: "#10B981")

    /// Colores sólidos asignados a cada locutor (L1, L2, L3, etc.)
    static let speakerHexPalette: [String] = [
        "#3B82F6", // L1: Azul Pixel
        "#10B981", // L2: Esmeralda
        "#F59E0B", // L3: Ámbar
        "#EC4899", // L4: Rosa Intenso
        "#8B5CF6", // L5: Violeta
        "#06B6D4", // L6: Cian
        "#F97316", // L7: Naranja
        "#14B8A6"  // L8: Turquesa
    ]

    static func colorHex(forSpeakerIndex index: Int) -> String {
        guard !speakerHexPalette.isEmpty else { return "#3B82F6" }
        return speakerHexPalette[abs(index) % speakerHexPalette.count]
    }
}

// MARK: - Sistema de Temas Visuales Sutiles (Conserva Modo Claro/Oscuro y Liquid Glass)

/// Paletas predeterminadas sutiles que adaptan carpetas Liquid Glass y acentos principales
/// conservando el fondo Claro/Oscuro del sistema, interruptores nativos verdes y semántica funcional.
enum AppVisualTheme: String, CaseIterable, Identifiable, Sendable {
    case original
    case blue
    case rose
    case purple
    case green
    case amber
    case orange
    case cherry

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .original: return L10n.themeOriginalTitle
        case .blue: return L10n.themeBlueTitle
        case .rose: return L10n.themeRoseTitle
        case .purple: return L10n.themePurpleTitle
        case .green: return L10n.themeGreenTitle
        case .amber: return L10n.themeAmberTitle
        case .orange: return L10n.themeOrangeTitle
        case .cherry: return L10n.themeCherryTitle
        }
    }

    var localizedSubtitle: String {
        switch self {
        case .original: return L10n.themeOriginalSubtitle
        case .blue: return L10n.themeBlueSubtitle
        case .rose: return L10n.themeRoseSubtitle
        case .purple: return L10n.themePurpleSubtitle
        case .green: return L10n.themeGreenSubtitle
        case .amber: return L10n.themeAmberSubtitle
        case .orange: return L10n.themeOrangeSubtitle
        case .cherry: return L10n.themeCherrySubtitle
        }
    }

    var primaryAccentHex: String {
        switch self {
        case .original, .blue: return "#3B82F6"
        case .rose: return "#E03E87"
        case .purple: return "#8B5CF6"
        case .green: return "#0EA571"
        case .amber: return "#D97706"
        case .orange: return "#EA6510"
        case .cherry: return "#DC1E47"
        }
    }

    var secondaryGlowHex: String {
        switch self {
        case .original: return "#06B6D4"
        case .blue: return "#38BDF8"
        case .rose: return "#F472B6"
        case .purple: return "#A855F7"
        case .green: return "#34D399"
        case .amber: return "#FBBF24"
        case .orange: return "#FB923C"
        case .cherry: return "#FB7185"
        }
    }

    var primaryAccent: Color {
        Color(hex: primaryAccentHex)
    }

    var secondaryGlow: Color {
        Color(hex: secondaryGlowHex)
    }

    /// Paleta ordenada de 14 tonos diferenciables dentro de la misma familia cromática.
    /// Índices 0 y 1 corresponden a `Todas` y `Favoritas`; 2+ se asignan a carpetas visibles
    /// alternando brillo, saturación y matiz para que tarjetas vecinas nunca se confundan en Liquid Glass.
    var folderHexPalette: [String] {
        switch self {
        case .original:
            return [
                "#3B82F6", "#F59E0B", "#EC4899", "#8B5CF6", "#10B981",
                "#06B6D4", "#14B8A6", "#F43F5E", "#F97316", "#6366F1"
            ]
        case .blue:
            return [
                "#3B82F6", "#06B6D4", "#4338CA", "#4F86C6", "#22D3EE",
                "#1D4ED8", "#818CF8", "#7DD3FC", "#0284C7", "#6366F1",
                "#93C5FD", "#0EA5E9", "#2563EB", "#38BDF8"
            ]
        case .rose:
            return [
                "#E03E87", "#FB7185", "#F9A8D4", "#A61C58", "#E667A2",
                "#FDA4AF", "#DB2777", "#AD4B77", "#F2859B", "#F472B6",
                "#BE185D", "#E88AA8", "#C45485", "#D44B7E"
            ]
        case .purple:
            return [
                "#8B5CF6", "#D946EF", "#D8B4FE", "#6366F1", "#9333EA",
                "#F0ABFC", "#C084FC", "#6229C4", "#A855F7", "#B478D4",
                "#4F46E5", "#7E22CE", "#A78BFA", "#6D28D9"
            ]
        case .green:
            return [
                "#10B981", "#65C466", "#9CE043", "#0D9488", "#86EFAC",
                "#178C45", "#2DD4BF", "#4ADE80", "#0A8762", "#6EE7B7",
                "#16A34A", "#5E9E72", "#059669", "#2E8A5B"
            ]
        case .amber:
            return [
                "#F59E0B", "#FDE047", "#A86416", "#F6AD55", "#FDE68A",
                "#C46210", "#EAB308", "#C68B2C", "#D97706", "#FCD34D",
                "#D49B27", "#FBBF24", "#F7C948", "#CA8A04"
            ]
        case .orange:
            return [
                "#F97316", "#F59E0B", "#B44318", "#FDBA74", "#EA580C",
                "#E76F51", "#FFB347", "#C25E12", "#FF8A5B", "#FF9F43",
                "#CC4D16", "#E07A3F", "#D95D39", "#FB923C"
            ]
        case .cherry:
            return [
                "#E11D48", "#FB7185", "#A11842", "#F7A1A8", "#F43F5E",
                "#AC1B46", "#F28482", "#E85D75", "#BE123C", "#B84054",
                "#E06C78", "#D64550", "#B02A43", "#C83E4D"
            ]
        }
    }

    func folderColor(atSlot slot: Int) -> Color {
        let palette = folderHexPalette
        guard !palette.isEmpty else { return primaryAccent }
        return Color(hex: palette[abs(slot) % palette.count])
    }

    /// 6 muestras representativas de la variedad de tonos para las filas del selector de temas.
    var previewSwatches: [Color] {
        [0, 1, 2, 3, 4, 5].map { folderColor(atSlot: $0) }
    }

    /// 4 tonos para la vista previa 2x2 de carpetas (`Todas`, `Favoritas`, `Ideas`, `Microbiología`).
    var representativeDashboardColors: [Color] {
        switch self {
        case .original:
            return [
                PixelTheme.accentBlue,
                PixelTheme.bookmarkAmber,
                Color(hex: "#EC4899"),
                Color(hex: "#14B8A6")
            ]
        default:
            return [0, 1, 2, 3].map { folderColor(atSlot: $0) }
        }
    }
}

/// Gestor reactivo del tema visual elegido en Configuración (persistente entre sesiones sin alterar SwiftData).
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    private static let storageKey = "com.pixelvoicepro.appearance.theme"

    @Published var currentTheme: AppVisualTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: Self.storageKey)
        }
    }

    private var visibleTagSlotByID: [String: Int] = [:]

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey)
        self.currentTheme = saved.flatMap(AppVisualTheme.init(rawValue:)) ?? .original
    }

    var primaryAccent: Color {
        currentTheme.primaryAccent
    }

    var secondaryGlow: Color {
        currentTheme.secondaryGlow
    }

    var allFolderColor: Color {
        currentTheme == .original ? PixelTheme.accentBlue : currentTheme.folderColor(atSlot: 0)
    }

    var favoritesFolderColor: Color {
        currentTheme == .original ? PixelTheme.bookmarkAmber : currentTheme.folderColor(atSlot: 1)
    }

    var manageFoldersTileColor: Color {
        currentTheme == .original ? PixelTheme.accentBlue : currentTheme.primaryAccent
    }

    func syncVisibleTagOrder(_ orderedVisibleTagIDs: [String]) {
        var mapping: [String: Int] = [:]
        mapping.reserveCapacity(orderedVisibleTagIDs.count)
        for (index, tagID) in orderedVisibleTagIDs.enumerated() {
            mapping[tagID] = index
        }
        visibleTagSlotByID = mapping
    }

    func folderColor(forDestination destination: FolderDestination) -> Color {
        switch destination {
        case .all:
            return allFolderColor
        case .favorites:
            return favoritesFolderColor
        case .tag(let tag):
            return folderColor(for: tag)
        }
    }

    func folderColor(for tag: TagItem) -> Color {
        guard currentTheme != .original else {
            return tag.color
        }
        let reservedTailCount = max(1, currentTheme.folderHexPalette.count - 2)
        if let visibleIndex = visibleTagSlotByID[tag.id] {
            return currentTheme.folderColor(atSlot: 2 + (visibleIndex % reservedTailCount))
        }
        let fallbackOffset = Int(Self.stableFNV1aHash(tag.id) % UInt64(reservedTailCount))
        return currentTheme.folderColor(atSlot: 2 + fallbackOffset)
    }

    private static func stableFNV1aHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}

// MARK: - Modificadores Liquid Glass Nativos (iOS 26+ con fallback elegante)

extension View {
    /// Aplica efecto Liquid Glass circular nativo en iOS 26+ (o material translúcido cristalizado en versiones anteriores).
    @ViewBuilder
    func liquidGlassCircle(tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                if interactive {
                    self.glassEffect(.regular.tint(tint).interactive(), in: .circle)
                } else {
                    self.glassEffect(.regular.tint(tint), in: .circle)
                }
            } else {
                if interactive {
                    self.glassEffect(.regular.interactive(), in: .circle)
                } else {
                    self.glassEffect(.regular, in: .circle)
                }
            }
        } else {
            self
                .background(
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        if let tint {
                            Circle().fill(tint.opacity(0.65))
                        }
                    }
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.45), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                )
        }
    }

    /// Aplica efecto Liquid Glass en forma de cápsula para barras flotantes e indicadores discretos.
    @ViewBuilder
    func liquidGlassCapsule(tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                if interactive {
                    self.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
                } else {
                    self.glassEffect(.regular.tint(tint), in: .capsule)
                }
            } else {
                if interactive {
                    self.glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    self.glassEffect(.regular, in: .capsule)
                }
            }
        } else {
            self
                .background(
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        if let tint {
                            Capsule().fill(tint.opacity(0.28))
                        }
                    }
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                )
        }
    }

    /// Aplica efecto Liquid Glass en tarjetas/carpetas cuadradas con bordes redondeados suaves.
    @ViewBuilder
    func liquidGlassRoundedRect(cornerRadius: CGFloat = 24, tint: Color? = nil, interactive: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            if let tint {
                if interactive {
                    self.glassEffect(.regular.tint(tint).interactive(), in: shape)
                } else {
                    self.glassEffect(.regular.tint(tint), in: shape)
                }
            } else {
                if interactive {
                    self.glassEffect(.regular.interactive(), in: shape)
                } else {
                    self.glassEffect(.regular, in: shape)
                }
            }
        } else {
            self
                .background(
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        if let tint {
                            shape.fill(tint.opacity(0.25))
                        }
                    }
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.32), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
                )
        }
    }

    /// Marca el botón origen para transiciones de zoom continuas en iOS 18+.
    @ViewBuilder
    func morphTransitionSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Aplica transición fluida tipo zoom desde el botón origen hacia una hoja/sheet en iOS 18+.
    @ViewBuilder
    func morphZoomSheetTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }

    /// Detecta el gesto de deslizar hacia abajo al soltar el dedo al inicio de un `List`/`ScrollView` en iOS 18+,
    /// permitiendo que el rebote elástico vuelva a `0` suavemente sin quedar pegado ni congelar la barra superior.
    @ViewBuilder
    func onSafePullDownReleaseReveal(threshold: CGFloat = 48.0, action: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollPhaseChange { oldPhase, newPhase, context in
                if oldPhase == .interacting && newPhase != .interacting {
                    let pullDistance = -(context.geometry.contentOffset.y + context.geometry.contentInsets.top)
                    if pullDistance > threshold {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            action()
                        }
                    }
                }
            }
        } else {
            self
        }
    }
}
