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
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
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

/// Paleta de diseño inspirada en Google Pixel Recorder Pro con soporte nativo para Dark Mode.
enum PixelTheme {
    static let accentBlue = Color(hex: "#3B82F6")
    static let accentCyan = Color(hex: "#06B6D4")
    static let accentIndigo = Color(hex: "#6366F1")
    static let recordRed = Color(hex: "#EF4444")
    static let bookmarkAmber = Color(hex: "#F59E0B")
    static let successEmerald = Color(hex: "#10B981")

    /// Colores distintivos asignados automáticamente a cada locutor (Locutor 1, Locutor 2, Locutor 3, etc.)
    static let speakerHexPalette: [String] = [
        "#3B82F6", // Locutor 1: Azul Pixel
        "#10B981", // Locutor 2: Esmeralda
        "#F59E0B", // Locutor 3: Ámbar
        "#EC4899", // Locutor 4: Rosa Intenso
        "#8B5CF6", // Locutor 5: Violeta
        "#06B6D4", // Locutor 6: Cian
        "#F97316", // Locutor 7: Naranja
        "#14B8A6"  // Locutor 8: Turquesa
    ]

    static func colorHex(forSpeakerIndex index: Int) -> String {
        guard !speakerHexPalette.isEmpty else { return "#3B82F6" }
        return speakerHexPalette[abs(index) % speakerHexPalette.count]
    }
}
