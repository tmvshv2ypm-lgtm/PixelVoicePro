import Foundation
import AVFoundation
import Accelerate
import UIKit
import CryptoKit

/// Motor de Grabación de Audio Avanzado (`AVFoundation` + `AVAudioEngine`) optimizado para clases universitarias largas:
/// Soporta línea de tiempo con zoom tipo CapCut, tarjeta persistente en pantalla bloqueada (Live Activity + Lock Screen),
/// transcripción en vivo opcional/plegable para ahorrar RAM y batería, y pipeline completo de post-procesamiento por fragmentos de 45s.
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

    /// Ventana deslizante rápida a 60 FPS + historial temporal (10 muestras/seg) para la línea de tiempo con Zoom tipo CapCut
    @Published private(set) var liveWaveformWindow: [Float] = Array(repeating: 0.04, count: 96)
    @Published private(set) var liveTimelineSamples: [Float] = []
    @Published private(set) var liveSpectrumBands: [Float] = Array(repeating: 0.05, count: 28)

    /// Control de ahorro de RAM y batería: oculto/apagado por defecto para grabaciones de varias horas
    @Published private(set) var isLiveTranscriptionEnabled: Bool = false

    /// Estado de progreso del post-procesamiento completo al finalizar
    @Published private(set) var postProcessingProgress: Double = 0.0
    @Published private(set) var postProcessingStatusText: String = "Preparando análisis..."

    /// Estado del detector visual en vivo
    @Published private(set) var liveDetectorBanner: String = "Listo para grabar"
    @Published private(set) var liveDetectedEventType: AcousticEventType?
    @Published private(set) var activeSpeakerId: String = "speaker_1"
    @Published private(set) var activeSpeakerPitchHz: Double = 0.0

    /// Vista previa de los segmentos transcritos, marcadores, locutores y eventos
    @Published private(set) var liveSegments: [TranscriptSegment] = []
    @Published private(set) var liveBookmarks: [RecordingBookmark] = []
    @Published private(set) var liveAcousticEvents: [AcousticEvent] = []
    @Published private(set) var liveSpeakers: [SpeakerProfile] = [SpeakerProfile.createDefault(number: 1)]
    @Published private(set) var liveSpeakerTurns: [SpeakerTurnMarker] = [SpeakerTurnMarker(timestamp: 0, speakerId: "speaker_1")]

    /// Título borrador sincronizado con la pantalla bloqueada (Live Activity)
    @Published var liveCustomDraftTitle: String = ""

    /// Preferencias de calidad configurables por el usuario
    @Published var selectedFormat: AudioFormatOption = .m4a
    @Published var selectedSampleRate: SampleRateOption = .hz48000

    private var audioEngine = AVAudioEngine()
    private nonisolated(unsafe) var outputAudioFile: AVAudioFile?
    private let fileWriteLock = NSLock()
    private var currentFileURL: URL?
    private var currentFileName: String = ""
    private var hadLiveTranscriptionActiveEntireSession: Bool = false

    private let transcriptionService = SpeechTranscriptionService()
    private let diarizationService = SpeakerDiarizationService()
    private let acousticAnalyzer = AcousticEventAnalyzer()

    private var fullRecordingWaveform: [Float] = []
    private var highPrecisionTimer: Timer?
    private var lastResumeMachTime: TimeInterval = 0
    private var accumulatedTimeBeforePause: TimeInterval = 0
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var latestMeasuredRMS: Float = 0.0
    private var latestSpectralBands: [Float] = Array(repeating: 0.05, count: 28)
    private var lastTimelineSampleIndex: Int = -1

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
                if self.isLiveTranscriptionEnabled {
                    self.rebuildLiveSegments(with: self.transcriptionService.allCapturedWords)
                }
            }
        }

        acousticAnalyzer.onLiveStatusChanged = { [weak self] statusText, eventType in
            guard let self = self else { return }
            Task { @MainActor in
                self.liveDetectorBanner = statusText
                self.liveDetectedEventType = eventType
            }
        }

        LiveActivityManager.shared.onTogglePauseFromLockScreen = { [weak self] in
            guard let self = self else { return }
            if self.state == .recording {
                self.pauseRecording()
            } else if self.state == .paused {
                try? self.resumeRecording()
            }
        }

        LiveActivityManager.shared.onAddBookmarkFromLockScreen = { [weak self] in
            guard let self = self else { return }
            if self.state == .recording || self.state == .paused {
                self.addLiveBookmark(customLabel: "Marcador desde Pantalla Bloqueada")
            }
        }
    }

    /// Activa o pausa el motor de transcripción en vivo durante la grabación para ahorrar RAM y batería en clases largas.
    func setLiveTranscriptionEnabled(_ enabled: Bool) {
        guard isLiveTranscriptionEnabled != enabled else { return }
        isLiveTranscriptionEnabled = enabled

        if state == .recording {
            if enabled {
                transcriptionService.startLiveTranscription(diarizer: diarizationService, offsetSeconds: elapsedTime)
                liveDetectorBanner = "🎙️ Transcripción en vivo activada"
            } else {
                hadLiveTranscriptionActiveEntireSession = false
                transcriptionService.stopLiveTranscription()
                liveDetectorBanner = "⚡ Modo Ahorro Activo (Audio ligero en 2º plano)"
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
        self.lastTimelineSampleIndex = -1
        self.fullRecordingWaveform.removeAll()
        self.liveTimelineSamples.removeAll()
        self.liveBookmarks.removeAll()
        self.liveAcousticEvents.removeAll()
        self.liveSegments.removeAll()
        self.liveWaveformWindow = Array(repeating: 0.04, count: 96)
        self.liveSpectrumBands = Array(repeating: 0.05, count: 28)
        self.postProcessingProgress = 0.0
        self.postProcessingStatusText = "Preparando análisis..."

        // Por defecto, oculto/desactivado al iniciar para ahorrar RAM y batería en clases largas
        self.isLiveTranscriptionEnabled = false
        self.hadLiveTranscriptionActiveEntireSession = false

        diarizationService.reset()
        transcriptionService.resetCaptureBuffer()
        acousticAnalyzer.reset()

        liveSpeakers = diarizationService.detectedSpeakers
        liveSpeakerTurns = diarizationService.speakerTurnMarkers
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

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.processIncomingAudioBuffer(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        state = .recording
        liveDetectorBanner = "⚡ Grabando en modo ahorro (\(selectedFormat.shortBadge))"
        liveDetectedEventType = nil

        LiveActivityManager.shared.startLockScreenActivity(
            title: liveCustomDraftTitle,
            startDate: exactStart,
            formatBadge: selectedFormat.shortBadge,
            activeSpeaker: "Locutor 1"
        )

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

        let speakerName = liveSpeakers.first(where: { $0.id == activeSpeakerId })?.displayName ?? "Locutor 1"
        LiveActivityManager.shared.updateLockScreenProgress(
            title: liveCustomDraftTitle,
            startDate: recordingStartDate ?? Date(),
            elapsedTime: elapsedTime,
            isPaused: true,
            activeSpeaker: speakerName,
            formatBadge: selectedFormat.shortBadge,
            force: true
        )
    }

    func resumeRecording() throws {
        guard state == .paused else { return }
        try AudioSessionManager.shared.configureForBackgroundRecording(preferredSampleRate: selectedSampleRate.rawValue)
        try audioEngine.start()
        lastResumeMachTime = ProcessInfo.processInfo.systemUptime
        state = .recording
        liveDetectorBanner = "🎙️ Grabación reanudada"

        let speakerName = liveSpeakers.first(where: { $0.id == activeSpeakerId })?.displayName ?? "Locutor 1"
        LiveActivityManager.shared.updateLockScreenProgress(
            title: liveCustomDraftTitle,
            startDate: recordingStartDate ?? Date(),
            elapsedTime: elapsedTime,
            isPaused: false,
            activeSpeaker: speakerName,
            formatBadge: selectedFormat.shortBadge,
            force: true
        )
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

    func switchActiveSpeakerManually(toNumber number: Int) {
        let profile = diarizationService.selectOrCreateSpeaker(number: number, at: elapsedTime)
        liveSpeakers = diarizationService.detectedSpeakers
        liveSpeakerTurns = diarizationService.speakerTurnMarkers
        activeSpeakerId = profile.id
        liveDetectorBanner = "🗣️ Hablando ahora: \(profile.displayName)"
    }

    func triggerAcousticEventMarker(_ type: AcousticEventType) {
        let event = AcousticEvent(
            type: type,
            timestamp: elapsedTime,
            duration: 1.8,
            confidence: 0.95
        )
        acousticAnalyzer.recordDetectedEvent(event)
    }

    /// Detiene la grabación, cierra la Live Activity de la pantalla bloqueada, ejecuta el pipeline completo de post-procesamiento
    /// (dividiendo en fragmentos seguros de 45s) y devuelve el `VoiceRecording` listo para persistir.
    func stopAndFinalizeRecording(
        customTitle: String? = nil,
        initialTags: [TagItem] = [],
        performFullPostProcessing: Bool = true
    ) async -> VoiceRecording? {
        guard state == .recording || state == .paused else { return nil }
        state = .finalizing
        postProcessingProgress = 0.04
        postProcessingStatusText = "Cerrando flujo de audio de alta fidelidad..."

        highPrecisionTimer?.invalidate()
        highPrecisionTimer = nil

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        fileWriteLock.lock()
        outputAudioFile = nil
        fileWriteLock.unlock()

        LiveActivityManager.shared.stopLockScreenActivity()
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

        guard performFullPostProcessing else {
            state = .idle
            endBackgroundExecutionSafetyTask()
            return nil
        }

        // Paso 1: Diarización espectral y análisis de eventos acústicos sobre el archivo completo si estuvo en modo ahorro
        postProcessingProgress = 0.10
        postProcessingStatusText = "Analizando voces de locutores (Pitch F0 y timbre)..."
        diarizationService.analyzeAudioFileOfflineIfNeeded(url: fileURL)

        postProcessingProgress = 0.16
        postProcessingStatusText = "Detectando eventos acústicos (risas, aplausos, música y pausas)..."
        if !hadLiveTranscriptionActiveEntireSession {
            await acousticAnalyzer.analyzeCompleteAudioFileIfNeeded(at: fileURL)
        }

        let capturedWords = transcriptionService.allCapturedWords
        let capturedEvents = acousticAnalyzer.detectedEvents

        // Paso 2: Transcripción completa en fragmentos seguros de 45 segundos
        let postProcessed = await transcriptionService.postProcessRecording(
            audioFileURL: fileURL,
            totalDuration: finalDuration,
            existingWords: capturedWords,
            diarizer: diarizationService,
            acousticEvents: capturedEvents,
            onProgress: { [weak self] progress, status in
                self?.postProcessingProgress = progress
                self?.postProcessingStatusText = status
            }
        )

        postProcessingProgress = 0.96
        postProcessingStatusText = "Calculando firma de integridad SHA-256 y guardando..."

        let fileSize = Self.queryFileSizeBytes(at: fileURL)
        let sha256 = Self.computeSHA256(at: fileURL)

        let downsampledWaveform = Self.downsampleWaveform(fullRecordingWaveform, targetCount: 220)
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

        postProcessingProgress = 1.0
        state = .idle
        endBackgroundExecutionSafetyTask()
        return recording
    }

    // MARK: - Procesamiento de Audio en Tiempo Real

    private nonisolated func processIncomingAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // 1. Escribir inmediatamente en el archivo de audio (.m4a o .wav) de forma síncrona
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

            // Alimentar reconocimiento de voz en vivo SOLO si el usuario desplegó "Ver transcripción en vivo"
            if self.isLiveTranscriptionEnabled {
                self.transcriptionService.appendAudioBuffer(buffer)
            }

            // Analizador de silencios ligero siempre activo; clasificador ML en vivo solo si está desplegado o cada pocos segundos
            self.acousticAnalyzer.analyzeBuffer(
                buffer,
                at: self.elapsedTime,
                runMLStream: self.isLiveTranscriptionEnabled
            )

            // Diarizador ligero en DSP (vDSP) para mostrar cambios de locutor en la línea de tiempo CapCut
            let diarizationResult = self.diarizationService.processAudioBuffer(buffer, at: self.elapsedTime)
            if self.activeSpeakerId != diarizationResult.speakerId {
                self.activeSpeakerId = diarizationResult.speakerId
                self.liveSpeakers = self.diarizationService.detectedSpeakers
                self.liveSpeakerTurns = self.diarizationService.speakerTurnMarkers
            }
            self.activeSpeakerPitchHz = diarizationResult.pitchHz

            if diarizationResult.isVoiceActive && self.liveDetectedEventType == nil {
                let speakerName = self.liveSpeakers.first(where: { $0.id == diarizationResult.speakerId })?.displayName ?? "Locutor 1"
                let modeTag = self.isLiveTranscriptionEnabled ? "" : " · ⚡ Ahorro"
                if diarizationResult.pitchHz > 0 {
                    self.liveDetectorBanner = "🎙️ \(speakerName) (\(Int(diarizationResult.pitchHz)) Hz)\(modeTag)"
                } else {
                    self.liveDetectorBanner = "🎙️ \(speakerName)\(modeTag)"
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

                // Guardar 10 muestras por segundo (cada 0.1s) para la línea de tiempo con zoom tipo CapCut
                let currentDeciSecond = Int(self.elapsedTime * 10.0)
                if currentDeciSecond > self.lastTimelineSampleIndex {
                    self.lastTimelineSampleIndex = currentDeciSecond
                    self.liveTimelineSamples.append(sample)
                    self.fullRecordingWaveform.append(sample)
                }

                for i in 0..<min(self.liveSpectrumBands.count, self.latestSpectralBands.count) {
                    self.liveSpectrumBands[i] = (self.liveSpectrumBands[i] * 0.55) + (self.latestSpectralBands[i] * 0.45)
                }

                // Actualizar la tarjeta persistente en la pantalla bloqueada cada segundo
                let speakerName = self.liveSpeakers.first(where: { $0.id == self.activeSpeakerId })?.displayName ?? "Locutor 1"
                LiveActivityManager.shared.updateLockScreenProgress(
                    title: self.liveCustomDraftTitle,
                    startDate: self.recordingStartDate ?? Date(),
                    elapsedTime: self.elapsedTime,
                    isPaused: false,
                    activeSpeaker: speakerName,
                    formatBadge: self.selectedFormat.shortBadge
                )
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
