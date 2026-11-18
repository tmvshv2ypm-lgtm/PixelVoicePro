import Foundation
import UIKit
import MediaPlayer
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)
/// Atributos de ActivityKit para la Live Activity de grabación en la pantalla bloqueada y Dynamic Island.
@available(iOS 16.2, *)
struct PixelVoiceRecordingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var startDate: Date
        var elapsedSeconds: Int
        var isPaused: Bool
        var activeSpeakerName: String
        var audioFormatBadge: String
    }

    var sessionIdentifier: String
    var exactStartTimestamp: String
}
#endif

/// Gestor de presencia persistente en Pantalla Bloqueada (Lock Screen):
/// Combina `ActivityKit` (Live Activity) con `MPNowPlayingInfoCenter` y `MPRemoteCommandCenter`
/// para mostrar en la pantalla de bloqueo del iPhone el punto rojo "Grabando en vivo", el título de la nota,
/// el cronómetro corriendo en tiempo real (`HH:MM:SS`) y controles de Pausa/Reanudar/Marcador sin desbloquear el teléfono.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var cachedArtwork: MPMediaItemArtwork?
    private var lastArtworkStatePaused: Bool?
    private var lastUpdateSecond: Int = -1
    private var remoteCommandsConfigured: Bool = false

    var onTogglePauseFromLockScreen: (() -> Void)?
    var onAddBookmarkFromLockScreen: (() -> Void)?

    #if canImport(ActivityKit)
    private var currentActivity: Any?
    #endif

    private init() {}

    /// Inicia la tarjeta persistente en la pantalla bloqueada (Live Activity + Lock Screen Now Playing Card).
    func startLockScreenActivity(
        title: String,
        startDate: Date,
        formatBadge: String,
        activeSpeaker: String = L10n.speakerDefaultName(1)
    ) {
        lastUpdateSecond = -1
        lastArtworkStatePaused = nil
        configureLockScreenRemoteCommands()

        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.lockscreenRecordingTitle
            : title

        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            if ActivityAuthorizationInfo().areActivitiesEnabled {
                let attributes = PixelVoiceRecordingAttributes(
                    sessionIdentifier: UUID().uuidString,
                    exactStartTimestamp: ExactDateFormatter.fullExactTimestamp(from: startDate)
                )
                let initialState = PixelVoiceRecordingAttributes.ContentState(
                    title: resolvedTitle,
                    startDate: startDate,
                    elapsedSeconds: 0,
                    isPaused: false,
                    activeSpeakerName: activeSpeaker,
                    audioFormatBadge: formatBadge
                )
                let content = ActivityContent(state: initialState, staleDate: nil)
                currentActivity = try? Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            }
        }
        #endif

        updateLockScreenProgress(
            title: resolvedTitle,
            startDate: startDate,
            elapsedTime: 0.0,
            isPaused: false,
            activeSpeaker: activeSpeaker,
            formatBadge: formatBadge,
            force: true
        )
    }

    /// Actualiza segundo a segundo el cronómetro `HH:MM:SS` y el estado en la pantalla de bloqueo del iPhone.
    func updateLockScreenProgress(
        title: String,
        startDate: Date,
        elapsedTime: TimeInterval,
        isPaused: Bool,
        activeSpeaker: String,
        formatBadge: String,
        force: Bool = false
    ) {
        let currentSecond = Int(elapsedTime)
        guard force || currentSecond != lastUpdateSecond else { return }
        lastUpdateSecond = currentSecond

        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.lockscreenInProgress
            : title
        let formattedTimer = Self.formatHHMMSS(currentSecond)
        let statusPrefix = isPaused ? L10n.lockscreenStatusPaused : L10n.lockscreenStatusLive

        if cachedArtwork == nil || lastArtworkStatePaused != isPaused || (currentSecond % 15 == 0) {
            cachedArtwork = generateLockScreenBadgeArtwork(
                isPaused: isPaused,
                timerText: formattedTimer,
                formatBadge: formatBadge
            )
            lastArtworkStatePaused = isPaused
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: "\(statusPrefix) · \( formattedTimer )",
            MPMediaItemPropertyArtist: "\(resolvedTitle) • \(activeSpeaker)",
            MPMediaItemPropertyAlbumTitle: "Voice Notes (\(formatBadge))",
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedTime,
            MPMediaItemPropertyPlaybackDuration: max(elapsedTime + 3600.0, 3600.0),
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0
        ]

        if let artwork = cachedArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = isPaused ? .paused : .playing

        #if canImport(ActivityKit)
        if #available(iOS 16.2, *),
           let activity = currentActivity as? Activity<PixelVoiceRecordingAttributes> {
            let updatedState = PixelVoiceRecordingAttributes.ContentState(
                title: resolvedTitle,
                startDate: startDate,
                elapsedSeconds: currentSecond,
                isPaused: isPaused,
                activeSpeakerName: activeSpeaker,
                audioFormatBadge: formatBadge
            )
            Task {
                await activity.update(ActivityContent(state: updatedState, staleDate: nil))
            }
        }
        #endif
    }

    /// Cierra y limpia la tarjeta de la pantalla de bloqueo al finalizar la grabación.
    func stopLockScreenActivity() {
        lastUpdateSecond = -1
        cachedArtwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        disableLockScreenRemoteCommands()

        #if canImport(ActivityKit)
        if #available(iOS 16.2, *),
           let activity = currentActivity as? Activity<PixelVoiceRecordingAttributes> {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            currentActivity = nil
        }
        #endif
    }

    // MARK: - Controles Interactivos en la Pantalla Bloqueada

    private func configureLockScreenRemoteCommands() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.bookmarkCommand.isEnabled = true
        commandCenter.bookmarkCommand.localizedTitle = L10n.lockscreenAddBookmark

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onTogglePauseFromLockScreen?() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onTogglePauseFromLockScreen?() }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onTogglePauseFromLockScreen?() }
            return .success
        }
        commandCenter.bookmarkCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onAddBookmarkFromLockScreen?() }
            return .success
        }
    }

    private func disableLockScreenRemoteCommands() {
        guard remoteCommandsConfigured else { return }
        remoteCommandsConfigured = false
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.bookmarkCommand.removeTarget(nil)
    }

    // MARK: - Generador de Carátula en Vivo para la Pantalla de Bloqueo

    private func generateLockScreenBadgeArtwork(isPaused: Bool, timerText: String, formatBadge: String) -> MPMediaItemArtwork {
        let size = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.055, green: 0.067, blue: 0.090, alpha: 1.0).setFill()
            ctx.fill(rect)

            // Círculo exterior brillante
            let circleRect = CGRect(x: 36, y: 36, width: 228, height: 228)
            let accentColor = isPaused
                ? UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0)
                : UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1.0)

            accentColor.withAlphaComponent(0.18).setFill()
            UIBezierPath(ovalIn: circleRect).fill()

            accentColor.setStroke()
            let strokePath = UIBezierPath(ovalIn: circleRect)
            strokePath.lineWidth = 6
            strokePath.stroke()

            // Punto rojo central de "Grabando en vivo"
            let dotRect = CGRect(x: 118, y: 78, width: 64, height: 64)
            accentColor.setFill()
            UIBezierPath(ovalIn: dotRect).fill()

            // Texto de cronómetro HH:MM:SS en la tarjeta
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            let timerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 32, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            NSString(string: timerText).draw(in: CGRect(x: 20, y: 162, width: 260, height: 42), withAttributes: timerAttrs)

            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .bold),
                .foregroundColor: accentColor,
                .paragraphStyle: paragraph
            ]
            let stateText = isPaused ? L10n.lockscreenBadgePaused : L10n.lockscreenBadgeLive(formatBadge)
            NSString(string: stateText).draw(in: CGRect(x: 20, y: 208, width: 260, height: 24), withAttributes: subAttrs)
        }

        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }

    private static func formatHHMMSS(_ totalSeconds: Int) -> String {
        let clamped = max(0, totalSeconds)
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        let s = clamped % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
