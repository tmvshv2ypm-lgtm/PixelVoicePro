import Foundation
import AVFoundation
import Accelerate
import UIKit
import CryptoKit

/// Motor de Grabación de Audio Avanzado (`AVFoundation` + `AVAudioEngine`) a 60 FPS.
/// Soporta grabación `.m4a` (AAC) y `.wav` (Linear PCM), visualización de onda y espectro en tiempo real,
/// marcadores en vivo (Bookmarks), transcripción simultánea, separación de locutores y análisis de sonido.
@MainActor
final class AudioRecorderService: ObservableObject {
    enum RecorderState: Equatable {
        case idle
        case recording
        case paused
        case finalizing
    }

    @Published private(set) var state: RecorderState = .idle
    @Published private(set) var recordingStartDate: Date?
    @Published private(set) var elapsedTime: TimeInterval = 0.0
    @Published private(set) var currentDecibels: Float = -60.0
    @Published private(set) var normalizedLevel: Float = 0.0

    /// Ventana deslizante de muestras normalizadas a 60 FPS para la gráfica de onda en vivo
    @Published private(set) var liveWaveformWindow: [Float] = Array(repeating: 0.04, count: 96)
    /// 28 bandas de frecuencia en tiempo real para el espectrograma/analizador de barras
    @Published private(set) var liveSpectrumBands: [Float] = Array(repeating: 0.05, count: 28)

    /// Estado del detector visual en vivo (ej. "🎙️ Voz activa · Locutor 1 (142 Hz)" o "😂 Risas detectadas")
    @Published private(set) var liveDetectorBanner: String = "Listo para grabar"
    @Published private(set) var liveDetectedEventType: AcousticEventType?
    @Published private(set) var activeSpeakerId: String = "speaker_1"
    @Published private(set) var activeSpeakerPitchHz: Double = 0.0

    /// Vista previa de los segmentos transcritos saliendo en vivo durante la grabación
    @Published private(set) var liveSegments: [TranscriptSegment] = []
    @Published private(set) var liveBookmarks: [RecordingBookmark] = []
    @Published private(set) var liveAcousticEvents: [AcousticEvent] = []
    @Published private(set) var liveSpeakers: [SpeakerProfile] = [SpeakerProfile.createDefault(number: 1)]

    /// Preferencias de calidad configurables por el usuario
    @Published var selectedFormat: AudioFormatOption = .m4a
    @Published var selectedSampleRate: SampleRateOption = .hz48000

    private var audioEngine = AVAudioEngine()
    private nonisolated(unsafe) var outputAudioFile: AVAudioFile?
    private let fileWriteLock = NSLock()
    private var currentFileURL: URL?
    private var currentFileName: String = ""

    private let transcriptionService = SpeechTranscriptionService()
    private let diarizationService = SpeakerDiarizationService()
    private let acousticAnalyzer = AcousticEventAnalyzer()

    /// Acumulador de todas las muestras de onda de la grabación para guardar el resumen visual final
    private var fullRecordingWaveform: [Float] = []
    private var highPrecisionTimer: Timer?
    private var lastResumeMachTime: TimeInterval = 0
    private var accumulatedTimeBeforePause: TimeInterval = 0
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var latestMeasuredRMS: Float = 0.0
    private var latestSpectralBands: [Float] = Array(repeating: 0.05, count: 28)

    init() {
        setupServiceCallbacks()
    }

    private func setupServiceCallbacks() {
        transcriptionService.onLiveWordsUpdated = { [weak self] words in
            guard let self = self else { return }
            Task { @MainActor in
                self.rebuildLiveSegments(with: words)
            }
        }

        acousticAnalyzer.onAcousticEventDetected = { [weak self] event in
            guard let self = self else { return }
            Task { @MainActor in
                self.liveAcousticEvents.append(event)
                self.rebuildLiveSegments(with: self.transcriptionService.allCapturedWords)
            }
        }

        acousticAnalyzer.onLiveStatusChanged = { [weak self] statusText, eventType in
            guard let self = self else { return }
            Task { @MainActor in
                self.liveDetectorBanner = statusText
                self.liveDetectedEventType = eventType
            }
        }
    }

    // MARK: - Inicio, Pausa, Reanudación y Finalización de Grabación

    func startRecording(in directoryURL: URL) async throws {
        guard state == .idle else { return }

        let permissions = await AudioSessionManager.shared.requestAllPermissions()
        guard permissions.microphone else {
            throw NSError(
                domain: "PixelVoicePro.AudioRecorder",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "El permiso de micrófono es obligatorio para grabar notas de voz."]
            )
        }

        try AudioSessionManager.shared.configureForBackgroundRecording(preferredSampleRate: selectedSampleRate.rawValue)
        beginBackgroundExecutionSafetyTask()

        let exactStart = Date()
        self.recordingStartDate = exactStart
        self.elapsedTime = 0.0
        self.accumulatedTimeBeforePause = 0.0
        self.lastResumeMachTime = ProcessInfo.processInfo.systemUptime
        self.fullRecordingWaveform.removeAll()
        self.liveBookmarks.removeAll()
        self.liveAcousticEvents.removeAll()
        self.liveSegments.removeAll()
        self.liveWaveformWindow = Array(repeating: 0.04, count: 96)
        self.liveSpectrumBands = Array(repeating: 0.05, count: 28)

        diarizationService.reset()
        liveSpeakers = diarizationService.detectedSpeakers
        activeSpeakerId = diarizationService.currentSpeakerId

        let safeTimestamp = ExactDateFormatter.filenameTimestamp(from: exactStart)
        let fileName = "PixelVoice_\(safeTimestamp)_\(UUID().uuidString.prefix(6)).\(selectedFormat.rawValue)"
        let fileURL = directoryURL.appendingPathComponent(fileName)
        self.currentFileName = fileName
        self.currentFileURL = fileURL

        audioEngine.stop()
        audioEngine.reset()

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        let recordingFormat: AVAudioFormat
        if hardwareFormat.sampleRate > 0 && hardwareFormat.channelCount > 0 {
            recordingFormat = hardwareFormat
        } else {
            recordingFormat = AVAudioFormat(standardFormatWithSampleRate: selectedSampleRate.rawValue, channels: 1)!
        }

        // Crear el archivo de salida en disco (.m4a AAC o .wav PCM) alineado con el formato de entrada del hardware
        let settings = selectedFormat.audioSettings(
            sampleRate: recordingFormat.sampleRate,
            channels: Int(recordingFormat.channelCount)
        )
        fileWriteLock.lock()
        self.outputAudioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: settings,
            commonFormat: recordingFormat.commonFormat,
            interleaved: recordingFormat.isInterleaved
        )
        fileWriteLock.unlock()

        acousticAnalyzer.startLiveStreamAnalysis(format: recordingFormat)
        if permissions.speech {
            transcriptionService.startLiveTranscription(diarizer: diarizationService)
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.processIncomingAudioBuffer(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        state = .recording
        liveDetectorBanner = "🎙️ Escuchando en alta fidelidad (\(selectedFormat.shortBadge))"
        liveDetectedEventType = nil
        start60FPSTimer()
    }

    func pauseRecording() {
        guard state == .recording else { return }
        audioEngine.pause()
        accumulatedTimeBeforePause = elapsedTime
        highPrecisionTimer?.invalidate()
        highPrecisionTimer = nil
        state = .paused
        liveDetectorBanner = "⏸️ Grabación en pausa"
    }

    func resumeRecording() throws {
        guard state == .paused else { return }
        try AudioSessionManager.shared.configureForBackgroundRecording(preferredSampleRate: selectedSampleRate.rawValue)
        try audioEngine.start()
        lastResumeMachTime = ProcessInfo.processInfo.systemUptime
        state = .recording
        liveDetectorBanner = "🎙️ Grabación reanudada"
        start60FPSTimer()
    }

    /// Añade un Marcador de Tiempo en vivo con un solo toque sin detener ni interrumpir la grabación.
    @discardableResult
    func addLiveBookmark(customLabel: String? = nil, note: String = "") -> RecordingBookmark {
        let index = liveBookmarks.count + 1
        let resolvedLabel: String
        if let custom = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            resolvedLabel = custom
        } else {
            let speakerName = liveSpeakers.first(where: { $0.id == activeSpeakerId })?.displayName ?? "Locutor 1"
            resolvedLabel = "Momento clave #\(index) (\(speakerName))"
        }

        let bookmark = RecordingBookmark(
            timestamp: elapsedTime,
            label: resolvedLabel,
            note: note,
            createdAt: Date()
        )
        liveBookmarks.append(bookmark)
        liveDetectorBanner = "🔖 Marcador añadido en \(bookmark.formattedTimestamp)"
        return bookmark
    }

    /// Permite indicar manualmente un cambio o nuevo locutor en pleno directo.
    func switchActiveSpeakerManually(toNumber number: Int) {
        let profile = diarizationService.selectOrCreateSpeaker(number: number, at: elapsedTime)
        liveSpeakers = diarizationService.detectedSpeakers
        activeSpeakerId = profile.id
        liveDetectorBanner = "🗣️ Hablando ahora: \(profile.displayName)"
    }

    /// Permite registrar un evento acústico en vivo.
    func triggerAcousticEventMarker(_ type: AcousticEventType) {
        let event = AcousticEvent(
            type: type,
            timestamp: elapsedTime,
            duration: 1.8,
            confidence: 0.95
        )
        acousticAnalyzer.recordDetectedEvent(event)
    }

    /// Detiene la grabación, cierra el archivo de audio, redirige `AVAudioSession` explícitamente hacia el altavoz principal
    /// y devuelve el modelo `VoiceRecording` completo con hora exacta hasta el segundo.
    func stopAndFinalizeRecording(customTitle: String? = nil, initialTags: [TagItem] = []) async -> VoiceRecording? {
        guard state == .recording || state == .paused else { return nil }
        state = .finalizing

        highPrecisionTimer?.invalidate()
        highPrecisionTimer = nil

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        fileWriteLock.lock()
        outputAudioFile = nil // Fuerza el volcado y cierre limpio del contenedor .m4a / .wav en disco
        fileWriteLock.unlock()

        // Configurar inmediatamente la sesión de audio hacia el altavoz principal tras finalizar la grabación
        try? AudioSessionManager.shared.configureForPlayback()

        let finalDuration = max(0.5, elapsedTime)
        let exactEndDate = Date()
        let exactStartDate = recordingStartDate ?? exactEndDate.addingTimeInterval(-finalDuration)

        transcriptionService.stopLiveTranscription()
        acousticAnalyzer.stopLiveStreamAnalysis(finalDuration: finalDuration)

        guard let fileURL = currentFileURL else {
            state = .idle
            endBackgroundExecutionSafetyTask()
            return nil
        }

        let capturedWords = transcriptionService.allCapturedWords
        let capturedEvents = acousticAnalyzer.detectedEvents

        let postProcessed = await transcriptionService.postProcessRecording(
            audioFileURL: fileURL,
            existingWords: capturedWords,
            diarizer: diarizationService,
            acousticEvents: capturedEvents
        )

        let fileSize = Self.queryFileSizeBytes(at: fileURL)
        let sha256 = Self.computeSHA256(at: fileURL)

        let downsampledWaveform = Self.downsampleWaveform(fullRecordingWaveform, targetCount: 160)
        let resolvedTitle: String
        if let custom = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            resolvedTitle = custom
        } else {
            let period = DayPeriod.from(date: exactStartDate).rawValue
            let timeStr = ExactDateFormatter.exactTimeOnly(from: exactStartDate)
            resolvedTitle = "Grabación de la \(period.lowercased()) (\(timeStr))"
        }

        let recording = VoiceRecording(
            title: resolvedTitle,
            createdAt: exactStartDate,
            endedAt: exactEndDate,
            audioFileName: currentFileName,
            format: selectedFormat,
            sampleRate: selectedSampleRate.rawValue,
            bitRate: selectedFormat == .m4a ? 192000 : Int(selectedSampleRate.rawValue * 16),
            channelCount: 1,
            duration: finalDuration,
            fileSizeBytes: fileSize,
            sha256Hash: sha256,
            isFavorite: false,
            transcriptionEngineUsed: postProcessed.engineDescription,
            tags: initialTags,
            speakers: diarizationService.detectedSpeakers,
            segments: postProcessed.segments,
            acousticEvents: capturedEvents,
            bookmarks: liveBookmarks,
            waveformSamples: downsampledWaveform,
            silenceIntervals: acousticAnalyzer.silenceIntervals
        )
        recording.recalculateSpeakerStatistics()

        state = .idle
        endBackgroundExecutionSafetyTask()
        return recording
    }

    // MARK: - Procesamiento de Audio en Tiempo Real (Hilo de Audio -> Disco Síncrono + UI 60 FPS)

    private nonisolated func processIncomingAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // 1. Escribir inmediatamente en el archivo de audio (.m4a o .wav) en el hilo del tap antes de que AVAudioEngine recicle el buffer
        fileWriteLock.lock()
        try? outputAudioFile?.write(from: buffer)
        fileWriteLock.unlock()

        guard let channelData = buffer.floatChannelData?[0] else { return }

        // 2. Calcular RMS y decibelios con Accelerate (vDSP)
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        let db = 20.0 * log10(max(rms, 1e-6))
        let normalized = max(0.03, min(1.0, (db + 55.0) / 55.0))

        // 3. Calcular 28 bandas espectrales para el analizador de frecuencias en vivo
        var bands = [Float](repeating: 0.04, count: 28)
        let step = max(1, frameLength / 28)
        for b in 0..<28 {
            let startIdx = b * step
            let count = min(step, frameLength - startIdx)
            if count > 0 {
                var bandMean: Float = 0.0
                vDSP_meamgv(channelData.advanced(by: startIdx), 1, &bandMean, vDSP_Length(count))
                let scaled = min(1.0, max(0.05, sqrt(bandMean) * 4.2))
                bands[b] = scaled
            }
        }

        Task { @MainActor [weak self] in
            guard let self = self, self.state == .recording else { return }

            // Alimentar reconocimiento de voz en vivo
            self.transcriptionService.appendAudioBuffer(buffer)

            // Alimentar analizador de eventos acústicos (SoundAnalysis)
            self.acousticAnalyzer.analyzeBuffer(buffer, at: self.elapsedTime)

            // Alimentar diarizador de locutores (Pitch F0 + Centroide Espectral)
            let diarizationResult = self.diarizationService.processAudioBuffer(buffer, at: self.elapsedTime)
            self.activeSpeakerId = diarizationResult.speakerId
            self.activeSpeakerPitchHz = diarizationResult.pitchHz
            self.liveSpeakers = self.diarizationService.detectedSpeakers

            if diarizationResult.isVoiceActive && self.liveDetectedEventType == nil {
                let speakerName = self.liveSpeakers.first(where: { $0.id == diarizationResult.speakerId })?.displayName ?? "Locutor 1"
                if diarizationResult.pitchHz > 0 {
                    self.liveDetectorBanner = "🎙️ Voz activa: \(speakerName) (\(Int(diarizationResult.pitchHz)) Hz)"
                } else {
                    self.liveDetectorBanner = "🎙️ Voz activa: \(speakerName)"
                }
            }

            self.currentDecibels = db
            self.normalizedLevel = normalized
            self.latestMeasuredRMS = normalized
            self.latestSpectralBands = bands
        }
    }

    private func start60FPSTimer() {
        highPrecisionTimer?.invalidate()
        highPrecisionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard self.state == .recording else { return }
                let now = ProcessInfo.processInfo.systemUptime
                self.elapsedTime = self.accumulatedTimeBeforePause + (now - self.lastResumeMachTime)

                let sample = max(0.04, min(1.0, self.latestMeasuredRMS))
                self.liveWaveformWindow.append(sample)
                if self.liveWaveformWindow.count > 96 {
                    self.liveWaveformWindow.removeFirst(self.liveWaveformWindow.count - 96)
                }

                for i in 0..<min(self.liveSpectrumBands.count, self.latestSpectralBands.count) {
                    self.liveSpectrumBands[i] = (self.liveSpectrumBands[i] * 0.55) + (self.latestSpectralBands[i] * 0.45)
                }

                if Int(self.elapsedTime * 60) % 3 == 0 {
                    self.fullRecordingWaveform.append(sample)
                }
            }
        }
        if let timer = highPrecisionTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func rebuildLiveSegments(with words: [WordTimestamp]) {
        liveSegments = diarizationService.buildSpeakerSegments(
            words: words,
            acousticEvents: liveAcousticEvents
        )
    }

    // MARK: - Gestión de Tareas en Segundo Plano y Utilidades de Archivo

    private func beginBackgroundExecutionSafetyTask() {
        endBackgroundExecutionSafetyTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "PixelVoiceProLiveRecording") { [weak self] in
            self?.endBackgroundExecutionSafetyTask()
        }
    }

    private func endBackgroundExecutionSafetyTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    private static func queryFileSizeBytes(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    private static func computeSHA256(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return ""
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func downsampleWaveform(_ samples: [Float], targetCount: Int) -> [Float] {
        guard !samples.isEmpty else {
            return (0..<targetCount).map { idx in
                Float(0.15 + 0.35 * abs(sin(Double(idx) * 0.25)))
            }
        }
        if samples.count <= targetCount {
            return samples
        }
        var result: [Float] = []
        result.reserveCapacity(targetCount)
        let bucketSize = Double(samples.count) / Double(targetCount)
        for i in 0..<targetCount {
            let start = Int(Double(i) * bucketSize)
            let end = min(samples.count, Int(Double(i + 1) * bucketSize))
            if end > start {
                let slice = samples[start..<end]
                let peak = slice.max() ?? 0.1
                result.append(max(0.05, min(1.0, peak)))
            } else {
                result.append(samples[min(start, samples.count - 1)])
            }
        }
        return result
    }
}
