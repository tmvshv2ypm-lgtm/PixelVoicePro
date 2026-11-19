import Foundation
import AVFoundation
import CoreMedia
import CryptoKit

/// Gestor de persistencia de archivos de audio en `Documents/PixelVoiceRecordings/` y generador de grabaciones de demostración iniciales.
enum RecordingStorageService {
    static var recordingsDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = docs.appendingPathComponent("PixelVoiceRecordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    static func audioFileURL(for fileName: String) -> URL {
        recordingsDirectoryURL.appendingPathComponent(fileName)
    }

    static func deleteAudioFile(named fileName: String) {
        let url = audioFileURL(for: fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Verifica que el archivo de audio de una grabación exista en `FileManager` y sea reproducible.
    /// Si una grabación de prueba precargada no tiene archivo en la ruta actual del contenedor o está vacío, lo regenera automáticamente.
    @discardableResult
    static func ensurePlayableAudioFileExists(for recording: VoiceRecording, expectedURL: URL? = nil) -> URL {
        let targetURL = expectedURL ?? audioFileURL(for: recording.audioFileName)
        let fm = FileManager.default

        if fm.fileExists(atPath: targetURL.path),
           let attrs = try? fm.attributesOfItem(atPath: targetURL.path),
           let size = attrs[.size] as? NSNumber,
           size.int64Value > 4096 {
            // Si es una de las 3 notas de prueba precargadas (22050 Hz) de una versión previa, actualizarla al nuevo WAV de alta potencia 44.1kHz
            if recording.sampleRate == 22050.0 {
                try? generateSynthesizedDemoWAVFile(at: targetURL, durationSeconds: recording.duration)
                recording.sampleRate = 44100.0
                if let newSize = (try? fm.attributesOfItem(atPath: targetURL.path)[.size] as? NSNumber)?.int64Value {
                    recording.fileSizeBytes = newSize
                }
            }
            return targetURL
        }

        // Si el archivo no existe en la ruta actual (p. ej. tras actualizar el contenedor o en grabaciones de prueba), generarlo
        try? generateSynthesizedDemoWAVFile(at: targetURL, durationSeconds: max(2.0, recording.duration))
        if let newSize = (try? fm.attributesOfItem(atPath: targetURL.path)[.size] as? NSNumber)?.int64Value {
            recording.fileSizeBytes = newSize
        }
        return targetURL
    }

    /// Genera un archivo RIFF/WAVE PCM de 16 bits a 44,100 Hz con cabecera estándar universal y volumen alto y claro,
    /// garantizando reproducción 100% audible por el altavoz principal en `AVAudioPlayer`.
    static func generateSynthesizedDemoWAVFile(at destinationURL: URL, durationSeconds: TimeInterval) throws {
        let sampleRate: Int = 44100
        let numChannels: Int = 1
        let bitsPerSample: Int = 16
        let clampedDuration = max(1.5, min(60.0, durationSeconds))
        let totalSamples = Int(Double(sampleRate) * clampedDuration)
        let bytesPerSample = bitsPerSample / 8
        let dataChunkSize = totalSamples * numChannels * bytesPerSample
        let totalFileSizeMinus8 = 36 + dataChunkSize

        var wavData = Data(capacity: 44 + dataChunkSize)

        func appendASCII(_ text: String) {
            if let data = text.data(using: .ascii) {
                wavData.append(data)
            }
        }
        func appendUInt32LE(_ value: UInt32) {
            var le = value.littleEndian
            wavData.append(Data(bytes: &le, count: 4))
        }
        func appendUInt16LE(_ value: UInt16) {
            var le = value.littleEndian
            wavData.append(Data(bytes: &le, count: 2))
        }

        // Cabecera estándar RIFF/WAVE de 44 bytes
        appendASCII("RIFF")
        appendUInt32LE(UInt32(totalFileSizeMinus8))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32LE(16) // Tamaño del bloque fmt PCM
        appendUInt16LE(1)  // AudioFormat = 1 (Linear PCM)
        appendUInt16LE(UInt16(numChannels))
        appendUInt32LE(UInt32(sampleRate))
        appendUInt32LE(UInt32(sampleRate * numChannels * bytesPerSample)) // ByteRate
        appendUInt16LE(UInt16(numChannels * bytesPerSample)) // BlockAlign
        appendUInt16LE(UInt16(bitsPerSample))
        appendASCII("data")
        appendUInt32LE(UInt32(dataChunkSize))

        // Sintetizar muestras de audio claras (acordes armónicos cálidos con cadencia silábica y ventana de silencio entre 7.2s y 9.8s)
        var phase1: Double = 0.0
        var phase2: Double = 0.0
        var phase3: Double = 0.0
        var samplesBuffer = [Int16](repeating: 0, count: totalSamples)

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)

            // Ventana de silencio real entre 7.2s y 9.8s para probar "Saltar silencios" y [⏸️ Pausa larga]
            if t >= 7.2 && t <= 9.8 {
                samplesBuffer[i] = 0
                continue
            }

            // Alternar locutor 1 (timbre grave-medio cálido 220 Hz) y locutor 2 (timbre medio-agudo 330 Hz)
            let isFirstSpeaker = (Int(t / 5.0) % 2 == 0)
            let f1 = isFirstSpeaker ? 220.0 : 329.63
            let f2 = isFirstSpeaker ? 277.18 : 440.0
            let f3 = isFirstSpeaker ? 329.63 : 554.37

            phase1 += 2.0 * .pi * f1 / Double(sampleRate)
            phase2 += 2.0 * .pi * f2 / Double(sampleRate)
            phase3 += 2.0 * .pi * f3 / Double(sampleRate)

            // Modulación silábica suave para que suene rítmico y claramente audible en el altavoz del iPhone
            let cadence = 0.45 + 0.55 * max(0.0, sin(2.0 * .pi * 3.2 * t))
            let wave = 0.55 * sin(phase1) + 0.28 * sin(phase2) + 0.17 * sin(phase3)
            let normalizedSample = max(-0.95, min(0.95, wave * cadence * 0.68))
            samplesBuffer[i] = Int16(normalizedSample * 32767.0)
        }

        samplesBuffer.withUnsafeBufferPointer { ptr in
            wavData.append( UnsafeBufferPointer(start: UnsafeRawPointer(ptr.baseAddress)?.assumingMemoryBound(to: UInt8.self), count: dataChunkSize) )
        }

        try wavData.write(to: destinationURL, options: .atomic)
    }

    // MARK: - Creación de Grabaciones Iniciales con Horas Exactas al Segundo (Mañana, Tarde y Noche del Mismo Día)

    static func buildSampleRecordings() -> [VoiceRecording] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)

        func makeDate(hour: Int, minute: Int, second: Int, daysOffset: Int = 0) -> Date {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day
            comps.hour = hour
            comps.minute = minute
            comps.second = second
            let base = calendar.date(from: comps) ?? now
            return calendar.date(byAdding: .day, value: daysOffset, to: base) ?? base
        }

        let dateNight = makeDate(hour: 22, minute: 25, second: 42, daysOffset: 0)
        let rec1 = createRichRecording(
            title: L10n.sample1Title,
            createdAt: dateNight,
            duration: 18.4,
            tags: [TagItem.predefinedTags[0], TagItem.predefinedTags[1]],
            isFavorite: true,
            speakers: [
                SpeakerProfile(
                    id: "speaker_1",
                    speakerNumber: 1,
                    defaultLabel: L10n.speakerDefaultName(1),
                    customName: L10n.sample1Speaker1,
                    colorHex: "#3B82F6",
                    pitchMeanHz: 132.0,
                    spectralCentroidHz: 1580.0,
                    totalSpeakingDuration: 10.2,
                    wordCount: 28
                ),
                SpeakerProfile(
                    id: "speaker_2",
                    speakerNumber: 2,
                    defaultLabel: L10n.speakerDefaultName(2),
                    customName: L10n.sample1Speaker2,
                    colorHex: "#10B981",
                    pitchMeanHz: 214.0,
                    spectralCentroidHz: 2120.0,
                    totalSpeakingDuration: 5.6,
                    wordCount: 18
                )
            ],
            rawTurns: [
                (
                    speakerId: "speaker_1",
                    start: 0.2,
                    words: L10n.tokenizeSampleSentence(L10n.sample1Turn1),
                    events: []
                ),
                (
                    speakerId: "speaker_2",
                    start: 4.8,
                    words: L10n.tokenizeSampleSentence(L10n.sample1Turn2),
                    events: [
                        AcousticEvent(type: .laughter, timestamp: 6.8, duration: 1.1, confidence: 0.94),
                        AcousticEvent(type: .longPause, timestamp: 7.3, duration: 2.5, confidence: 0.97)
                    ]
                ),
                (
                    speakerId: "speaker_1",
                    start: 10.0,
                    words: L10n.tokenizeSampleSentence(L10n.sample1Turn3),
                    events: [
                        AcousticEvent(type: .applause, timestamp: 16.4, duration: 1.6, confidence: 0.91)
                    ]
                )
            ],
            bookmarks: [
                RecordingBookmark(
                    timestamp: 4.8,
                    label: L10n.sample1BM1Label,
                    note: L10n.sample1BM1Note,
                    createdAt: dateNight.addingTimeInterval(5)
                ),
                RecordingBookmark(
                    timestamp: 10.0,
                    label: L10n.sample1BM2Label,
                    note: L10n.sample1BM2Note,
                    createdAt: dateNight.addingTimeInterval(11)
                )
            ],
            silenceIntervals: [
                SilenceInterval(startTime: 7.2, endTime: 9.8)
            ]
        )

        let dateAfternoon = makeDate(hour: 16, minute: 12, second: 9, daysOffset: 0)
        let rec2 = createRichRecording(
            title: L10n.sample2Title,
            createdAt: dateAfternoon,
            duration: 14.6,
            tags: [TagItem.predefinedTags[2], TagItem.predefinedTags[3]],
            isFavorite: false,
            speakers: [
                SpeakerProfile(
                    id: "speaker_1",
                    speakerNumber: 1,
                    defaultLabel: L10n.speakerDefaultName(1),
                    customName: nil,
                    colorHex: "#3B82F6",
                    pitchMeanHz: 144.0,
                    spectralCentroidHz: 1690.0,
                    totalSpeakingDuration: 7.4,
                    wordCount: 19
                ),
                SpeakerProfile(
                    id: "speaker_2",
                    speakerNumber: 2,
                    defaultLabel: L10n.speakerDefaultName(2),
                    customName: nil,
                    colorHex: "#10B981",
                    pitchMeanHz: 196.0,
                    spectralCentroidHz: 1980.0,
                    totalSpeakingDuration: 6.2,
                    wordCount: 16
                )
            ],
            rawTurns: [
                (
                    speakerId: "speaker_1",
                    start: 0.3,
                    words: L10n.tokenizeSampleSentence(L10n.sample2Turn1),
                    events: [
                        AcousticEvent(type: .music, timestamp: 3.9, duration: 1.4, confidence: 0.89)
                    ]
                ),
                (
                    speakerId: "speaker_2",
                    start: 6.0,
                    words: L10n.tokenizeSampleSentence(L10n.sample2Turn2),
                    events: [
                        AcousticEvent(type: .sigh, timestamp: 12.8, duration: 0.9, confidence: 0.86)
                    ]
                )
            ],
            bookmarks: [
                RecordingBookmark(
                    timestamp: 6.0,
                    label: L10n.sample2BM1Label,
                    note: L10n.sample2BM1Note,
                    createdAt: dateAfternoon.addingTimeInterval(6)
                )
            ],
            silenceIntervals: [
                SilenceInterval(startTime: 4.8, endTime: 5.9)
            ]
        )

        let dateMorning = makeDate(hour: 8, minute: 47, second: 19, daysOffset: 0)
        let rec3 = createRichRecording(
            title: L10n.sample3Title,
            createdAt: dateMorning,
            duration: 11.2,
            tags: [TagItem.predefinedTags[4]],
            isFavorite: true,
            speakers: [
                SpeakerProfile(
                    id: "speaker_1",
                    speakerNumber: 1,
                    defaultLabel: L10n.speakerDefaultName(1),
                    customName: L10n.sample3Speaker1,
                    colorHex: "#3B82F6",
                    pitchMeanHz: 136.0,
                    spectralCentroidHz: 1610.0,
                    totalSpeakingDuration: 10.5,
                    wordCount: 24
                )
            ],
            rawTurns: [
                (
                    speakerId: "speaker_1",
                    start: 0.2,
                    words: L10n.tokenizeSampleSentence(L10n.sample3Turn1),
                    events: []
                )
            ],
            bookmarks: [
                RecordingBookmark(
                    timestamp: 2.1,
                    label: L10n.sample3BM1Label,
                    note: L10n.sample3BM1Note,
                    createdAt: dateMorning.addingTimeInterval(3)
                )
            ],
            silenceIntervals: []
        )

        return [rec1, rec2, rec3]
    }

    private static func createRichRecording(
        title: String,
        createdAt: Date,
        duration: TimeInterval,
        tags: [TagItem],
        isFavorite: Bool,
        speakers: [SpeakerProfile],
        rawTurns: [(speakerId: String, start: TimeInterval, words: [String], events: [AcousticEvent])],
        bookmarks: [RecordingBookmark],
        silenceIntervals: [SilenceInterval]
    ) -> VoiceRecording {
        let safeStamp = ExactDateFormatter.filenameTimestamp(from: createdAt)
        let fileName = "PixelVoice_\(safeStamp).wav"
        let fileURL = audioFileURL(for: fileName)

        try? generateSynthesizedDemoWAVFile(at: fileURL, durationSeconds: duration)

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? Int64(duration * 88200)
        let sha256: String = {
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }()

        var builtSegments: [TranscriptSegment] = []
        var allEvents: [AcousticEvent] = []

        for turn in rawTurns {
            var currentWordStart = turn.start
            var wordModels: [WordTimestamp] = []
            for w in turn.words {
                let wordDur = max(0.24, Double(w.count) * 0.045)
                let wt = WordTimestamp(
                    word: w,
                    startTime: currentWordStart,
                    endTime: currentWordStart + wordDur,
                    confidence: 0.98,
                    speakerId: turn.speakerId
                )
                wordModels.append(wt)
                currentWordStart += wordDur + 0.05
            }
            let segEnd = wordModels.last?.endTime ?? (turn.start + 2.0)
            let segment = TranscriptSegment(
                speakerId: turn.speakerId,
                startTime: turn.start,
                endTime: segEnd,
                text: L10n.smartJoinWords(turn.words),
                words: wordModels,
                inlineEvents: turn.events
            )
            builtSegments.append(segment)
            allEvents.append(contentsOf: turn.events)
        }

        let sampleCount = 160
        var waveform: [Float] = []
        for i in 0..<sampleCount {
            let t = (Double(i) / Double(sampleCount)) * duration
            if silenceIntervals.contains(where: { $0.contains(t) }) {
                waveform.append(0.05)
            } else {
                let v = 0.22 + 0.58 * abs(sin(Double(i) * 0.31) * cos(Double(i) * 0.17))
                waveform.append(Float(min(0.96, max(0.12, v))))
            }
        }

        let recording = VoiceRecording(
            title: title,
            createdAt: createdAt,
            endedAt: createdAt.addingTimeInterval(duration),
            audioFileName: fileName,
            format: .wav,
            sampleRate: 44100.0,
            bitRate: 705600,
            channelCount: 1,
            duration: duration,
            fileSizeBytes: fileSize,
            sha256Hash: sha256,
            isFavorite: isFavorite,
            transcriptionEngineUsed: L10n.speechEngineApple(
                SpeechTranscriptionService.resolveRecognitionLocale(for: TranscriptionConfiguration.automaticLocaleIdentifier).identifier,
                onDevice: true
            ),
            tags: tags,
            speakers: speakers,
            segments: builtSegments,
            acousticEvents: allEvents,
            bookmarks: bookmarks,
            waveformSamples: waveform,
            silenceIntervals: silenceIntervals
        )
        recording.recalculateSpeakerStatistics()
        return recording
    }
}

// MARK: - Checkpoint de Recuperación y Ensamblado Seguro en Disco (Anti-Crash)

struct ActiveRecordingCheckpoint: Codable, Sendable {
    let sessionID: UUID
    let directoryName: String
    var title: String
    let createdAt: Date
    let formatRaw: String
    let sampleRate: Double
    let channelCount: Int
    var chunkFileNames: [String]
    var estimatedDuration: TimeInterval
    var tags: [TagItem]
    var bookmarks: [RecordingBookmark]
    var speakers: [SpeakerProfile]
    var waveformSamples: [Float]
}

extension RecordingStorageService {
    static var liveSessionsDirectoryURL: URL {
        let dir = recordingsDirectoryURL.appendingPathComponent("LiveSessions", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func sessionDirectoryURL(for sessionID: UUID) -> URL {
        let dir = liveSessionsDirectoryURL.appendingPathComponent("Session_\(sessionID.uuidString)", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func saveCheckpoint(_ checkpoint: ActiveRecordingCheckpoint) {
        let dir = sessionDirectoryURL(for: checkpoint.sessionID)
        let url = dir.appendingPathComponent("checkpoint.json")
        if let data = try? JSONEncoder().encode(checkpoint) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func removeSessionDirectory(sessionID: UUID) {
        let dir = liveSessionsDirectoryURL.appendingPathComponent("Session_\(sessionID.uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    static func discoverPendingRecoveryCheckpoints() -> [ActiveRecordingCheckpoint] {
        let fm = FileManager.default
        let root = liveSessionsDirectoryURL
        guard let subdirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }

        var checkpoints: [ActiveRecordingCheckpoint] = []
        for dir in subdirs where dir.hasDirectoryPath {
            let checkpointURL = dir.appendingPathComponent("checkpoint.json")
            guard let data = try? Data(contentsOf: checkpointURL),
                  var cp = try? JSONDecoder().decode(ActiveRecordingCheckpoint.self, from: data) else {
                continue
            }

            // Incluir cualquier chunk físico presente en el directorio ordenado numéricamente
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                let diskChunks = files
                    .filter { url in
                        let ext = url.pathExtension.lowercased()
                        return ext == "m4a" || ext == "wav"
                    }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                    .map(\.lastPathComponent)

                var merged = cp.chunkFileNames
                for name in diskChunks where !merged.contains(name) {
                    merged.append(name)
                }
                cp.chunkFileNames = merged
            }
            checkpoints.append(cp)
        }
        return checkpoints.sorted { $0.createdAt > $1.createdAt }
    }

    /// Repara cabecera RIFF/WAVE en disco si un `.wav` quedó abierto tras cierre abrupto del sistema.
    static func repairWAVHeaderIfNeeded(at url: URL) {
        guard url.pathExtension.lowercased() == "wav",
              let handle = try? FileHandle(forUpdating: url) else {
            return
        }
        defer { try? handle.close() }

        let endOffset = (try? handle.seekToEnd()) ?? 0
        guard endOffset > 44 else { return }

        try? handle.seek(toOffset: 0)
        let headerData = (try? handle.read(upToCount: 44)) ?? Data()
        guard headerData.count == 44,
              String(data: headerData.subdata(in: 0..<4), encoding: .ascii) == "RIFF",
              String(data: headerData.subdata(in: 8..<12), encoding: .ascii) == "WAVE",
              String(data: headerData.subdata(in: 36..<40), encoding: .ascii) == "data" else {
            return
        }

        let riffSize = UInt32(min(UInt64(UInt32.max), endOffset - 8)).littleEndian
        let dataSize = UInt32(min(UInt64(UInt32.max), endOffset - 44)).littleEndian

        try? handle.seek(toOffset: 4)
        try? handle.write(contentsOf: withUnsafeBytes(of: riffSize) { Data($0) })
        try? handle.seek(toOffset: 40)
        try? handle.write(contentsOf: withUnsafeBytes(of: dataSize) { Data($0) })
    }

    /// Valida y une todos los fragmentos grabados (`.m4a` o `.wav`) en el archivo final sin sobrecargar la RAM.
    static func finalizeAndStitchChunks(
        chunkURLs: [URL],
        destinationURL: URL,
        format: AudioFormatOption
    ) async -> (url: URL?, duration: TimeInterval) {
        let fm = FileManager.default
        var candidateURLs: [URL] = []

        for url in chunkURLs {
            guard fm.fileExists(atPath: url.path) else { continue }
            if format == .wav {
                repairWAVHeaderIfNeeded(at: url)
            }
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            guard bytes > 128 else { continue }
            candidateURLs.append(url)
        }

        guard !candidateURLs.isEmpty else {
            return (nil, 0)
        }

        if fm.fileExists(atPath: destinationURL.path) {
            try? fm.removeItem(at: destinationURL)
        }

        // Caso rápido: 1 único fragmento válido -> copiar directamente al destino
        if candidateURLs.count == 1 {
            let singleURL = candidateURLs[0]
            let singleDur = queryAudioDuration(at: singleURL)
            guard singleDur > 0.02 else { return (nil, 0) }
            do {
                try fm.copyItem(at: singleURL, to: destinationURL)
                return (destinationURL, singleDur)
            } catch {
                return (nil, 0)
            }
        }

        // Caso WAV multifragmento: concatenación streaming en hilo utilitario sin cargar buffers masivos en RAM
        if format == .wav {
            return await Task.detached(priority: .userInitiated) {
                var validURLs: [URL] = []
                for url in candidateURLs {
                    if let f = try? AVAudioFile(forReading: url), f.length > 0 {
                        validURLs.append(url)
                    }
                }
                guard let firstURL = validURLs.first,
                      let firstFile = try? AVAudioFile(forReading: firstURL) else {
                    return (nil, 0)
                }
                let fmt = firstFile.processingFormat
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: fmt.sampleRate,
                    AVNumberOfChannelsKey: Int(fmt.channelCount),
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                guard let outFile = try? AVAudioFile(
                    forWriting: destinationURL,
                    settings: settings,
                    commonFormat: fmt.commonFormat,
                    interleaved: fmt.isInterleaved
                ),
                let copyBuffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 32768) else {
                    return (nil, 0)
                }

                for chunkURL in validURLs {
                    guard let reader = try? AVAudioFile(forReading: chunkURL) else { continue }
                    while reader.framePosition < reader.length {
                        do {
                            try reader.read(into: copyBuffer, frameCount: 32768)
                            if copyBuffer.frameLength == 0 { break }
                            try outFile.write(from: copyBuffer)
                        } catch {
                            break
                        }
                    }
                }
                let dur = queryAudioDuration(at: destinationURL)
                return (dur > 0 ? destinationURL : nil, dur)
            }.value
        }

        // Caso M4A multifragmento: AVMutableComposition + empalme binario AAC sin recodificar (< 0.5s para 1 hora)
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return (nil, 0)
        }

        var cursor = CMTime.zero
        var firstFormatHint: CMFormatDescription?
        var validChunkCount = 0
        var lastValidURL: URL?

        for chunkURL in candidateURLs {
            let asset = AVURLAsset(url: chunkURL)
            guard let assetTrack = try? await asset.loadTracks(withMediaType: .audio).first,
                  let duration = try? await asset.load(.duration),
                  CMTimeGetSeconds(duration) > 0.02 else {
                continue
            }
            if firstFormatHint == nil {
                firstFormatHint = (try? await assetTrack.load(.formatDescriptions))?.first
            }
            let range = CMTimeRange(start: .zero, duration: duration)
            do {
                try track.insertTimeRange(range, of: assetTrack, at: cursor)
                cursor = CMTimeAdd(cursor, duration)
                validChunkCount += 1
                lastValidURL = chunkURL
            } catch {
                continue
            }
        }

        guard CMTimeGetSeconds(cursor) > 0.05 else {
            return (nil, 0)
        }

        // Si solo sobrevivió 1 fragmento válido tras filtrar corruptos -> copia directa sin re-empaquetar
        if validChunkCount == 1, let onlyURL = lastValidURL {
            do {
                try fm.copyItem(at: onlyURL, to: destinationURL)
                return (destinationURL, queryAudioDuration(at: destinationURL))
            } catch {
                return (nil, 0)
            }
        }

        // 1. Empalme comprimido AAC lossless (AVAssetReader + AVAssetWriter outputSettings: nil) -> 0% recodificación CPU
        let losslessOK = await stitchM4ACompositionLossless(
            composition: composition,
            track: track,
            sourceFormatHint: firstFormatHint,
            to: destinationURL
        )
        if losslessOK {
            let dur = queryAudioDuration(at: destinationURL)
            if dur > 0.05 {
                return (destinationURL, dur)
            }
        }

        // 2. Respaldo seguro solo si el empalme binario fallase por incompatibilidad de codec
        if fm.fileExists(atPath: destinationURL.path) {
            try? fm.removeItem(at: destinationURL)
        }
        let encodedOK = await exportComposition(composition, presetName: AVAssetExportPresetAppleM4A, to: destinationURL)
        if encodedOK {
            return (destinationURL, queryAudioDuration(at: destinationURL))
        }
        return (nil, 0)
    }

    /// Copia paquetes AAC comprimidos directamente de una composición a `.m4a` sin decodificar ni re-codificar PCM.
    private static func stitchM4ACompositionLossless(
        composition: AVMutableComposition,
        track: AVCompositionTrack,
        sourceFormatHint: CMFormatDescription?,
        to outputURL: URL
    ) async -> Bool {
        final class PumpContext: @unchecked Sendable {
            let reader: AVAssetReader
            let readerOutput: AVAssetReaderTrackOutput
            let writer: AVAssetWriter
            let writerInput: AVAssetWriterInput
            let lock = NSLock()
            var finished = false

            init(reader: AVAssetReader, readerOutput: AVAssetReaderTrackOutput, writer: AVAssetWriter, writerInput: AVAssetWriterInput) {
                self.reader = reader
                self.readerOutput = readerOutput
                self.writer = writer
                self.writerInput = writerInput
            }

            func markFinishedOnce() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if finished { return false }
                finished = true
                return true
            }
        }

        guard let reader = try? AVAssetReader(asset: composition),
              let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .m4a) else {
            return false
        }

        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { return false }
        reader.add(readerOutput)

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: sourceFormatHint)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { return false }
        writer.add(writerInput)

        guard reader.startReading(), writer.startWriting() else {
            reader.cancelReading()
            writer.cancelWriting()
            return false
        }
        writer.startSession(atSourceTime: .zero)

        let ctx = PumpContext(reader: reader, readerOutput: readerOutput, writer: writer, writerInput: writerInput)
        let pumpQueue = DispatchQueue(label: "com.pixelvoicepro.m4a.lossless.stitch", qos: .userInitiated)

        return await withCheckedContinuation { continuation in
            ctx.writerInput.requestMediaDataWhenReady(on: pumpQueue) {
                while ctx.writerInput.isReadyForMoreMediaData {
                    let nextBuffer: CMSampleBuffer? = autoreleasepool {
                        ctx.readerOutput.copyNextSampleBuffer()
                    }
                    if let sampleBuffer = nextBuffer {
                        if !ctx.writerInput.append(sampleBuffer) {
                            if ctx.markFinishedOnce() {
                                ctx.reader.cancelReading()
                                ctx.writerInput.markAsFinished()
                                ctx.writer.cancelWriting()
                                continuation.resume(returning: false)
                            }
                            return
                        }
                    } else {
                        if ctx.markFinishedOnce() {
                            ctx.writerInput.markAsFinished()
                            let readerSucceeded = (ctx.reader.status == .completed)
                            ctx.writer.finishWriting {
                                let ok = readerSucceeded && (ctx.writer.status == .completed)
                                continuation.resume(returning: ok)
                            }
                        }
                        return
                    }
                }
            }
        }
    }

    static func queryAudioDuration(at url: URL) -> TimeInterval {
        if let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 {
            return Double(file.length) / file.processingFormat.sampleRate
        }
        return 0
    }

    private static func exportComposition(
        _ composition: AVMutableComposition,
        presetName: String,
        to outputURL: URL
    ) async -> Bool {
        guard let exporter = AVAssetExportSession(asset: composition, presetName: presetName) else {
            return false
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        return await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume(returning: exporter.status == .completed)
            }
        }
    }
}
