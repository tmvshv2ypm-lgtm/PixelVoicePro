import Foundation
import SwiftData

/// Modelo persistente principal de SwiftData para cada nota de voz de PixelVoice Pro.
/// Almacena metadatos de fecha y hora exacta hasta el segundo, archivo de audio, transcripción sincronizada,
/// diarización de locutores, eventos acústicos (SoundAnalysis) y marcadores en vivo.
@Model
final class VoiceRecording {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var endedAt: Date

    /// Cadena obligatoria pre-calculada en formato exacto: DD/MM/YYYY - HH:MM:SS AM/PM
    var exactTimestampString: String

    /// Clave de agrupación cronológica exacta por día: DD/MM/YYYY
    var dayGroupKey: String

    /// Franja del día (Mañana, Tarde, Noche) para distinguir notas grabadas el mismo día
    var dayPeriodRaw: String

    /// Nombre del archivo de audio almacenado en Documents/PixelVoiceRecordings/
    var audioFileName: String
    var formatRaw: String
    var sampleRate: Double
    var bitRate: Int
    var channelCount: Int
    var duration: TimeInterval
    var fileSizeBytes: Int64
    var sha256Hash: String
    var isFavorite: Bool
    var isProcessingBackground: Bool = false
    var transcriptionEngineUsed: String

    /// Texto completo plano indexable para búsquedas globales ultrarrápidas
    var fullTranscriptText: String

    /// Datos serializados en JSON para colecciones estructuradas de alta densidad
    var tagsData: Data
    var speakersData: Data
    var segmentsData: Data
    var acousticEventsData: Data
    var bookmarksData: Data
    var waveformSamplesData: Data
    var silenceIntervalsData: Data

    /// Cachés en memoria (@Transient) para evitar decodificar JSON a 60 Hz durante reproducción o scroll en clases de varias horas
    @Transient private var cachedTags: [TagItem]?
    @Transient private var cachedTagsByteCount: Int = -1
    @Transient private var cachedSpeakers: [SpeakerProfile]?
    @Transient private var cachedSpeakersByteCount: Int = -1
    @Transient private var cachedSegments: [TranscriptSegment]?
    @Transient private var cachedSegmentsByteCount: Int = -1
    @Transient private var cachedEvents: [AcousticEvent]?
    @Transient private var cachedEventsByteCount: Int = -1
    @Transient private var cachedBookmarks: [RecordingBookmark]?
    @Transient private var cachedBookmarksByteCount: Int = -1
    @Transient private var cachedWaveform: [Float]?
    @Transient private var cachedWaveformByteCount: Int = -1
    @Transient private var cachedSilences: [SilenceInterval]?
    @Transient private var cachedSilencesByteCount: Int = -1

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date,
        endedAt: Date? = nil,
        audioFileName: String,
        format: AudioFormatOption = .m4a,
        sampleRate: Double = 48000.0,
        bitRate: Int = 192000,
        channelCount: Int = 1,
        duration: TimeInterval,
        fileSizeBytes: Int64,
        sha256Hash: String = "",
        isFavorite: Bool = false,
        isProcessingBackground: Bool = false,
        transcriptionEngineUsed: String = "Apple Speech On-Device + PixelVoice DSP Diarizer",
        tags: [TagItem] = [],
        speakers: [SpeakerProfile] = [],
        segments: [TranscriptSegment] = [],
        acousticEvents: [AcousticEvent] = [],
        bookmarks: [RecordingBookmark] = [],
        waveformSamples: [Float] = [],
        silenceIntervals: [SilenceInterval] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        let resolvedEnd = endedAt ?? createdAt.addingTimeInterval(duration)
        self.endedAt = resolvedEnd
        self.exactTimestampString = ExactDateFormatter.fullExactTimestamp(from: createdAt)
        self.dayGroupKey = ExactDateFormatter.exactDayKey(from: createdAt)
        self.dayPeriodRaw = DayPeriod.from(date: createdAt).rawValue
        self.audioFileName = audioFileName
        self.formatRaw = format.rawValue
        self.sampleRate = sampleRate
        self.bitRate = bitRate
        self.channelCount = channelCount
        self.duration = duration
        self.fileSizeBytes = fileSizeBytes
        self.sha256Hash = sha256Hash
        self.isFavorite = isFavorite
        self.isProcessingBackground = isProcessingBackground
        self.transcriptionEngineUsed = transcriptionEngineUsed

        let encoder = JSONEncoder()
        self.tagsData = (try? encoder.encode(tags)) ?? Data()
        self.speakersData = (try? encoder.encode(speakers)) ?? Data()
        self.segmentsData = (try? encoder.encode(segments)) ?? Data()
        self.acousticEventsData = (try? encoder.encode(acousticEvents)) ?? Data()
        self.bookmarksData = (try? encoder.encode(bookmarks)) ?? Data()
        self.waveformSamplesData = (try? encoder.encode(waveformSamples)) ?? Data()
        self.silenceIntervalsData = (try? encoder.encode(silenceIntervals)) ?? Data()
        self.fullTranscriptText = segments.map(\.text).joined(separator: " ")
    }

    // MARK: - Propiedades Calculadas y Decodificación Segura

    var audioFormat: AudioFormatOption {
        AudioFormatOption(rawValue: formatRaw) ?? .m4a
    }

    var dayPeriod: DayPeriod {
        DayPeriod(rawValue: dayPeriodRaw) ?? DayPeriod.from(date: createdAt)
    }

    var formattedExactCreationDate: String {
        ExactDateFormatter.fullExactTimestamp(from: createdAt)
    }

    var formattedExactEndDate: String {
        ExactDateFormatter.fullExactTimestamp(from: endedAt)
    }

    var formattedExactTimeOnly: String {
        ExactDateFormatter.exactTimeOnly(from: createdAt)
    }

    var formattedDuration: String {
        ExactDateFormatter.standardDuration(duration)
    }

    var formattedPreciseDuration: String {
        ExactDateFormatter.preciseChronometer(duration, alwaysShowHours: false)
    }

    var formattedFileSize: String {
        ExactDateFormatter.formattedFileSize(bytes: fileSizeBytes)
    }

    var formattedDetailedFileSize: String {
        ExactDateFormatter.detailedFileSize(bytes: fileSizeBytes)
    }

    var tags: [TagItem] {
        get {
            if let cached = cachedTags, cachedTagsByteCount == tagsData.count {
                return cached
            }
            let decoded = (try? JSONDecoder().decode([TagItem].self, from: tagsData)) ?? []
            cachedTags = decoded
            cachedTagsByteCount = tagsData.count
            return decoded
        }
        set {
            tagsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            cachedTags = newValue
            cachedTagsByteCount = tagsData.count
        }
    }

    var speakers: [SpeakerProfile] {
        get {
            if let cached = cachedSpeakers, cachedSpeakersByteCount == speakersData.count {
                return cached
            }
            let decoded = (try? JSONDecoder().decode([SpeakerProfile].self, from: speakersData)) ?? []
            cachedSpeakers = decoded
            cachedSpeakersByteCount = speakersData.count
            return decoded
        }
        set {
            speakersData = (try? JSONEncoder().encode(newValue)) ?? Data()
            cachedSpeakers = newValue
            cachedSpeakersByteCount = speakersData.count
        }
    }

    var segments: [TranscriptSegment] {
        get {
            if let cached = cachedSegments, cachedSegmentsByteCount == segmentsData.count {
                return cached
            }
            let decoded = (try? JSONDecoder().decode([TranscriptSegment].self, from: segmentsData)) ?? []
            cachedSegments = decoded
            cachedSegmentsByteCount = segmentsData.count
            return decoded
        }
        set {
            segmentsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            cachedSegments = newValue
            cachedSegmentsByteCount = segmentsData.count
            fullTranscriptText = newValue.map(\.text).joined(separator: " ")
        }
    }

    var acousticEvents: [AcousticEvent] {
        get {
            if let cached = cachedEvents, cachedEventsByteCount == acousticEventsData.count {
                return cached
            }
            let decoded = (try? JSONDecoder().decode([AcousticEvent].self, from: acousticEventsData)) ?? []
            cachedEvents = decoded
            cachedEventsByteCount = acousticEventsData.count
            return decoded
        }
        set {
            acousticEventsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            cachedEvents = newValue
            cachedEventsByteCount = acousticEventsData.count
        }
    }

    var bookmarks: [RecordingBookmark] {
        get {
            if let cached = cachedBookmarks, cachedBookmarksByteCount == bookmarksData.count {
                return cached
            }
            let decoded = (try? JSONDecoder().decode([RecordingBookmark].self, from: bookmarksData)) ?? []
            cachedBookmarks = decoded
            cachedBookmarksByteCount = bookmarksData.count
            return decoded
        }
        set {
            let sorted = newValue.sorted { $0.timestamp < $1.timestamp }
            bookmarksData = (try? JSONEncoder().encode(sorted)) ?? Data()
            cachedBookmarks = sorted
            cachedBookmarksByteCount = bookmarksData.count
        }
    }

    var waveformSamples: [Float] {
        get {
            if let cached = cachedWaveform, cachedWaveformByteCount == waveformSamplesData.count {
                return cached
            }
            let decoded = (try? JSONDecoder().decode([Float].self, from: waveformSamplesData)) ?? []
            cachedWaveform = decoded
            cachedWaveformByteCount = waveformSamplesData.count
            return decoded
        }
        set {
            waveformSamplesData = (try? JSONEncoder().encode(newValue)) ?? Data()
            cachedWaveform = newValue
            cachedWaveformByteCount = waveformSamplesData.count
        }
    }

    var silenceIntervals: [SilenceInterval] {
        get {
            if let cached = cachedSilences, cachedSilencesByteCount == silenceIntervalsData.count {
                return cached
            }
            let decoded = (try? JSONDecoder().decode([SilenceInterval].self, from: silenceIntervalsData)) ?? []
            cachedSilences = decoded
            cachedSilencesByteCount = silenceIntervalsData.count
            return decoded
        }
        set {
            silenceIntervalsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            cachedSilences = newValue
            cachedSilencesByteCount = silenceIntervalsData.count
        }
    }

    // MARK: - Gestión de Locutores y Renombrado Global en la Nota

    func speakerProfile(for speakerId: String) -> SpeakerProfile {
        if let found = speakers.first(where: { $0.id == speakerId }) {
            return found
        }
        let number = Int(speakerId.replacingOccurrences(of: "speaker_", with: "")) ?? 1
        return SpeakerProfile.createDefault(number: number)
    }

    /// Renombra un locutor (ej. "Locutor 1" -> "Dra. Elena Gómez") y actualiza estadísticas en toda la grabación.
    func renameSpeaker(speakerId: String, newName: String, newColorHex: String? = nil) {
        var currentSpeakers = speakers
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let index = currentSpeakers.firstIndex(where: { $0.id == speakerId }) {
            currentSpeakers[index].customName = trimmed.isEmpty ? nil : trimmed
            if let hex = newColorHex {
                currentSpeakers[index].colorHex = hex
            }
        } else {
            let number = Int(speakerId.replacingOccurrences(of: "speaker_", with: "")) ?? (currentSpeakers.count + 1)
            var created = SpeakerProfile.createDefault(number: number)
            created.id = speakerId
            created.customName = trimmed.isEmpty ? nil : trimmed
            if let hex = newColorHex {
                created.colorHex = hex
            }
            currentSpeakers.append(created)
        }
        self.speakers = currentSpeakers
    }

    /// Recalcula la duración hablada y el conteo de palabras de cada locutor en base a los segmentos actuales.
    func recalculateSpeakerStatistics() {
        var currentSpeakers = speakers
        let currentSegments = segments

        for idx in currentSpeakers.indices {
            let spkId = currentSpeakers[idx].id
            let matchingSegments = currentSegments.filter { $0.speakerId == spkId }
            let totalTime = matchingSegments.reduce(0.0) { $0 + max(0, $1.endTime - $1.startTime) }
            let totalWords = matchingSegments.reduce(0) { $0 + $1.words.count }
            currentSpeakers[idx].totalSpeakingDuration = totalTime
            currentSpeakers[idx].wordCount = totalWords
        }
        self.speakers = currentSpeakers
    }

    // MARK: - Gestión de Etiquetas y Marcadores

    func toggleTag(_ tag: TagItem) {
        var current = tags
        if let idx = current.firstIndex(where: { $0.id == tag.id }) {
            current.remove(at: idx)
        } else {
            current.append(tag)
        }
        tags = current
    }

    func addBookmark(at timestamp: TimeInterval, label: String, note: String = "") {
        var current = bookmarks
        let newBookmark = RecordingBookmark(
            timestamp: max(0, min(duration, timestamp)),
            label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? L10n.bookmarkDefaultNumbered(current.count + 1)
                : label,
            note: note,
            createdAt: Date()
        )
        current.append(newBookmark)
        bookmarks = current
    }

    func removeBookmark(id: UUID) {
        var current = bookmarks
        current.removeAll { $0.id == id }
        bookmarks = current
    }

    // MARK: - Búsqueda Local y Global Profunda

    /// Busca todas las ocurrencias de una palabra o frase dentro de esta grabación y devuelve su segundo exacto.
    func searchLocalOccurrences(query: String) -> [LocalWordSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let searchLocale = Locale.current
        let normalizedQuery = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: searchLocale)

        var hits: [LocalWordSearchHit] = []
        for segment in segments {
            // Buscar primero en palabras con timestamp exacto
            var matchedInWords = false
            for wordItem in segment.words {
                let normalizedWord = wordItem.word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: searchLocale)
                if normalizedWord.contains(normalizedQuery) {
                    hits.append(
                        LocalWordSearchHit(
                            segmentId: segment.id,
                            wordId: wordItem.id,
                            matchedWord: wordItem.word,
                            contextSnippet: segment.text,
                            timestamp: wordItem.startTime,
                            speakerId: segment.speakerId
                        )
                    )
                    matchedInWords = true
                }
            }

            // Si la búsqueda es una frase de varias palabras dentro del segmento
            if !matchedInWords {
                let normalizedSegment = segment.text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: searchLocale)
                if normalizedSegment.contains(normalizedQuery) {
                    hits.append(
                        LocalWordSearchHit(
                            segmentId: segment.id,
                            wordId: segment.words.first?.id,
                            matchedWord: trimmed,
                            contextSnippet: segment.text,
                            timestamp: segment.startTime,
                            speakerId: segment.speakerId
                        )
                    )
                }
            }
        }
        return hits.sorted { $0.timestamp < $1.timestamp }
    }

    /// Evalúa coincidencias profundas para el Buscador Global de la pantalla principal.
    func evaluateGlobalSearchMatches(query: String) -> [GlobalSearchMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let searchLocale = Locale.current
        let normalizedQuery = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: searchLocale)

        var results: [GlobalSearchMatch] = []

        // 1. Coincidencias exactas palabra por palabra en la transcripción
        for hit in searchLocalOccurrences(query: trimmed) {
            let speakerName = speakerProfile(for: hit.speakerId).displayName
            results.append(
                GlobalSearchMatch(
                    recordingId: id,
                    recordingTitle: title,
                    recordingExactDate: formattedExactCreationDate,
                    matchSource: .transcriptWord,
                    matchedText: hit.matchedWord,
                    contextSnippet: hit.contextSnippet,
                    timestamp: hit.timestamp,
                    speakerName: speakerName
                )
            )
        }

        // 2. Coincidencias en Marcadores en vivo (Bookmarks)
        for bookmark in bookmarks {
            let combined = "\(bookmark.label) \(bookmark.note)".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: searchLocale)
            if combined.contains(normalizedQuery) {
                results.append(
                    GlobalSearchMatch(
                        recordingId: id,
                        recordingTitle: title,
                        recordingExactDate: formattedExactCreationDate,
                        matchSource: .bookmark,
                        matchedText: bookmark.label,
                        contextSnippet: bookmark.note.isEmpty ? L10n.bookmarkAtTimestamp(bookmark.formattedTimestamp) : bookmark.note,
                        timestamp: bookmark.timestamp,
                        speakerName: nil
                    )
                )
            }
        }

        // 3. Coincidencias en Eventos Acústicos
        for event in acousticEvents {
            let normalizedEvent = event.type.localizedTitle.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: searchLocale)
            if normalizedEvent.contains(normalizedQuery) {
                results.append(
                    GlobalSearchMatch(
                        recordingId: id,
                        recordingTitle: title,
                        recordingExactDate: formattedExactCreationDate,
                        matchSource: .acousticEvent,
                        matchedText: event.formattedInlineTag,
                        contextSnippet: L10n.searchEventConfidence(Int(event.confidence * 100)),
                        timestamp: event.timestamp,
                        speakerName: nil
                    )
                )
            }
        }

        // 4. Coincidencias en Título o Etiquetas si aún no hay coincidencias o como resultado adicional
        let normalizedTitle = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: searchLocale)
        let matchingTags = tags.filter {
            $0.localizedName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: searchLocale).contains(normalizedQuery) ||
            $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: searchLocale).contains(normalizedQuery)
        }
        if normalizedTitle.contains(normalizedQuery) || !matchingTags.isEmpty {
            let tagNames = matchingTags.map(\.localizedName).joined(separator: ", ")
            results.append(
                GlobalSearchMatch(
                    recordingId: id,
                    recordingTitle: title,
                    recordingExactDate: formattedExactCreationDate,
                    matchSource: .titleOrTag,
                    matchedText: matchingTags.isEmpty ? title : tagNames,
                    contextSnippet: fullTranscriptText.isEmpty ? L10n.recordingDateFallback(formattedExactCreationDate) : String(fullTranscriptText.prefix(140)),
                    timestamp: 0,
                    speakerName: speakers.first?.displayName
                )
            )
        }

        return results
    }
}
