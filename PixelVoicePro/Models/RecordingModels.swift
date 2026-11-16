import Foundation
import AVFoundation
import SwiftUI

// MARK: - Configuración de Formato de Audio

enum AudioFormatOption: String, Codable, CaseIterable, Identifiable {
    case m4a = "m4a"
    case wav = "wav"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .m4a: return "AAC Alta Fidelidad (.m4a)"
        case .wav: return "Linear PCM Sin Pérdida (.wav)"
        }
    }

    var shortBadge: String {
        switch self {
        case .m4a: return "M4A · AAC"
        case .wav: return "WAV · PCM"
        }
    }

    var descriptionText: String {
        switch self {
        case .m4a:
            return "Compresión inteligente de alta nitidez vocal (~1.1 MB/min). Ideal para clases largas, entrevistas y uso diario."
        case .wav:
            return "Audio de estudio sin compresión (~5.5 MB/min). Máximo rango dinámico para análisis acústico profundo."
        }
    }

    var formatID: AudioFormatID {
        switch self {
        case .m4a: return kAudioFormatMPEG4AAC
        case .wav: return kAudioFormatLinearPCM
        }
    }

    func audioSettings(sampleRate: Double, channels: Int = 1, bitRate: Int = 192_000) -> [String: Any] {
        let resolvedChannels = max(1, min(2, channels))
        switch self {
        case .m4a:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: resolvedChannels,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
                AVEncoderBitRateKey: bitRate
            ]
        case .wav:
            return [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: resolvedChannels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
    }
}

enum SampleRateOption: Double, Codable, CaseIterable, Identifiable {
    case hz44100 = 44100.0
    case hz48000 = 48000.0

    var id: Double { rawValue }

    var displayLabel: String {
        switch self {
        case .hz44100: return "44.1 kHz (Estándar CD)"
        case .hz48000: return "48.0 kHz (Estudio Pro)"
        }
    }
}

enum PlaybackSpeedOption: Float, Codable, CaseIterable, Identifiable {
    case x0_5 = 0.5
    case x1_0 = 1.0
    case x1_25 = 1.25
    case x1_5 = 1.5
    case x2_0 = 2.0

    var id: Float { rawValue }

    var label: String {
        switch self {
        case .x0_5: return "0.5x"
        case .x1_0: return "1.0x"
        case .x1_25: return "1.25x"
        case .x1_5: return "1.5x"
        case .x2_0: return "2.0x"
        }
    }
}

// MARK: - Etiquetas de Colores (Tags)

struct TagItem: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var colorHex: String
    var iconName: String

    var color: Color {
        Color(hex: colorHex)
    }

    static let predefinedTags: [TagItem] = [
        TagItem(id: "tag_universidad", name: "Universidad", colorHex: "#3B82F6", iconName: "graduationcap.fill"),
        TagItem(id: "tag_clases", name: "Clases", colorHex: "#8B5CF6", iconName: "book.closed.fill"),
        TagItem(id: "tag_entrevistas", name: "Entrevistas", colorHex: "#10B981", iconName: "mic.badge.plus"),
        TagItem(id: "tag_trabajo", name: "Trabajo", colorHex: "#F59E0B", iconName: "briefcase.fill"),
        TagItem(id: "tag_ideas", name: "Ideas", colorHex: "#EC4899", iconName: "lightbulb.fill"),
        TagItem(id: "tag_reunion", name: "Reuniones", colorHex: "#06B6D4", iconName: "person.3.fill")
    ]
}

// MARK: - Identificación de Locutores (Speaker Diarization)

struct SpeakerProfile: Identifiable, Codable, Hashable {
    var id: String
    var speakerNumber: Int
    var defaultLabel: String
    var customName: String?
    var colorHex: String
    var pitchMeanHz: Double
    var spectralCentroidHz: Double
    var totalSpeakingDuration: TimeInterval
    var wordCount: Int

    /// Nombre visible en toda la nota: usa el nombre real asignado por el usuario o "Locutor X" por defecto.
    var displayName: String {
        if let custom = customName?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        return defaultLabel
    }

    var initials: String {
        let components = displayName.split(separator: " ")
        if components.count >= 2,
           let first = components.first?.first,
           let second = components.dropFirst().first?.first {
            return "\(first)\(second)".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    var color: Color {
        Color(hex: colorHex)
    }

    static func createDefault(number: Int, pitchHz: Double = 145.0, centroidHz: Double = 1650.0) -> SpeakerProfile {
        SpeakerProfile(
            id: "speaker_\(number)",
            speakerNumber: number,
            defaultLabel: "Locutor \(number)",
            customName: nil,
            colorHex: PixelTheme.colorHex(forSpeakerIndex: number - 1),
            pitchMeanHz: pitchHz,
            spectralCentroidHz: centroidHz,
            totalSpeakingDuration: 0,
            wordCount: 0
        )
    }
}

// MARK: - Eventos Acústicos y Sonidos No Verbales (SoundAnalysis / IA)

enum AcousticEventType: String, Codable, CaseIterable, Identifiable {
    case laughter = "laughter"
    case applause = "applause"
    case music = "music"
    case sigh = "sigh"
    case longPause = "long_pause"
    case cough = "cough"

    var id: String { rawValue }

    var spanishTitle: String {
        switch self {
        case .laughter: return "Risas"
        case .applause: return "Aplausos"
        case .music: return "Música"
        case .sigh: return "Suspiro"
        case .longPause: return "Pausa larga"
        case .cough: return "Tos / Carraspeo"
        }
    }

    var emoji: String {
        switch self {
        case .laughter: return "😂"
        case .applause: return "👏"
        case .music: return "🎵"
        case .sigh: return "😮‍💨"
        case .longPause: return "⏸️"
        case .cough: return "🤧"
        }
    }

    var sfSymbol: String {
        switch self {
        case .laughter: return "face.smiling.inverse"
        case .applause: return "hands.clap.fill"
        case .music: return "music.note.list"
        case .sigh: return "wind"
        case .longPause: return "pause.circle.fill"
        case .cough: return "waveform.badge.exclamationmark"
        }
    }

    var colorHex: String {
        switch self {
        case .laughter: return "#F59E0B"   // Amarillo/Ámbar vibrante
        case .applause: return "#10B981"   // Verde esmeralda
        case .music: return "#EC4899"      // Magenta/Rosa musical
        case .sigh: return "#06B6D4"       // Cian suave
        case .longPause: return "#64748B"  // Gris pizarra
        case .cough: return "#F97316"      // Naranja alerta
        }
    }

    var color: Color {
        Color(hex: colorHex)
    }
}

struct AcousticEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var type: AcousticEventType
    var timestamp: TimeInterval
    var duration: TimeInterval
    var confidence: Double

    /// Etiqueta visual estilo Google Pixel: ej. `[😂 Risas - 02:14]` o `[🎵 Música - 01:05]`
    var formattedInlineTag: String {
        let timeStr = ExactDateFormatter.standardDuration(timestamp)
        return "[\(type.emoji) \(type.spanishTitle) - \(timeStr)]"
    }

    /// Etiqueta corta para badges compactos
    var compactBadgeLabel: String {
        "\(type.emoji) \(type.spanishTitle) · \(ExactDateFormatter.standardDuration(timestamp))"
    }
}

// MARK: - Sincronización Palabra por Palabra (Karaoke-style) y Segmentos

struct WordTimestamp: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var word: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var confidence: Float
    var speakerId: String

    func isActive(at playbackTime: TimeInterval) -> Bool {
        playbackTime >= startTime && playbackTime <= max(endTime, startTime + 0.18)
    }
}

struct TranscriptSegment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var speakerId: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var words: [WordTimestamp]
    var inlineEvents: [AcousticEvent]

    func contains(time: TimeInterval) -> Bool {
        time >= startTime && time <= max(endTime, startTime + 0.25)
    }
}

// MARK: - Marcadores en Vivo (Bookmarks) y Silencios

struct RecordingBookmark: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var timestamp: TimeInterval
    var label: String
    var note: String
    var createdAt: Date
    var colorHex: String = "#F59E0B"

    var formattedTimestamp: String {
        ExactDateFormatter.exactAudioPosition(timestamp)
    }

    var formattedCreatedAtExact: String {
        ExactDateFormatter.fullExactTimestamp(from: createdAt)
    }
}

struct SilenceInterval: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var startTime: TimeInterval
    var endTime: TimeInterval

    var duration: TimeInterval {
        max(0, endTime - startTime)
    }

    func contains(_ time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }
}

// MARK: - Resultados de Búsqueda Profunda Global y Local

struct LocalWordSearchHit: Identifiable, Hashable {
    let id = UUID()
    let segmentId: UUID
    let wordId: UUID?
    let matchedWord: String
    let contextSnippet: String
    let timestamp: TimeInterval
    let speakerId: String

    var formattedTime: String {
        ExactDateFormatter.exactAudioPosition(timestamp)
    }
}

struct GlobalSearchMatch: Identifiable, Hashable {
    let id = UUID()
    let recordingId: UUID
    let recordingTitle: String
    let recordingExactDate: String
    let matchSource: MatchSource
    let matchedText: String
    let contextSnippet: String
    let timestamp: TimeInterval
    let speakerName: String?

    enum MatchSource: String, Hashable {
        case transcriptWord = "Palabra en Transcripción"
        case bookmark = "Marcador de Tiempo"
        case acousticEvent = "Evento Acústico"
        case speaker = "Locutor"
        case titleOrTag = "Título / Etiqueta"
    }

    var formattedExactMinute: String {
        ExactDateFormatter.exactAudioPosition(timestamp)
    }
}
