import Foundation
import AVFoundation
import Combine

/// Motor de Reproducción Interactiva Pro con sincronización Karaoke a 60 Hz,
/// salida forzada al altavoz principal inferior del iPhone, control de velocidad (0.5x - 2.0x),
/// saltos precisos (-10s, -5s, +5s, +10s) y "Saltar Silencios" automático.
@MainActor
final class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0.0
    @Published private(set) var duration: TimeInterval = 0.0
    @Published var playbackSpeed: PlaybackSpeedOption = .x1_0 {
        didSet {
            applyPlaybackRate()
        }
    }
    @Published var skipSilenceEnabled: Bool = false
    @Published private(set) var totalSilenceSavedSeconds: TimeInterval = 0.0
    @Published private(set) var isCurrentlySkippingSilence: Bool = false

    /// Estado de sincronización Karaoke en tiempo real
    @Published private(set) var activeSegmentId: UUID?
    @Published private(set) var activeWordId: UUID?
    @Published private(set) var activeSpeakerId: String?
    @Published private(set) var activeAcousticEventId: UUID?

    private var audioPlayer: AVAudioPlayer?
    private var syncTimer: Timer?
    private var currentRecording: VoiceRecording?
    private var currentAudioURL: URL?

    /// Configura explícitamente `AVAudioSession` para forzar la salida de audio por el altavoz principal del iPhone.
    private func forceSpeakerOutputAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.overrideOutputAudioPort(.speaker)
            try session.setActive(true)
        } catch {
            print("Error configurando AVAudioSession hacia el altavoz principal: \(error)")
        }
    }

    /// Carga una grabación y verifica que su archivo de audio exista y sea reproducible desde `FileManager`.
    func loadRecording(_ recording: VoiceRecording, audioFileURL: URL) {
        stop()
        self.currentRecording = recording
        self.duration = max(0.1, recording.duration)
        self.currentTime = 0.0
        self.totalSilenceSavedSeconds = 0.0

        // Verificar que el archivo exista y tenga contenido de audio válido en FileManager
        let resolvedURL = RecordingStorageService.ensurePlayableAudioFileExists(
            for: recording,
            expectedURL: audioFileURL
        )
        self.currentAudioURL = resolvedURL

        forceSpeakerOutputAudioSession()

        if FileManager.default.fileExists(atPath: resolvedURL.path) {
            do {
                let player = try AVAudioPlayer(contentsOf: resolvedURL)
                player.delegate = self
                player.enableRate = true
                player.volume = 1.0
                player.rate = playbackSpeed.rawValue
                player.prepareToPlay()
                self.audioPlayer = player
                if player.duration > 0 {
                    self.duration = player.duration
                }
            } catch {
                print("Error inicializando AVAudioPlayer: \(error)")
                self.audioPlayer = nil
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
        // Configurar explícitamente la ruta de audio hacia el altavoz principal justo antes de iniciar cualquier reproducción
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.overrideOutputAudioPort(.speaker)
            try session.setActive(true)
        } catch {
            print("Error configurando AVAudioSession en play(): \(error)")
        }

        if currentTime >= duration - 0.05 {
            seek(to: 0.0, autoPlay: false)
        }

        if audioPlayer == nil, let recording = currentRecording {
            let fallbackURL = currentAudioURL ?? RecordingStorageService.audioFileURL(for: recording.audioFileName)
            let validURL = RecordingStorageService.ensurePlayableAudioFileExists(for: recording, expectedURL: fallbackURL)
            if let recreatedPlayer = try? AVAudioPlayer(contentsOf: validURL) {
                recreatedPlayer.delegate = self
                recreatedPlayer.enableRate = true
                recreatedPlayer.volume = 1.0
                recreatedPlayer.prepareToPlay()
                self.audioPlayer = recreatedPlayer
            }
        }

        if let player = audioPlayer {
            player.volume = 1.0
            player.rate = playbackSpeed.rawValue
            player.currentTime = currentTime
            player.play()
        }
        isPlaying = true
        start60HzSyncTimer()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        syncTimer?.invalidate()
        syncTimer = nil
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        syncTimer?.invalidate()
        syncTimer = nil
        currentTime = 0.0
        activeSegmentId = nil
        activeWordId = nil
        activeAcousticEventId = nil
    }

    /// Salta instantáneamente al segundo exacto indicado (ej. al tocar una palabra, párrafo, marcador o etiqueta `[😂 Risas - 02:14]`).
    func seek(to targetTime: TimeInterval, autoPlay: Bool = true) {
        let clamped = max(0.0, min(duration, targetTime))
        currentTime = clamped
        audioPlayer?.currentTime = clamped
        updateKaraokeSynchronization(at: clamped)

        if autoPlay && !isPlaying {
            play()
        }
    }

    /// Controles Pro de salto relativo (-10s, -5s, +5s, +10s)
    func skip(by deltaSeconds: TimeInterval) {
        let target = max(0.0, min(duration, currentTime + deltaSeconds))
        seek(to: target, autoPlay: isPlaying)
    }

    private func applyPlaybackRate() {
        audioPlayer?.rate = playbackSpeed.rawValue
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

        if let player = audioPlayer, player.isPlaying {
            currentTime = player.currentTime
        } else {
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
                    audioPlayer?.currentTime = jumpTarget

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

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = self.duration
            self.syncTimer?.invalidate()
            self.syncTimer = nil
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
