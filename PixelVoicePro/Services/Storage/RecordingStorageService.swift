import Foundation
import AVFoundation
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

    /// Sintetiza un archivo de audio WAV real y reproducible en disco con modulación armónica vocal e intervalos de silencio reales,
    /// garantizando que las notas de demostración iniciales se reproduzcan con sonido real, onda sincronizada y "Saltar Silencios".
    static func generateSynthesizedDemoWAVFile(at destinationURL: URL, durationSeconds: TimeInterval) throws {
        let sampleRate: Double = 22050.0
        let totalFrames = Int(sampleRate * max(1.0, durationSeconds))
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)),
        let channel = buffer.floatChannelData?[0] else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(totalFrames)
        var phase: Double = 0.0

        for frame in 0..<totalFrames {
            let t = Double(frame) / sampleRate
            // Crear un intervalo de silencio real entre el segundo 7.2 y 9.8 para probar "Saltar silencios" y [⏸️ Pausa larga]
            let isSilenceWindow = (t >= 7.2 && t <= 9.8)
            if isSilenceWindow {
                channel[frame] = 0.0005 * Float.random(in: -1...1)
                continue
            }

            // Alternar timbre entre Locutor 1 (138 Hz) y Locutor 2 (205 Hz)
            let baseFreq = (Int(t / 5.5) % 2 == 0) ? 138.0 : 205.0
            let syllableEnvelope = 0.55 + 0.45 * sin(2.0 * .pi * 3.8 * t)
            phase += 2.0 * .pi * baseFreq / sampleRate
            let fundamental = sin(phase)
            let harmonic2 = 0.35 * sin(phase * 2.0)
            let harmonic3 = 0.15 * sin(phase * 3.0)
            let sampleValue = 0.14 * syllableEnvelope * (fundamental + harmonic2 + harmonic3)
            channel[frame] = Float(sampleValue)
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        let file = try AVAudioFile(
            forWriting: destinationURL,
            settings: AudioFormatOption.wav.audioSettings(sampleRate: sampleRate),
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
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

        // 1. Grabación de la Noche (Hoy - 10:25:42 PM) - Entrevista / Clase de IA y Sistemas Embebidos
        let dateNight = makeDate(hour: 22, minute: 25, second: 42, daysOffset: 0)
        let rec1 = createRichRecording(
            title: "Clase Magistral: Redes Neuronales y Audio CoreML",
            createdAt: dateNight,
            duration: 18.4,
            tags: [TagItem.predefinedTags[0], TagItem.predefinedTags[1]],
            isFavorite: true,
            speakers: [
                SpeakerProfile(
                    id: "speaker_1",
                    speakerNumber: 1,
                    defaultLabel: "Locutor 1",
                    customName: "Dr. Alejandro Vega",
                    colorHex: "#3B82F6",
                    pitchMeanHz: 132.0,
                    spectralCentroidHz: 1580.0,
                    totalSpeakingDuration: 10.2,
                    wordCount: 28
                ),
                SpeakerProfile(
                    id: "speaker_2",
                    speakerNumber: 2,
                    defaultLabel: "Locutor 2",
                    customName: "Sofía (Estudiante)",
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
                    words: ["Bienvenidos", "al", "laboratorio", "de", "inteligencia", "artificial", "aplicada", "al", "procesamiento", "acústico", "en", "tiempo", "real."],
                    events: []
                ),
                (
                    speakerId: "speaker_2",
                    start: 4.8,
                    words: ["Profesor,", "¿el", "modelo", "puede", "separar", "voces", "y", "detectar", "risas", "durante", "una", "entrevista?"],
                    events: [
                        AcousticEvent(type: .laughter, timestamp: 6.8, duration: 1.1, confidence: 0.94),
                        AcousticEvent(type: .longPause, timestamp: 7.3, duration: 2.5, confidence: 0.97)
                    ]
                ),
                (
                    speakerId: "speaker_1",
                    start: 10.0,
                    words: ["Exactamente,", "combinamos", "SoundAnalysis", "con", "diarización", "espectral", "para", "indexar", "cada", "segundo", "con", "precisión", "absoluta."],
                    events: [
                        AcousticEvent(type: .applause, timestamp: 16.4, duration: 1.6, confidence: 0.91)
                    ]
                )
            ],
            bookmarks: [
                RecordingBookmark(
                    timestamp: 4.8,
                    label: "Pregunta de Sofía sobre Diarización",
                    note: "Entra en el examen parcial del viernes",
                    createdAt: dateNight.addingTimeInterval(5)
                ),
                RecordingBookmark(
                    timestamp: 10.0,
                    label: "Explicación de arquitectura CoreML",
                    note: "Revisar diagrama de espectrograma",
                    createdAt: dateNight.addingTimeInterval(11)
                )
            ],
            silenceIntervals: [
                SilenceInterval(startTime: 7.2, endTime: 9.8)
            ]
        )

        // 2. Grabación de la Tarde (Mismo día - 04:12:09 PM) - Entrevista de Diseño de Producto
        let dateAfternoon = makeDate(hour: 16, minute: 12, second: 9, daysOffset: 0)
        let rec2 = createRichRecording(
            title: "Entrevista UX: Flujo de Búsqueda Instantánea",
            createdAt: dateAfternoon,
            duration: 14.6,
            tags: [TagItem.predefinedTags[2], TagItem.predefinedTags[3]],
            isFavorite: false,
            speakers: [
                SpeakerProfile(
                    id: "speaker_1",
                    speakerNumber: 1,
                    defaultLabel: "Locutor 1",
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
                    defaultLabel: "Locutor 2",
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
                    words: ["Necesitamos", "que", "el", "buscador", "global", "encuentre", "cualquier", "palabra", "clave", "en", "todas", "las", "grabaciones."],
                    events: [
                        AcousticEvent(type: .music, timestamp: 3.9, duration: 1.4, confidence: 0.89)
                    ]
                ),
                (
                    speakerId: "speaker_2",
                    start: 6.0,
                    words: ["Totalmente", "de", "acuerdo,", "y", "al", "tocar", "la", "palabra", "debe", "saltar", "al", "segundo", "exacto", "del", "audio."],
                    events: [
                        AcousticEvent(type: .sigh, timestamp: 12.8, duration: 0.9, confidence: 0.86)
                    ]
                )
            ],
            bookmarks: [
                RecordingBookmark(
                    timestamp: 6.0,
                    label: "Requisito Karaoke interactivo",
                    note: "Sincronización a 60 FPS",
                    createdAt: dateAfternoon.addingTimeInterval(6)
                )
            ],
            silenceIntervals: [
                SilenceInterval(startTime: 4.8, endTime: 5.9)
            ]
        )

        // 3. Grabación de la Mañana (Mismo día - 08:47:19 AM) - Nota rápida de Ideas
        let dateMorning = makeDate(hour: 8, minute: 47, second: 19, daysOffset: 0)
        let rec3 = createRichRecording(
            title: "Ideas de Arquitectura: Compresión AAC y Metadatos",
            createdAt: dateMorning,
            duration: 11.2,
            tags: [TagItem.predefinedTags[4]],
            isFavorite: true,
            speakers: [
                SpeakerProfile(
                    id: "speaker_1",
                    speakerNumber: 1,
                    defaultLabel: "Locutor 1",
                    customName: "Ingeniero Principal",
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
                    words: ["Recordatorio", "importante:", "todas", "las", "tarjetas", "deben", "mostrar", "el", "formato", "día,", "mes,", "año", "y", "la", "hora", "exacta", "hasta", "el", "segundo", "con", "AM", "o", "PM."],
                    events: []
                )
            ],
            bookmarks: [
                RecordingBookmark(
                    timestamp: 2.1,
                    label: "Prioridad máxima: Fechas exactas",
                    note: "Prohibido usar fechas ambiguas",
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

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? Int64(duration * 44100)
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
                text: turn.words.joined(separator: " "),
                words: wordModels,
                inlineEvents: turn.events
            )
            builtSegments.append(segment)
            allEvents.append(contentsOf: turn.events)
        }

        // Generar envolvente de onda realista (con caída en los intervalos de silencio)
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
            sampleRate: 22050.0,
            bitRate: 352800,
            channelCount: 1,
            duration: duration,
            fileSizeBytes: fileSize,
            sha256Hash: sha256,
            isFavorite: isFavorite,
            transcriptionEngineUsed: "Apple Speech On-Device (es) + PixelVoice DSP Diarizer + SoundAnalysis",
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
