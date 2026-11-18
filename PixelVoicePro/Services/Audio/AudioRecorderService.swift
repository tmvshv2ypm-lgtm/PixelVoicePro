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
    var bypassShortFilter: Bool = false
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
    @Published private(set) var postProcessingStatusText: String = L10n.recorderPreparing

    /// Estado del detector visual en vivo
    @Published private(set) var liveDetectorBanner: String = L10n.recorderReady
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
    private let fileRotationQueue = DispatchQueue(label: "com.pixelvoicepro.file.rotation", qos: .utility)
    private var currentFileURL: URL?
    private var currentFileName: String = ""
    private var hadLiveTranscriptionActiveEntireSession: Bool = false

    private var activeSessionID: UUID?
    private var activeSessionTags: [TagItem] = []
    private var chunkFileNames: [String] = []
    private var currentChunkIndex: Int = 0
    private var currentChunkStartElapsed: TimeInterval = 0.0
    private var isRotatingChunk: Bool = false
    private let chunkRotationIntervalSeconds: TimeInterval = 30.0
    private var cachedAudioFormat: AVAudioFormat?
    private var cachedAudioSettings: [String: Any] = [:]
    private var liveMLStreamStarted: Bool = false

    private var isAppInBackground: Bool = false
    private var wasPausedByInterruption: Bool = false

    private var transcriptionService = SpeechTranscriptionService()
    private var diarizationService = SpeakerDiarizationService()
    private var acousticAnalyzer = AcousticEventAnalyzer()

    /// Cola serial en segundo plano para DSP (Pitch F0, ZCR y detección RMS de pausas) a ~4 Hz sin tocar `@MainActor`.
    private let dspQueue = DispatchQueue(label: "com.pixelvoicepro.dsp.live", qos: .userInitiated)
    /// Cola serial dedicada para enviar copias ligeras de audio a `SFSpeechRecognizer` y `SoundAnalysis` sin crear `Task { @MainActor }` 47 veces/s.
    private let liveAnalysisQueue = DispatchQueue(label: "com.pixelvoicepro.live.analysis", qos: .utility)
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
    private var lifecycleObservers: [NSObjectProtocol] = []

    init() {
        setupServiceCallbacks()
        setupLifecycleAndInterruptionObservers()
    }

    deinit {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupLifecycleAndInterruptionObservers() {
        let nc = NotificationCenter.default

        let bgObs = nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAppDidEnterBackground()
            }
        }
        let fgObs = nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAppWillEnterForeground()
            }
        }
        let activeObs = nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAppWillEnterForeground()
            }
        }
        lifecycleObservers.append(contentsOf: [bgObs, fgObs, activeObs])

        AudioSessionManager.shared.onInterruptionBegan = { [weak self] in
            guard let self = self else { return }
            if self.state == .recording {
                self.wasPausedByInterruption = true
                self.pauseRecording()
            }
        }

        AudioSessionManager.shared.onInterruptionEnded = { [weak self] shouldResume in
            guard let self = self else { return }
            if shouldResume && self.wasPausedByInterruption && self.state == .paused {
                self.wasPausedByInterruption = false
                try? self.resumeRecording()
            } else {
                self.wasPausedByInterruption = false
            }
        }

        AudioSessionManager.shared.onMediaServicesReset = { [weak self] in
            guard let self = self else { return }
            if self.state == .recording {
                self.wasPausedByInterruption = true
                self.pauseRecording()
            }
        }
    }

    func updateDraftTags(_ tags: [TagItem]) {
        activeSessionTags = tags
        persistSessionCheckpointSnapshot()
    }

    private func handleAppDidEnterBackground() {
        guard !isAppInBackground else { return }
        isAppInBackground = true

        guard state == .recording || state == .paused else { return }

        // Apagar SFSpeechRecognizer y CoreML SoundAnalysis al bloquear pantalla para blindar RAM y CPU
        clockLock.lock()
        clockLiveTranscriptionEnabled = false
        clockLock.unlock()

        if isLiveTranscriptionEnabled {
            hadLiveTranscriptionActiveEntireSession = false
            transcriptionService.stopLiveTranscription()
        }

        persistSessionCheckpointSnapshot()

        // Cambiar timer UI de 60 FPS a 1 Hz ligero para mantener Lock Screen sin quemar batería
        if state == .recording {
            startRecordingTimer(fps: 1.0)
        }
    }

    private func handleAppWillEnterForeground() {
        guard isAppInBackground else { return }
        isAppInBackground = false

        guard state == .recording || state == .paused else { return }

        if state == .recording {
            elapsedTime = accumulatedTimeBeforePause + max(0.0, ProcessInfo.processInfo.systemUptime - lastResumeMachTime)
            let wantsLive = isLiveTranscriptionEnabled
            clockLock.lock()
            clockLiveTranscriptionEnabled = wantsLive
            clockLock.unlock()

            if wantsLive {
                if !liveMLStreamStarted, let fmt = cachedAudioFormat {
                    acousticAnalyzer.startLiveStreamAnalysis(format: fmt)
                    liveMLStreamStarted = true
                }
                transcriptionService.startLiveTranscription(diarizer: diarizationService, offsetSeconds: elapsedTime)
            }
            startRecordingTimer(fps: 60.0)
        }
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
                self.addLiveBookmark(customLabel: L10n.bookmarkFromLockScreen)
            }
        }
    }

    /// Activa o pausa el motor de transcripción en vivo durante la grabación para ahorrar RAM y batería en clases largas.
    /// Solo se ejecuta si el usuario tiene el panel abierto, está grabando y la app está activa en primer plano.
    func setLiveTranscriptionEnabled(_ enabled: Bool) {
        guard isLiveTranscriptionEnabled != enabled else { return }
        isLiveTranscriptionEnabled = enabled
        let shouldActivateNow = enabled && !isAppInBackground && state == .recording
        clockLock.lock()
        clockLiveTranscriptionEnabled = shouldActivateNow
        clockLock.unlock()

        if state == .recording {
            if shouldActivateNow {
                if !liveMLStreamStarted, let fmt = cachedAudioFormat {
                    acousticAnalyzer.startLiveStreamAnalysis(format: fmt)
                    liveMLStreamStarted = true
                }
                transcriptionService.startLiveTranscription(diarizer: diarizationService, offsetSeconds: elapsedTime)
                liveDetectorBanner = L10n.recorderLiveOn
            } else {
                hadLiveTranscriptionActiveEntireSession = false
                transcriptionService.stopLiveTranscription()
                liveDetectorBanner = L10n.recorderPowerSaverActive
            }
        }
    }

    private func resetIsolatedServicesForNewSession() {
        transcriptionService = SpeechTranscriptionService()
        diarizationService = SpeakerDiarizationService()
        acousticAnalyzer = AcousticEventAnalyzer()
        liveMLStreamStarted = false
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
                userInfo: [NSLocalizedDescriptionKey: L10n.recorderMicPermissionError]
            )
        }

        try AudioSessionManager.shared.configureForBackgroundRecording(preferredSampleRate: selectedSampleRate.rawValue)

        let exactStart = Date()
        let startUptime = ProcessInfo.processInfo.systemUptime
        let sessionID = UUID()
        self.activeSessionID = sessionID
        self.activeSessionTags = []
        self.chunkFileNames = []
        self.currentChunkIndex = 0
        self.currentChunkStartElapsed = 0.0
        self.isRotatingChunk = false
        self.wasPausedByInterruption = false
        self.isAppInBackground = (UIApplication.shared.applicationState == .background)

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
        self.postProcessingStatusText = L10n.recorderPreparing

        // Por defecto, oculto/desactivado al iniciar para ahorrar RAM y batería en clases largas
        self.isLiveTranscriptionEnabled = false
        self.hadLiveTranscriptionActiveEntireSession = false

        clockLock.withLock {
            self.lastLiveDSPTimestamp = -1.0
            self.lastLiveDSPPublishUptime = 0.0
        }

        meteringLock.withLock {
            self.latestMeasuredRMS = 0.0
            self.latestCurrentDecibels = -60.0
            self.latestSpectralBands = Array(repeating: 0.05, count: 28)
        }

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
        self.cachedAudioFormat = recordingFormat
        self.cachedAudioSettings = settings

        let sessionDir = RecordingStorageService.sessionDirectoryURL(for: sessionID)
        let firstChunkName = Self.chunkFilename(index: 0, format: selectedFormat)
        let firstChunkURL = sessionDir.appendingPathComponent(firstChunkName)

        try fileWriteLock.withLock {
            self.outputAudioFile = try AVAudioFile(
                forWriting: firstChunkURL,
                settings: settings,
                commonFormat: recordingFormat.commonFormat,
                interleaved: recordingFormat.isInterleaved
            )
        }
        self.chunkFileNames = [firstChunkName]
        persistSessionCheckpointSnapshot()

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.processIncomingAudioBuffer(buffer)
        }

        updateClockState(recording: true, accumulated: 0.0, resumeUptime: startUptime, liveTranscript: false)

        audioEngine.prepare()
        try audioEngine.start()

        state = .recording
        liveDetectorBanner = L10n.recorderPowerSaverBadge(selectedFormat.shortBadge)
        liveDetectedEventType = nil

        LiveActivityManager.shared.startLockScreenActivity(
            title: liveCustomDraftTitle,
            startDate: exactStart,
            formatBadge: selectedFormat.shortBadge,
            activeSpeaker: L10n.speakerShortBadge(1)
        )

        startRecordingTimer(fps: isAppInBackground ? 1.0 : 60.0)
    }

    func pauseRecording() {
        guard state == .recording else { return }
        audioEngine.pause()
        accumulatedTimeBeforePause = elapsedTime
        updateClockState(
            recording: false,
            accumulated: accumulatedTimeBeforePause,
            resumeUptime: ProcessInfo.processInfo.systemUptime,
            liveTranscript: false
        )
        if isLiveTranscriptionEnabled {
            transcriptionService.stopLiveTranscription()
        }
        highPrecisionTimer?.invalidate()
        highPrecisionTimer = nil
        state = .paused
        liveDetectorBanner = L10n.recorderPaused
        persistSessionCheckpointSnapshot()

        let speakerBadge = liveSpeakers.first(where: { $0.id == activeSpeakerId })?.shortBadgeCode ?? L10n.speakerShortBadge(1)
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
        let shouldLiveNow = isLiveTranscriptionEnabled && !isAppInBackground
        updateClockState(
            recording: true,
            accumulated: accumulatedTimeBeforePause,
            resumeUptime: resumeUptime,
            liveTranscript: shouldLiveNow
        )
        if shouldLiveNow {
            if !liveMLStreamStarted, let fmt = cachedAudioFormat {
                acousticAnalyzer.startLiveStreamAnalysis(format: fmt)
                liveMLStreamStarted = true
            }
            transcriptionService.startLiveTranscription(diarizer: diarizationService, offsetSeconds: accumulatedTimeBeforePause)
        }
        state = .recording
        liveDetectorBanner = L10n.recorderResumed

        let speakerBadge = liveSpeakers.first(where: { $0.id == activeSpeakerId })?.shortBadgeCode ?? L10n.speakerShortBadge(1)
        LiveActivityManager.shared.updateLockScreenProgress(
            title: liveCustomDraftTitle,
            startDate: recordingStartDate ?? Date(),
            elapsedTime: elapsedTime,
            isPaused: false,
            activeSpeaker: speakerBadge,
            formatBadge: selectedFormat.shortBadge,
            force: true
        )
        startRecordingTimer(fps: isAppInBackground ? 1.0 : 60.0)
    }

    /// Añade un Marcador de Tiempo en vivo con un solo toque sin detener ni interrumpir la grabación.
    @discardableResult
    func addLiveBookmark(customLabel: String? = nil, note: String = "") -> RecordingBookmark {
        let index = liveBookmarks.count + 1
        let resolvedLabel: String
        if let custom = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            resolvedLabel = custom
        } else {
            let speakerBadge = liveSpeakers.first(where: { $0.id == activeSpeakerId })?.shortBadgeCode ?? L10n.speakerShortBadge(1)
            resolvedLabel = L10n.bookmarkKeyMoment(index: index, speakerBadge: speakerBadge)
        }

        let bookmark = RecordingBookmark(
            timestamp: elapsedTime,
            label: resolvedLabel,
            note: note,
            createdAt: Date()
        )
        liveBookmarks.append(bookmark)
        liveDetectorBanner = L10n.recorderBookmarkAt(bookmark.formattedTimestamp)
        persistSessionCheckpointSnapshot()
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

    /// Finaliza instantáneamente los fragmentos grabados en disco, ensambla el archivo `.m4a`/`.wav` seguro
    /// y devuelve la nota lista para que `AppViewModel` procese transcripción y análisis en segundo plano.
    func stopAndFinalizeRecording(
        customTitle: String? = nil,
        initialTags: [TagItem] = [],
        performFullPostProcessing: Bool = true
    ) async -> (recording: VoiceRecording, payload: BackgroundPostProcessingPayload)? {
        guard state == .recording || state == .paused else { return nil }
        state = .finalizing
        beginBackgroundExecutionSafetyTask()

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

        fileWriteLock.withLock {
            outputAudioFile = nil
        }

        // Esperar cualquier rotación de chunk en vuelo antes de unir archivos
        await withCheckedContinuation { continuation in
            fileRotationQueue.async {
                continuation.resume()
            }
        }

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
        let sessionIDSnapshot = activeSessionID
        let chunkNamesSnapshot = chunkFileNames
        let targetFormatSnapshot = selectedFormat

        sessionTranscriber.stopLiveTranscription()
        sessionAnalyzer.stopLiveStreamAnalysis(finalDuration: finalDuration)

        guard performFullPostProcessing, let fileURL = fileURLSnapshot else {
            if let sid = sessionIDSnapshot {
                RecordingStorageService.removeSessionDirectory(sessionID: sid)
            }
            resetIsolatedServicesForNewSession()
            liveCustomDraftTitle = ""
            activeSessionID = nil
            chunkFileNames = []
            state = .idle
            endBackgroundExecutionSafetyTask()
            return nil
        }

        var stitchedDuration = finalDuration
        if let sid = sessionIDSnapshot {
            let sessionDir = RecordingStorageService.sessionDirectoryURL(for: sid)
            let chunkURLs = chunkNamesSnapshot.map { sessionDir.appendingPathComponent($0) }
            let stitched = await RecordingStorageService.finalizeAndStitchChunks(
                chunkURLs: chunkURLs,
                destinationURL: fileURL,
                format: targetFormatSnapshot
            )
            if stitched.url != nil {
                stitchedDuration = max(finalDuration, stitched.duration)
                RecordingStorageService.removeSessionDirectory(sessionID: sid)
            } else {
                // Conservar chunks sin borrar si falló el ensamblado para intento de recuperación
                resetIsolatedServicesForNewSession()
                state = .idle
                endBackgroundExecutionSafetyTask()
                return nil
            }
        }

        let resolvedDuration = max(0.5, stitchedDuration)
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

        let initialState: TranscriptionProcessingState = resolvedDuration < 3.0 ? .tooShort : .processing
        let initialEngineLabel = resolvedDuration < 3.0 ? L10n.transcriptionBadgeTooShort : L10n.recorderProcessingBg

        let recording = VoiceRecording(
            title: resolvedTitle,
            createdAt: exactStartDate,
            endedAt: exactEndDate,
            audioFileName: fileNameSnapshot,
            format: targetFormatSnapshot,
            sampleRate: cachedAudioFormat?.sampleRate ?? selectedSampleRate.rawValue,
            bitRate: targetFormatSnapshot == .m4a ? 192000 : Int((cachedAudioFormat?.sampleRate ?? selectedSampleRate.rawValue) * 16),
            channelCount: Int(cachedAudioFormat?.channelCount ?? 1),
            duration: resolvedDuration,
            fileSizeBytes: fileSize,
            sha256Hash: "",
            isFavorite: false,
            isProcessingBackground: initialState == .processing,
            transcriptionEngineUsed: initialEngineLabel,
            transcriptionState: initialState,
            tags: initialTags,
            speakers: speakersSnapshot,
            segments: currentSegments,
            acousticEvents: eventsSnapshot,
            bookmarks: bookmarksSnapshot,
            waveformSamples: downsampledWaveform,
            silenceIntervals: silenceSnapshot
        )
        recording.recalculateSpeakerStatistics()

        let payload = BackgroundPostProcessingPayload(
            recordingID: recording.id,
            audioFileURL: fileURL,
            totalDuration: resolvedDuration,
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
        activeSessionID = nil
        activeSessionTags = []
        chunkFileNames = []
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

        // Si el usuario desplegó manualmente transcripción en vivo Y la app está en primer plano,
        // copiar el buffer ligero hacia cola serial secundaria sin saturar @MainActor
        if tapSnapshot.liveTranscript, let bufferCopy = Self.clonePCMBuffer(buffer) {
            let elapsedForAnalysis = tapSnapshot.elapsed
            liveAnalysisQueue.async { [weak self] in
                guard let self = self else { return }
                let stillActive = self.snapshotClockForAudioTap()
                guard stillActive.isRecording && stillActive.liveTranscript else { return }
                self.transcriptionService.appendAudioBuffer(bufferCopy)
                self.acousticAnalyzer.analyzeBuffer(bufferCopy, at: elapsedForAnalysis, runMLStream: true)
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
            let shouldPublishUI = !postSnapshot.isRecording ? false : ((uptime - self.lastLiveDSPPublishUptime) >= 0.25)
            if shouldPublishUI {
                self.lastLiveDSPPublishUptime = uptime
            }
            self.clockLock.unlock()

            guard shouldPublishUI else { return }

            Task { @MainActor [weak self] in
                guard let self = self, self.state == .recording, !self.isAppInBackground else { return }
                if self.activeSpeakerId != diarizationResult.speakerId || self.liveSpeakers.count != speakersSnapshot.count {
                    self.activeSpeakerId = diarizationResult.speakerId
                    self.liveSpeakers = speakersSnapshot
                    self.liveSpeakerTurns = turnsSnapshot
                }
                self.activeSpeakerPitchHz = diarizationResult.pitchHz

                if diarizationResult.isVoiceActive && self.liveDetectedEventType == nil {
                    let speakerBadge = speakersSnapshot.first(where: { $0.id == diarizationResult.speakerId })?.shortBadgeCode ?? L10n.speakerShortBadge(1)
                    let modeTag = self.isLiveTranscriptionEnabled ? "" : " · \(L10n.recorderPowerSaverShort)"
                    if diarizationResult.pitchHz > 0 {
                        self.liveDetectorBanner = "🎙️ \(speakerBadge) (\(Int(diarizationResult.pitchHz)) Hz)\(modeTag)"
                    } else {
                        self.liveDetectorBanner = "🎙️ \(speakerBadge)\(modeTag)"
                    }
                }
            }
        }
    }

    private func startRecordingTimer(fps: Double) {
        highPrecisionTimer?.invalidate()
        let clampedFPS = max(1.0, min(60.0, fps))
        highPrecisionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / clampedFPS, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard self.state == .recording else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let currentElapsed = self.accumulatedTimeBeforePause + (now - self.lastResumeMachTime)
                self.elapsedTime = currentElapsed

                // Rotar el fragmento en disco cada 30s para garantizar audio salvable incluso ante cierre abrupto de iOS
                self.rotateAudioChunkIfNeeded(at: currentElapsed)

                let (measuredRMS, measuredDB, bandsSnapshot) = self.meteringLock.withLock {
                    (self.latestMeasuredRMS, self.latestCurrentDecibels, self.latestSpectralBands)
                }

                let sample = max(0.04, min(1.0, measuredRMS))

                if self.isAppInBackground {
                    // En segundo plano conservar puntos ligeros sin disparar redibujado SwiftUI a 60 Hz
                    let currentDeciSecond = Int(currentElapsed * 10.0)
                    if currentDeciSecond > self.lastTimelineSampleIndex {
                        let missing = currentDeciSecond - self.lastTimelineSampleIndex
                        self.fullRecordingWaveform.append(contentsOf: repeatElement(sample, count: min(missing, 12)))
                        if missing > 12 {
                            self.fullRecordingWaveform.append(contentsOf: repeatElement(Float(0.12), count: missing - 12))
                        }
                        self.lastTimelineSampleIndex = currentDeciSecond
                    }
                } else {
                    self.currentDecibels = measuredDB
                    self.normalizedLevel = measuredRMS

                    self.liveWaveformWindow.append(sample)
                    if self.liveWaveformWindow.count > 96 {
                        self.liveWaveformWindow.removeFirst(self.liveWaveformWindow.count - 96)
                    }

                    let currentDeciSecond = Int(currentElapsed * 10.0)
                    if currentDeciSecond > self.lastTimelineSampleIndex {
                        let missing = currentDeciSecond - self.lastTimelineSampleIndex
                        if missing <= 5 {
                            for _ in 0..<missing {
                                self.liveTimelineSamples.append(sample)
                                self.fullRecordingWaveform.append(sample)
                            }
                        } else {
                            let filler = Float(0.12)
                            self.liveTimelineSamples.append(contentsOf: repeatElement(filler, count: missing))
                            self.fullRecordingWaveform.append(contentsOf: repeatElement(filler, count: missing))
                        }
                        self.lastTimelineSampleIndex = currentDeciSecond
                    }

                    for i in 0..<min(self.liveSpectrumBands.count, bandsSnapshot.count) {
                        self.liveSpectrumBands[i] = (self.liveSpectrumBands[i] * 0.55) + (bandsSnapshot[i] * 0.45)
                    }
                }

                // Actualizar la tarjeta persistente en la pantalla bloqueada (LiveActivityManager ya aplica throttle de 1s)
                let speakerBadge = self.liveSpeakers.first(where: { $0.id == self.activeSpeakerId })?.shortBadgeCode ?? L10n.speakerShortBadge(1)
                LiveActivityManager.shared.updateLockScreenProgress(
                    title: self.liveCustomDraftTitle,
                    startDate: self.recordingStartDate ?? Date(),
                    elapsedTime: currentElapsed,
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

    private func rotateAudioChunkIfNeeded(at elapsed: TimeInterval) {
        guard state == .recording,
              !isRotatingChunk,
              (elapsed - currentChunkStartElapsed) >= chunkRotationIntervalSeconds,
              let sessionID = activeSessionID,
              let fmt = cachedAudioFormat else {
            return
        }

        isRotatingChunk = true
        currentChunkStartElapsed = elapsed
        let nextIndex = currentChunkIndex + 1
        currentChunkIndex = nextIndex

        let nextChunkName = Self.chunkFilename(index: nextIndex, format: selectedFormat)
        let sessionDir = RecordingStorageService.sessionDirectoryURL(for: sessionID)
        let nextURL = sessionDir.appendingPathComponent(nextChunkName)
        let settings = cachedAudioSettings

        fileRotationQueue.async { [weak self] in
            guard let self = self else { return }
            let newFile = try? AVAudioFile(
                forWriting: nextURL,
                settings: settings,
                commonFormat: fmt.commonFormat,
                interleaved: fmt.isInterleaved
            )

            if let newFile {
                self.fileWriteLock.lock()
                let previousFile = self.outputAudioFile
                self.outputAudioFile = newFile
                self.fileWriteLock.unlock()
                // Liberar previousFile fuera del lock para cerrar y sellar el átomo moov de M4A en disco
                _ = previousFile
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if newFile != nil {
                    self.chunkFileNames.append(nextChunkName)
                    self.persistSessionCheckpointSnapshot()
                }
                self.isRotatingChunk = false
            }
        }
    }

    private func persistSessionCheckpointSnapshot() {
        guard let sessionID = activeSessionID,
              let start = recordingStartDate else {
            return
        }
        let checkpoint = ActiveRecordingCheckpoint(
            sessionID: sessionID,
            directoryName: "Session_\(sessionID.uuidString)",
            title: liveCustomDraftTitle,
            createdAt: start,
            formatRaw: selectedFormat.rawValue,
            sampleRate: cachedAudioFormat?.sampleRate ?? selectedSampleRate.rawValue,
            channelCount: Int(cachedAudioFormat?.channelCount ?? 1),
            chunkFileNames: chunkFileNames,
            estimatedDuration: elapsedTime,
            tags: activeSessionTags,
            bookmarks: liveBookmarks,
            speakers: diarizationService.detectedSpeakers,
            waveformSamples: Self.downsampleWaveform(fullRecordingWaveform, targetCount: 220)
        )
        fileRotationQueue.async {
            RecordingStorageService.saveCheckpoint(checkpoint)
        }
    }

    private static func chunkFilename(index: Int, format: AudioFormatOption) -> String {
        String(format: "chunk_%04d.%@", index, format.rawValue)
    }

    private nonisolated static func clonePCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let channelCount = Int(buffer.format.channelCount)
        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            let byteCount = Int(buffer.frameLength) * MemoryLayout<Float>.size
            for ch in 0..<channelCount {
                memcpy(dst[ch], src[ch], byteCount)
            }
            return copy
        }
        if let srcInt16 = buffer.int16ChannelData, let dstInt16 = copy.int16ChannelData {
            let intBytes = Int(buffer.frameLength) * MemoryLayout<Int16>.size
            for ch in 0..<channelCount {
                memcpy(dstInt16[ch], srcInt16[ch], intBytes)
            }
            return copy
        }
        return nil
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
            Task { @MainActor [weak self] in
                self?.endBackgroundExecutionSafetyTask()
            }
        }
    }

    private func endBackgroundExecutionSafetyTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    nonisolated static func queryFileSizeBytes(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    /// Calcula SHA-256 leyendo en bloques de 64 KB para evitar picos de RAM en grabaciones de varias horas.
    nonisolated static func computeSHA256Streaming(at url: URL) -> String {
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
