import Foundation
import AVFoundation
import Accelerate
import UIKit
import CryptoKit

/// Carga aislada entregada a `AppViewModel` para ejecutar diarización espectral, SoundAnalysis,
/// transcripción por bloques de 45s y huella SHA-256 streaming en segundo plano sin bloquear la UI.
struct BackgroundPostProcessingPayload: @unchecked Sendable {
    let recordingID: UUID
    let audioFileURL: URL
    let totalDuration: TimeInterval
    let capturedWords: [WordTimestamp]
    let hadLiveTranscriptionEntireSession: Bool
    let transcriptionService: SpeechTranscriptionService
    let diarizationService: SpeakerDiarizationService
    let acousticAnalyzer: AcousticEventAnalyzer
}

/// Motor de Grabación de Audio Avanzado (`AVFoundation` + `AVAudioEngine`) optimizado para clases universitarias largas:
/// Soporta línea de tiempo con zoom tipo CapCut, tarjeta persistente en pantalla bloqueada (Live Activity + Lock Screen),
/// transcripción en vivo opcional/plegable para ahorrar RAM y batería, y handoff instantáneo a post-procesamiento en segundo plano.
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

    private var transcriptionService = SpeechTranscriptionService()
    private var diarizationService = SpeakerDiarizationService()
    private var acousticAnalyzer = AcousticEventAnalyzer()

    /// Cola serial en segundo plano para DSP (Pitch F0, ZCR y detección RMS de pausas) a ~4 Hz sin tocar `@MainActor`.
    private let dspQueue = DispatchQueue(label: "com.pixelvoicepro.dsp.live", qos: .userInitiated)
    private let clockLock = NSLock()
    private nonisolated(unsafe) var clockIsRecording: Bool = false
    private nonisolated(unsafe) var clockAccumulatedBeforePause: TimeInterval = 0
    private nonisolated(unsafe) var clockLastResumeUptime: TimeInterval = 0
    private nonisolated(unsafe) var clockLiveTranscriptionEnabled: Bool = false
    private nonisolated(unsafe) var lastLiveDSPTimestamp: TimeInterval = -1.0
    private nonisolated(unsafe) var lastLiveDSPPublishUptime: TimeInterval = 0.0

    private let meteringLock = NSLock()
    private nonisolated(unsafe) var latestMeasuredRMS: Float = 0.0
    private nonisolated(unsafe) var latestCurrentDecibels: Float = -60.0
    private nonisolated(unsafe) var latestSpectralBands: [Float] = Array(repeating: 0.05, count: 28)

    private var fullRecordingWaveform: [Float] = []
    private var highPrecisionTimer: Timer?
    private var lastResumeMachTime: TimeInterval = 0
    private var accumulatedTimeBeforePause: TimeInterval = 0
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var lastTimelineSampleIndex: Int = -1

    init() {
        setupServiceCallbacks()
    }

    private func setupServiceCallbacks() {
        let activeDiarizer = diarizationService
        let activeAnalyzer = acousticAnalyzer
        let activeTranscriber = transcriptionService

        activeTranscriber.onLiveWordsUpdated = { [weak self] words in
            guard let self = self else { return }
            Task { @MainActor in
                guard self.state == .recording else { return }
                self.rebuildLiveSegments(with: words)
            }
        }

        activeAnalyzer.onAcousticEventDetected = { [weak self] event in
            guard let self = self else { return }
            Task { @MainActor in
                guard self.state == .recording || self.state == .paused else { return }
                self.liveAcousticEvents.append(event)
                if self.isLiveTranscriptionEnabled {
                    self.rebuildLiveSegments(with: self.transcriptionService.allCapturedWords)
                }
            }
        }

        activeAnalyzer.onLiveStatusChanged = { [weak self] statusText, eventType in
            guard let self = self else { return }
            Task { @MainActor in
                guard self.state == .recording else { return }
                self.liveDetectorBanner = statusText
                self.liveDetectedEventType = eventType
            }
        }

        // Mantener referencias capturadas limpias si se sustituyen servicios entre sesiones
        _ = activeDiarizer

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
        clockLock.lock()
        clockLiveTranscriptionEnabled = enabled
        clockLock.unlock()

        if state == .recording {
            if enabled {
                transcriptionService.startLiveTranscription(diarizer: diarizationService, offsetSeconds: elapsedTime)
                liveDetectorBanner = "🎙️ Transcripción en vivo activada"
            } else {
                hadLiveTranscriptionActiveEntireSession = false
                transcriptionService.stopLiveTranscription()
                liveDetectorBanner = "⚡ Modo Ahorro Activo (Audio ligero)"
            }
        }
    }

    private func resetIsolatedServicesForNewSession() {
        transcriptionService = SpeechTranscriptionService()
        diarizationService = SpeakerDiarizationService()
        acousticAnalyzer = AcousticEventAnalyzer()
        setupServiceCallbacks()
    }

    private func updateClockState(recording: Bool, accumulated: TimeInterval, resumeUptime: TimeInterval, liveTranscript: Bool) {
        clockLock.lock()
        clockIsRecording = recording
        clockAccumulatedBeforePause = accumulated
        clockLastResumeUptime = resumeUptime
        clockLiveTranscriptionEnabled = liveTranscript
        clockLock.unlock()
    }

    private nonisolated func snapshotClockForAudioTap() -> (isRecording: Bool, elapsed: TimeInterval, liveTranscript: Bool) {
        clockLock.lock()
        let isRec = clockIsRecording
        let elapsed = isRec ? (clockAccumulatedBeforePause + max(0.0, ProcessInfo.processInfo.systemUptime - clockLastResumeUptime)) : clockAccumulatedBeforePause
        let live = clockLiveTranscriptionEnabled
        clockLock.unlock()
        return (isRec, elapsed, live)
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
        let startUptime = ProcessInfo.processInfo.systemUptime
        self.recordingStartDate = exactStart
        self.elapsedTime = 0.0
        self.accumulatedTimeBeforePause = 0.0
        self.lastResumeMachTime = startUptime
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

        clockLock.lock()
        self.lastLiveDSPTimestamp = -1.0
        self.lastLiveDSPPublishUptime = 0.0
        clockLock.unlock()

        meteringLock.lock()
        self.latestMeasuredRMS = 0.0
        self.latestCurrentDecibels = -60.0
        self.latestSpectralBands = Array(repeating: 0.05, count: 28)
        meteringLock.unlock()

        resetIsolatedServicesForNewSession()
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

        updateClockState(recording: true, accumulated: 0.0, resumeUptime: startUptime, liveTranscript: false)

        audioEngine.prepare()
        try audioEngine.start()

        state = .recording
        liveDetectorBanner = "⚡ Modo Ahorro (\(selectedFormat.shortBadge))"
        liveDetectedEventType = nil

        LiveActivityManager.shared.startLockScreenActivity(
            title: liveCustomDraftTitle,
            startDate: exactStart,
            formatBadge: selectedFormat.shortBadge,
            activeSpeaker: "L1"
        )

        start60FPSTimer()
    }

    func pauseRecording() {
        guard state == .recording else { return }
        audioEngine.pause()
        accumulatedTimeBeforePause = elapsedTime
        updateClockState(
            recording: false,
            accumulated: accumulatedTimeBeforePause,
            resumeUptime: ProcessInfo.processInfo.systemUptime,
            liveTranscript: isLiveTranscriptionEnabled
        )
        highPrecisionTimer?.invalidate()
        highPrecisionTimer = nil
        state = .paused
        liveDetectorBanner = "⏸️ Grabación en pausa"

        let speakerBadge = liveSpeakers.first(where: { $0.id == activeSpeakerId })?.shortBadgeCode ?? "L1"
        LiveActivityManager.shared.updateLockScreenProgress(
            title: liveCustomDraftTitle,
            startDate: recordingStartDate ?? Date(),
            elapsedTime: elapsedTime,
            isPaused: true,
            activeSpeaker: speakerBadge,
            formatBadge: selectedFormat.shortBadge,
            force: true
        )
    }

    func resumeRecording() throws {
        guard state == .paused else { return }
        try AudioSessionManager.shared.configureForBackgroundRecording(preferredSampleRate: selectedSampleRate.rawValue)
        try audioEngine.start()
        let resumeUptime = ProcessInfo.processInfo.systemUptime
        lastResumeMachTime = resumeUptime
        updateClockState(
            recording: true,
            accumulated: accumulatedTimeBeforePause,
            resumeUptime: resumeUptime,
            liveTranscript: isLiveTranscriptionEnabled
        )
        state = .recording
        liveDetectorBanner = "🎙️ Grabación reanudada"

        let speakerBadge = liveSpeakers.first(where: { $0.id == activeSpeakerId })?.shortBadgeCode ?? "L1"
        LiveActivityManager.shared.updateLockScreenProgress(
            title: liveCustomDraftTitle,
            startDate: recordingStartDate ?? Date(),
            elapsedTime: elapsedTime,
            isPaused: false,
            activeSpeaker: speakerBadge,
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
            let speakerBadge = liveSpeakers.first(where: { $0.id == activeSpeakerId })?.shortBadgeCode ?? "L1"
            resolvedLabel = "Momento clave #\(index) (\(speakerBadge))"
        }

        let bookmark = RecordingBookmark(
            timestamp: elapsedTime,
            label: resolvedLabel,
            note: note,
            createdAt: Date()
        )
        liveBookmarks.append(bookmark)
        liveDetectorBanner = "🔖 Marcador en \(bookmark.formattedTimestamp)"
        return bookmark
    }

    func switchActiveSpeakerManually(toNumber number: Int) {
        let profile = diarizationService.selectOrCreateSpeaker(number: number, at: elapsedTime)
        liveSpeakers = diarizationService.detectedSpeakers
        liveSpeakerTurns = diarizationService.speakerTurnMarkers
        activeSpeakerId = profile.id
        liveDetectorBanner = "🗣️ \(profile.shortBadgeCode)"
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

    /// Finaliza instantáneamente el archivo de audio, guarda la nota básica con `isProcessingBackground = true`
    /// y devuelve el payload aislado para que `AppViewModel` procese el análisis pesado en segundo plano sin bloquear al usuario.
    func stopAndFinalizeRecording(
        customTitle: String? = nil,
        initialTags: [TagItem] = [],
        performFullPostProcessing: Bool = true
    ) async -> (recording: VoiceRecording, payload: BackgroundPostProcessingPayload)? {
        guard state == .recording || state == .paused else { return nil }
        state = .finalizing

        updateClockState(
            recording: false,
            accumulated: elapsedTime,
            resumeUptime: ProcessInfo.processInfo.systemUptime,
            liveTranscript: false
        )

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

        let sessionTranscriber = transcriptionService
        let sessionDiarizer = diarizationService
        let sessionAnalyzer = acousticAnalyzer
        let capturedWords = sessionTranscriber.allCapturedWords
        let bookmarksSnapshot = liveBookmarks
        let hadLiveAll = hadLiveTranscriptionActiveEntireSession
        let waveformSnapshot = fullRecordingWaveform
        let currentSegments = liveSegments
        let fileURLSnapshot = currentFileURL
        let fileNameSnapshot = currentFileName

        sessionTranscriber.stopLiveTranscription()
        sessionAnalyzer.stopLiveStreamAnalysis(finalDuration: finalDuration)

        guard let fileURL = fileURLSnapshot else {
            resetIsolatedServicesForNewSession()
            state = .idle
            endBackgroundExecutionSafetyTask()
            return nil
        }

        guard performFullPostProcessing else {
            try? FileManager.default.removeItem(at: fileURL)
            resetIsolatedServicesForNewSession()
            liveCustomDraftTitle = ""
            state = .idle
            endBackgroundExecutionSafetyTask()
            return nil
        }

        let fileSize = Self.queryFileSizeBytes(at: fileURL)
        let downsampledWaveform = Self.downsampleWaveform(waveformSnapshot, targetCount: 220)
        let speakersSnapshot = sessionDiarizer.detectedSpeakers
        let eventsSnapshot = sessionAnalyzer.detectedEvents
        let silenceSnapshot = sessionAnalyzer.silenceIntervals

        let resolvedTitle: String
        if let custom = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            resolvedTitle = custom
        } else {
            resolvedTitle = "__AUTO_SEQUENTIAL_TITLE__"
        }

        let recording = VoiceRecording(
            title: resolvedTitle,
            createdAt: exactStartDate,
            endedAt: exactEndDate,
            audioFileName: fileNameSnapshot,
            format: selectedFormat,
            sampleRate: selectedSampleRate.rawValue,
            bitRate: selectedFormat == .m4a ? 192000 : Int(selectedSampleRate.rawValue * 16),
            channelCount: 1,
            duration: finalDuration,
            fileSizeBytes: fileSize,
            sha256Hash: "",
            isFavorite: false,
            transcriptionEngineUsed: "Procesando análisis e IA en segundo plano...",
            tags: initialTags,
            speakers: speakersSnapshot,
            segments: currentSegments,
            acousticEvents: eventsSnapshot,
            bookmarks: bookmarksSnapshot,
            waveformSamples: downsampledWaveform,
            silenceIntervals: silenceSnapshot,
            isProcessingBackground: true
        )
        recording.recalculateSpeakerStatistics()

        let payload = BackgroundPostProcessingPayload(
            recordingID: recording.id,
            audioFileURL: fileURL,
            totalDuration: finalDuration,
            capturedWords: capturedWords,
            hadLiveTranscriptionEntireSession: hadLiveAll,
            transcriptionService: sessionTranscriber,
            diarizationService: sessionDiarizer,
            acousticAnalyzer: sessionAnalyzer
        )

        // Preparar servicios aislados listos si el usuario inicia otra grabación mientras esta se procesa
        resetIsolatedServicesForNewSession()
        liveSegments.removeAll()
        liveBookmarks.removeAll()
        liveAcousticEvents.removeAll()
        liveCustomDraftTitle = ""
        state = .idle
        endBackgroundExecutionSafetyTask()
        return (recording, payload)
    }

    // MARK: - Procesamiento de Audio en Tiempo Real (Zero Main-Thread DSP)

    private nonisolated func processIncomingAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // 1. Escribir inmediatamente en el archivo de audio (.m4a o .wav) de forma síncrona
        fileWriteLock.lock()
        try? outputAudioFile?.write(from: buffer)
        fileWriteLock.unlock()

        guard let channelData = buffer.floatChannelData?[0] else { return }

        // 2. Calcular RMS, decibelios y 28 bandas espectrales en Accelerate (vDSP) sin tocar @MainActor
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        let db = 20.0 * log10(max(rms, 1e-6))
        let normalized = max(0.03, min(1.0, (db + 55.0) / 55.0))

        var bands = [Float](repeating: 0.04, count: 28)
        let step = max(1, frameLength / 28)
        for b in 0..<28 {
            let startIdx = b * step
            let count = min(step, frameLength - startIdx)
            if count > 0 {
                var bandMean: Float = 0.0
                vDSP_meamgv(channelData.advanced(by: startIdx), 1, &bandMean, vDSP_Length(count))
                bands[b] = min(1.0, max(0.05, sqrt(bandMean) * 4.2))
            }
        }

        // Guardar telemetría visual para que la lea el timer a 60 FPS sin crear Tasks por buffer
        meteringLock.lock()
        self.latestMeasuredRMS = normalized
        self.latestCurrentDecibels = db
        self.latestSpectralBands = bands
        meteringLock.unlock()

        let tapSnapshot = snapshotClockForAudioTap()
        guard tapSnapshot.isRecording else { return }

        // Si el usuario desplegó manualmente transcripción en vivo, enviar buffers al reconocedor y ML stream
        if tapSnapshot.liveTranscript {
            Task { @MainActor [weak self] in
                guard let self = self, self.state == .recording, self.isLiveTranscriptionEnabled else { return }
                self.transcriptionService.appendAudioBuffer(buffer)
                self.acousticAnalyzer.analyzeBuffer(buffer, at: tapSnapshot.elapsed, runMLStream: true)
            }
        }

        // Throttling estricto (~4 Hz) para ejecutar DSP de locutores y silencios en cola secundaria serial
        clockLock.lock()
        let shouldRunDSP = (tapSnapshot.elapsed - lastLiveDSPTimestamp) >= 0.24
        if shouldRunDSP {
            lastLiveDSPTimestamp = tapSnapshot.elapsed
        }
        clockLock.unlock()

        guard shouldRunDSP else { return }

        // Copiar muestra acotada de floats fuera del buffer reutilizable de AVAudioEngine
        let sampleCount = min(frameLength, 1024)
        let floatCopy = Array(UnsafeBufferPointer(start: channelData, count: sampleCount))
        let sampleRate = buffer.format.sampleRate
        let elapsedAtTap = tapSnapshot.elapsed
        let runRMSOnly = !tapSnapshot.liveTranscript

        dspQueue.async { [weak self] in
            guard let self = self else { return }
            let postSnapshot = self.snapshotClockForAudioTap()
            guard postSnapshot.isRecording else { return }

            if runRMSOnly {
                self.acousticAnalyzer.analyzeRMS(rms, at: elapsedAtTap)
            }

            let diarizationResult = self.diarizationService.processFloatSamples(
                floatCopy,
                sampleRate: sampleRate,
                at: elapsedAtTap
            )

            let speakersSnapshot = self.diarizationService.detectedSpeakers
            let turnsSnapshot = self.diarizationService.speakerTurnMarkers

            let uptime = ProcessInfo.processInfo.systemUptime
            self.clockLock.lock()
            let shouldPublishUI = (uptime - self.lastLiveDSPPublishUptime) >= 0.22
            if shouldPublishUI {
                self.lastLiveDSPPublishUptime = uptime
            }
            self.clockLock.unlock()

            guard shouldPublishUI else { return }

            Task { @MainActor [weak self] in
                guard let self = self, self.state == .recording else { return }
                if self.activeSpeakerId != diarizationResult.speakerId || self.liveSpeakers.count != speakersSnapshot.count {
                    self.activeSpeakerId = diarizationResult.speakerId
                    self.liveSpeakers = speakersSnapshot
                    self.liveSpeakerTurns = turnsSnapshot
                }
                self.activeSpeakerPitchHz = diarizationResult.pitchHz

                if diarizationResult.isVoiceActive && self.liveDetectedEventType == nil {
                    let speakerBadge = speakersSnapshot.first(where: { $0.id == diarizationResult.speakerId })?.shortBadgeCode ?? "L1"
                    let modeTag = self.isLiveTranscriptionEnabled ? "" : " · ⚡ Ahorro"
                    if diarizationResult.pitchHz > 0 {
                        self.liveDetectorBanner = "🎙️ \(speakerBadge) (\(Int(diarizationResult.pitchHz)) Hz)\(modeTag)"
                    } else {
                        self.liveDetectorBanner = "🎙️ \(speakerBadge)\(modeTag)"
                    }
                }
            }
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

                self.meteringLock.lock()
                let measuredRMS = self.latestMeasuredRMS
                let measuredDB = self.latestCurrentDecibels
                let bandsSnapshot = self.latestSpectralBands
                self.meteringLock.unlock()

                self.currentDecibels = measuredDB
                self.normalizedLevel = measuredRMS

                let sample = max(0.04, min(1.0, measuredRMS))
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

                for i in 0..<min(self.liveSpectrumBands.count, bandsSnapshot.count) {
                    self.liveSpectrumBands[i] = (self.liveSpectrumBands[i] * 0.55) + (bandsSnapshot[i] * 0.45)
                }

                // Actualizar la tarjeta persistente en la pantalla bloqueada (LiveActivityManager ya aplica throttle de 1s)
                let speakerBadge = self.liveSpeakers.first(where: { $0.id == self.activeSpeakerId })?.shortBadgeCode ?? "L1"
                LiveActivityManager.shared.updateLockScreenProgress(
                    title: self.liveCustomDraftTitle,
                    startDate: self.recordingStartDate ?? Date(),
                    elapsedTime: self.elapsedTime,
                    isPaused: false,
                    activeSpeaker: speakerBadge,
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

    static func queryFileSizeBytes(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    /// Calcula SHA-256 leyendo en bloques de 64 KB para evitar picos de RAM en grabaciones de varias horas.
    static func computeSHA256Streaming(at url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ""
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 64 * 1024
        while true {
            let chunk: Data? = autoreleasepool {
                let data = handle.readData(ofLength: chunkSize)
                return data.isEmpty ? nil : data
            }
            guard let data = chunk else { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
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
