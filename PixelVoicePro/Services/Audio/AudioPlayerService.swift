import Foundation
import AVFoundation
import Combine

/// Motor de Reproducción Interactiva Pro (`AVAudioEngine` + `AVAudioUnitTimePitch` + `AVAudioUnitEQ`)
/// con sincronización Karaoke a 60 Hz, salida al altavoz principal, velocidad variable sin cambio de tono (0.5x - 2.0x),
/// "Saltar Silencios" automático y "Aislamiento de Voz" DSP en tiempo real estilo Apple.
@MainActor
final class AudioPlayerService: ObservableObject {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0.0
    @Published private(set) var duration: TimeInterval = 0.0
    @Published var playbackSpeed: PlaybackSpeedOption = .x1_0 {
        didSet {
            applyPlaybackRate()
        }
    }
    @Published var skipSilenceEnabled: Bool = false
    @Published var voiceIsolationEnabled: Bool = false {
        didSet {
            applyVoiceIsolationSettings()
        }
    }
    @Published private(set) var totalSilenceSavedSeconds: TimeInterval = 0.0
    @Published private(set) var isCurrentlySkippingSilence: Bool = false

    /// Estado de sincronización Karaoke en tiempo real
    @Published private(set) var activeSegmentId: UUID?
    @Published private(set) var activeWordId: UUID?
    @Published private(set) var activeSpeakerId: String?
    @Published private(set) var activeAcousticEventId: UUID?

    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var timePitchNode = AVAudioUnitTimePitch()
    private var voiceIsolationEQ = AVAudioUnitEQ(numberOfBands: 5)
    private var isEngineGraphConfigured: Bool = false

    private var audioFile: AVAudioFile?
    private var fileSampleRate: Double = 44100.0
    private var totalFrames: AVAudioFramePosition = 0
    private var seekStartFrame: AVAudioFramePosition = 0
    private var playbackGeneration: Int = 0

    private var syncTimer: Timer?
    private var currentRecording: VoiceRecording?
    private var currentAudioURL: URL?

    init() {
        configureVoiceIsolationEQProfile()
    }

    /// Configura las 5 bandas DSP del filtro "Aislamiento de Voz":
    /// 1) Pasa-altas 120 Hz (aire acondicionado / golpes)
    /// 2) Atenuación 250 Hz (eco de salón)
    /// 3) Realce vocal 1.85 kHz (cuerpo de la voz)
    /// 4) Realce 3.5 kHz (consonantes e inteligibilidad)
    /// 5) Pasa-bajas 7.4 kHz (siseo de micrófono)
    private func configureVoiceIsolationEQProfile() {
        let bands = voiceIsolationEQ.bands
        guard bands.count >= 5 else { return }

        bands[0].filterType = .highPass
        bands[0].frequency = 120.0
        bands[0].bypass = false

        bands[1].filterType = .parametric
        bands[1].frequency = 250.0
        bands[1].bandwidth = 1.0
        bands[1].gain = -4.0
        bands[1].bypass = false

        bands[2].filterType = .parametric
        bands[2].frequency = 1850.0
        bands[2].bandwidth = 1.1
        bands[2].gain = 4.0
        bands[2].bypass = false

        bands[3].filterType = .parametric
        bands[3].frequency = 3500.0
        bands[3].bandwidth = 1.1
        bands[3].gain = 5.5
        bands[3].bypass = false

        bands[4].filterType = .lowPass
        bands[4].frequency = 7400.0
        bands[4].bypass = false

        applyVoiceIsolationSettings()
    }

    private func applyVoiceIsolationSettings() {
        voiceIsolationEQ.bypass = !voiceIsolationEnabled
        voiceIsolationEQ.globalGain = voiceIsolationEnabled ? 2.0 : 0.0
    }

    private func rebuildAudioEngineGraph(format: AVAudioFormat) {
        playbackGeneration &+= 1
        playerNode.stop()
        audioEngine.stop()
        audioEngine.reset()

        playerNode = AVAudioPlayerNode()
        timePitchNode = AVAudioUnitTimePitch()
        timePitchNode.rate = playbackSpeed.rawValue
        voiceIsolationEQ = AVAudioUnitEQ(numberOfBands: 5)
        configureVoiceIsolationEQProfile()

        audioEngine.attach(playerNode)
        audioEngine.attach(timePitchNode)
        audioEngine.attach(voiceIsolationEQ)

        audioEngine.connect(playerNode, to: timePitchNode, format: format)
        audioEngine.connect(timePitchNode, to: voiceIsolationEQ, format: format)
        audioEngine.connect(voiceIsolationEQ, to: audioEngine.mainMixerNode, format: nil)

        audioEngine.prepare()
        isEngineGraphConfigured = true
    }

    /// Carga una grabación y verifica que su archivo de audio exista y sea reproducible desde `FileManager`.
    func loadRecording(_ recording: VoiceRecording, audioFileURL: URL) {
        stop()
        self.currentRecording = recording
        self.duration = max(0.1, recording.duration)
        self.currentTime = 0.0
        self.totalSilenceSavedSeconds = 0.0
        self.seekStartFrame = 0

        let resolvedURL = RecordingStorageService.ensurePlayableAudioFileExists(
            for: recording,
            expectedURL: audioFileURL
        )
        self.currentAudioURL = resolvedURL

        try? AudioSessionManager.shared.configureForPlayback()

        if FileManager.default.fileExists(atPath: resolvedURL.path) {
            do {
                let file = try AVAudioFile(forReading: resolvedURL)
                let fmt = file.processingFormat
                self.audioFile = file
                self.fileSampleRate = max(8000.0, fmt.sampleRate)
                self.totalFrames = file.length
                if file.length > 0, fmt.sampleRate > 0 {
                    self.duration = max(0.1, Double(file.length) / fmt.sampleRate)
                }
                rebuildAudioEngineGraph(format: fmt)
            } catch {
                self.audioFile = nil
                self.totalFrames = 0
                self.isEngineGraphConfigured = false
            }
        }
        updateKaraokeSynchronization(at: 0.0)
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        try? AudioSessionManager.shared.configureForPlayback()

        if currentTime >= duration - 0.05 {
            currentTime = 0.0
            updateKaraokeSynchronization(at: 0.0)
        }

        if audioFile == nil, let recording = currentRecording {
            let fallbackURL = currentAudioURL ?? RecordingStorageService.audioFileURL(for: recording.audioFileName)
            let validURL = RecordingStorageService.ensurePlayableAudioFileExists(for: recording, expectedURL: fallbackURL)
            if let loaded = try? AVAudioFile(forReading: validURL) {
                self.audioFile = loaded
                self.fileSampleRate = max(8000.0, loaded.processingFormat.sampleRate)
                self.totalFrames = loaded.length
                if loaded.length > 0 {
                    self.duration = max(0.1, Double(loaded.length) / self.fileSampleRate)
                }
                rebuildAudioEngineGraph(format: loaded.processingFormat)
            }
        }

        scheduleAndStartPlayback(from: currentTime)
        isPlaying = true
        start60HzSyncTimer()
    }

    func pause() {
        if isPlaying {
            currentTime = resolveCurrentNodePlaybackTime() ?? currentTime
        }
        playbackGeneration &+= 1
        playerNode.stop()
        isPlaying = false
        syncTimer?.invalidate()
        syncTimer = nil
    }

    func stop() {
        playbackGeneration &+= 1
        playerNode.stop()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        isPlaying = false
        syncTimer?.invalidate()
        syncTimer = nil
        currentTime = 0.0
        seekStartFrame = 0
        activeSegmentId = nil
        activeWordId = nil
        activeAcousticEventId = nil
    }

    /// Salta instantáneamente al segundo exacto indicado (ej. al tocar una palabra, párrafo, marcador o evento acústico).
    func seek(to targetTime: TimeInterval, autoPlay: Bool = true) {
        let clamped = max(0.0, min(duration, targetTime))
        currentTime = clamped
        updateKaraokeSynchronization(at: clamped)

        if autoPlay {
            if !isPlaying {
                play()
            } else {
                scheduleAndStartPlayback(from: clamped)
            }
        } else if isPlaying {
            scheduleAndStartPlayback(from: clamped)
        }
    }

    /// Controles Pro de salto relativo (-10s, -5s, +5s, +10s)
    func skip(by deltaSeconds: TimeInterval) {
        let target = max(0.0, min(duration, currentTime + deltaSeconds))
        seek(to: target, autoPlay: isPlaying)
    }

    private func applyPlaybackRate() {
        timePitchNode.rate = playbackSpeed.rawValue
    }

    private func scheduleAndStartPlayback(from time: TimeInterval) {
        guard let file = audioFile, totalFrames > 0 else { return }

        if !isEngineGraphConfigured {
            rebuildAudioEngineGraph(format: file.processingFormat)
        }
        if !audioEngine.isRunning {
            audioEngine.prepare()
            try? audioEngine.start()
        }

        playbackGeneration &+= 1
        let activeGen = playbackGeneration
        playerNode.stop()

        let clamped = max(0.0, min(duration, time))
        let startFrame = min(totalFrames - 1, max(0, AVAudioFramePosition(clamped * fileSampleRate)))
        let remaining = max(1, totalFrames - startFrame)
        seekStartFrame = startFrame

        timePitchNode.rate = playbackSpeed.rawValue
        applyVoiceIsolationSettings()

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remaining),
            at: nil
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleSegmentNaturalCompletion(generation: activeGen)
            }
        }
        playerNode.play()
    }

    private func handleSegmentNaturalCompletion(generation: Int) {
        guard generation == playbackGeneration, isPlaying else { return }
        isPlaying = false
        currentTime = duration
        syncTimer?.invalidate()
        syncTimer = nil
        updateKaraokeSynchronization(at: duration)
    }

    private func resolveCurrentNodePlaybackTime() -> TimeInterval? {
        guard playerNode.isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleTime >= 0 else {
            return nil
        }
        let elapsedFrames = seekStartFrame + playerTime.sampleTime
        let seconds = Double(elapsedFrames) / max(1.0, fileSampleRate)
        return max(0.0, min(duration, seconds))
    }

    // MARK: - Sincronización Audio-Texto (Karaoke 60 Hz) y "Saltar Silencios"

    private func start60HzSyncTimer() {
        syncTimer?.invalidate()
        let interval: TimeInterval = 1.0 / 60.0
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.tickPlayback(delta: interval)
            }
        }
        if let timer = syncTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func tickPlayback(delta: TimeInterval) {
        guard isPlaying else { return }

        if let exactNodeTime = resolveCurrentNodePlaybackTime() {
            currentTime = exactNodeTime
        } else if audioFile == nil {
            currentTime += delta * Double(playbackSpeed.rawValue)
            if currentTime >= duration {
                currentTime = duration
                pause()
                return
            }
        }

        // Verificar si "Saltar silencios" está activo y entramos en un intervalo de silencio
        if skipSilenceEnabled, let recording = currentRecording {
            if let silence = recording.silenceIntervals.first(where: {
                $0.duration >= 0.45 && currentTime >= $0.startTime + 0.08 && currentTime < $0.endTime - 0.12
            }) {
                let jumpTarget = min(duration, silence.endTime - 0.05)
                let saved = max(0, jumpTarget - currentTime)
                if saved > 0.05 {
                    totalSilenceSavedSeconds += saved
                    isCurrentlySkippingSilence = true
                    currentTime = jumpTarget
                    scheduleAndStartPlayback(from: jumpTarget)

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 380_000_000)
                        self.isCurrentlySkippingSilence = false
                    }
                }
            }
        }

        updateKaraokeSynchronization(at: currentTime)
    }

    /// Calcula qué párrafo, palabra exacta y evento acústico están activos en el instante `time`.
    func updateKaraokeSynchronization(at time: TimeInterval) {
        guard let recording = currentRecording else { return }
        let segments = recording.segments

        var matchedSegmentId: UUID?
        var matchedWordId: UUID?
        var matchedSpeakerId: String?

        for segment in segments {
            if time >= segment.startTime - 0.08 && time <= segment.endTime + 0.25 {
                matchedSegmentId = segment.id
                matchedSpeakerId = segment.speakerId

                if let exactWord = segment.words.first(where: { $0.isActive(at: time) }) {
                    matchedWordId = exactWord.id
                } else if let closestWord = segment.words.lastOrClosest(at: time) {
                    matchedWordId = closestWord.id
                }
                break
            }
        }

        let matchedEvent = recording.acousticEvents.first { event in
            time >= event.timestamp - 0.15 && time <= (event.timestamp + max(0.8, event.duration))
        }

        if activeSegmentId != matchedSegmentId {
            activeSegmentId = matchedSegmentId
        }
        if activeWordId != matchedWordId {
            activeWordId = matchedWordId
        }
        if activeSpeakerId != matchedSpeakerId {
            activeSpeakerId = matchedSpeakerId
        }
        if activeAcousticEventId != matchedEvent?.id {
            activeAcousticEventId = matchedEvent?.id
        }
    }
}

private extension Array where Element == WordTimestamp {
    func lastOrClosest(at time: TimeInterval) -> WordTimestamp? {
        guard !isEmpty else { return nil }
        var candidate: WordTimestamp?
        for word in self {
            if word.startTime <= time + 0.08 {
                candidate = word
            } else {
                break
            }
        }
        return candidate ?? first
    }
}
