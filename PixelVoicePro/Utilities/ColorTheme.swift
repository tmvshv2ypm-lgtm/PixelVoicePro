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
}
