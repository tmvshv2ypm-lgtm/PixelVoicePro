import Foundation
import SwiftUI

/// Periodo cronológico del día para distinguir grabaciones tomadas el mismo día de un solo vistazo.
enum DayPeriod: String, Codable, CaseIterable, Identifiable {
    case morning = "Mañana"
    case afternoon = "Tarde"
    case night = "Noche"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .morning: return L10n.periodMorning
        case .afternoon: return L10n.periodAfternoon
        case .night: return L10n.periodNight
        }
    }

    var iconName: String {
        switch self {
        case .morning: return "sun.max.fill"
        case .afternoon: return "sun.haze.fill"
        case .night: return "moon.stars.fill"
        }
    }

    var badgeColorHex: String {
        switch self {
        case .morning: return "#F59E0B"   // Ámbar cálido
        case .afternoon: return "#F97316" // Naranja solar
        case .night: return "#6366F1"     // Índigo nocturno
        }
    }

    static func from(date: Date, calendar: Calendar = .current) -> DayPeriod {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return .morning
        case 12..<19:
            return .afternoon
        default:
            return .night
        }
    }
}

/// Sistema estricto de formateo de fechas, horas al segundo, duraciones con milisegundos y metadatos de peso.
/// Prohibido el uso de formatos relativos o ambiguos ("Hoy", "Ayer").
enum ExactDateFormatter {
    /// Formato obligatorio para todas las tarjetas y cabeceras: DD/MM/YYYY - HH:MM:SS AM/PM
    /// Ejemplo: 15/11/2026 - 10:25:42 PM
    private static let strictFullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "dd/MM/yyyy - hh:mm:ss a"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter
    }()

    /// Clave de agrupación por día exacto: DD/MM/YYYY (ej. 15/11/2026)
    private static let strictDayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    /// Nombre del día de la semana en el idioma actual del dispositivo acompañado siempre de DD/MM/YYYY
    private static let localizedWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    /// Hora exacta con segundos y AM/PM: HH:MM:SS AM/PM (ej. 10:25:42 PM)
    private static let strictTimeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "hh:mm:ss a"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter
    }()

    /// Formato seguro para nombres de archivo de exportación: DD-MM-YYYY_HH-MM-SS_AM
    private static let fileSafeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "dd-MM-yyyy_hh-mm-ss_a"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter
    }()

    /// Devuelve el string obligatorio `DD/MM/YYYY - HH:MM:SS AM/PM` (ej. `15/11/2026 - 10:25:42 PM`).
    static func fullExactTimestamp(from date: Date) -> String {
        strictFullFormatter.string(from: date)
    }

    /// Devuelve el día exacto `DD/MM/YYYY` para agrupar grabaciones cronológicamente sin ambigüedad.
    static func exactDayKey(from date: Date) -> String {
        strictDayKeyFormatter.string(from: date)
    }

    /// Devuelve la cabecera completa del grupo cronológico en el idioma actual: ej. `Sunday, 15/11/2026`.
    static func chronologicalGroupHeader(from date: Date) -> String {
        localizedWeekdayFormatter.locale = .autoupdatingCurrent
        let weekday = localizedWeekdayFormatter.string(from: date).localizedCapitalized
        let exactDay = strictDayKeyFormatter.string(from: date)
        return "\(weekday), \(exactDay)"
    }

    /// Devuelve únicamente la hora exacta hasta el segundo: `10:25:42 PM`.
    static func exactTimeOnly(from date: Date) -> String {
        strictTimeOnlyFormatter.string(from: date)
    }

    /// Devuelve un timestamp limpio para nombres de archivos exportados.
    static func filenameTimestamp(from date: Date) -> String {
        fileSafeFormatter.string(from: date)
    }

    /// Formatea duración con precisión de centésimas/milisegundos para el cronómetro de cabina y detalles: `HH:MM:SS.cc` o `MM:SS.cc`.
    static func preciseChronometer(_ duration: TimeInterval, alwaysShowHours: Bool = true) -> String {
        let clamped = max(0, duration)
        let totalSeconds = Int(clamped)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let centiseconds = Int((clamped.truncatingRemainder(dividingBy: 1.0)) * 100)

        if alwaysShowHours || hours > 0 {
            return String(format: "%02d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
        } else {
            return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
        }
    }

    /// Formatea duración exacta para tarjetas de listado y etiquetas de eventos: `MM:SS` o `HH:MM:SS`.
    static func standardDuration(_ duration: TimeInterval) -> String {
        let clamped = max(0, duration)
        let totalSeconds = Int(clamped.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// Formatea el instante exacto dentro de un audio con décimas de segundo para búsquedas y marcadores: `MM:SS.d`.
    static func exactAudioPosition(_ timestamp: TimeInterval) -> String {
        let clamped = max(0, timestamp)
        let totalSeconds = Int(clamped)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let tenths = Int((clamped.truncatingRemainder(dividingBy: 1.0)) * 10)

        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%d", hours, minutes, seconds, tenths)
        } else {
            return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
        }
    }

    /// Formatea el peso del archivo en formato legible exacto (`1.84 MB`, `425.2 KB`).
    static func formattedFileSize(bytes: Int64) -> String {
        let clamped = max(0, bytes)
        let kb = Double(clamped) / 1024.0
        if kb < 1024.0 {
            return String(format: "%.1f KB", max(0.1, kb))
        } else {
            let mb = kb / 1024.0
            return String(format: "%.2f MB", mb)
        }
    }

    /// Formatea el peso del archivo incluyendo el conteo exacto de bytes para la pestaña de Detalles.
    static func detailedFileSize(bytes: Int64) -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.locale = .autoupdatingCurrent
        let exactBytesString = numberFormatter.string(from: NSNumber(value: bytes)) ?? "\(bytes)"
        return "\(formattedFileSize(bytes: bytes)) (\(exactBytesString) \(L10n.unitBytes))"
    }
}
