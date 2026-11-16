import Foundation
import AVFoundation
import Speech
import Combine

/// Gestor central de `AVAudioSession` y permisos del sistema (Micrófono, Reconocimiento de Voz y Ejecución en Segundo Plano).
@MainActor
final class AudioSessionManager: ObservableObject {
    static let shared = AudioSessionManager()

    @Published private(set) var microphonePermissionGranted: Bool = false
    @Published private(set) var speechPermissionGranted: Bool = false
    @Published private(set) var currentInputRouteName: String = "Micrófono del iPhone"
    @Published private(set) var isInterrupted: Bool = false

    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        refreshCurrentPermissionStatus()
        observeAudioSessionNotifications()
        updateCurrentRouteDescription()
    }

    /// Verifica el estado actual de permisos sin bloquear la interfaz.
    func refreshCurrentPermissionStatus() {
        if #available(iOS 17.0, *) {
            microphonePermissionGranted = (AVAudioApplication.shared.recordPermission == .granted)
        } else {
            microphonePermissionGranted = (AVAudioSession.sharedInstance().recordPermission == .granted)
        }
        speechPermissionGranted = (SFSpeechRecognizer.authorizationStatus() == .authorized)
    }

    /// Solicita permisos de Micrófono y Reconocimiento de Voz en Español.
    func requestAllPermissions() async -> (microphone: Bool, speech: Bool) {
        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        let speechGranted: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        self.microphonePermissionGranted = micGranted
        self.speechPermissionGranted = speechGranted
        return (micGranted, speechGranted)
    }

    /// Configura `AVAudioSession` para grabación continua en alta fidelidad incluso con pantalla bloqueada o en segundo plano.
    func configureForBackgroundRecording(preferredSampleRate: Double = 48000.0) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [
                .defaultToSpeaker,
                .allowBluetooth,
                .allowBluetoothA2DP,
                .allowAirPlay
            ]
        )
        try session.setPreferredSampleRate(preferredSampleRate)
        try session.setPreferredIOBufferDuration(0.016) // ~60 FPS (16ms) para respuesta visual ultrarrápida
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        updateCurrentRouteDescription()
    }

    /// Configura `AVAudioSession` para reproducción interactiva con soporte de segundo plano.
    func configureForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        updateCurrentRouteDescription()
    }

    func updateCurrentRouteDescription() {
        let session = AVAudioSession.sharedInstance()
        if let input = session.currentRoute.inputs.first {
            currentInputRouteName = input.portName
        } else {
            currentInputRouteName = "Micrófono Integrado iPhone"
        }
    }

    private func observeAudioSessionNotifications() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleInterruption(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateCurrentRouteDescription()
            }
            .store(in: &cancellables)
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            isInterrupted = true
            onInterruptionBegan?()
        case .ended:
            isInterrupted = false
            var shouldResume = false
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                shouldResume = options.contains(.shouldResume)
            }
            try? AVAudioSession.sharedInstance().setActive(true)
            onInterruptionEnded?(shouldResume)
        @unknown default:
            break
        }
    }
}
