import Foundation
import AVFoundation
import SoundAnalysis
import Accelerate

/// Analizador de Eventos Acústicos y Sonidos No Verbales basado en `SoundAnalysis` (CoreML de Apple) y DSP (`vDSP`).
/// Soporta tanto modo en vivo como análisis completo post-grabación para ahorrar batería en clases largas.
final class AcousticEventAnalyzer: NSObject, SNResultsObserving {
    private let analysisQueue = DispatchQueue(label: "com.pixelvoicepro.soundanalysis", qos: .userInitiated)
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var currentSampleTime: AVAudioFramePosition = 0

    private(set) var detectedEvents: [AcousticEvent] = []
    private(set) var silenceIntervals: [SilenceInterval] = []

    /// Seguimiento de silencios en tiempo real para insertar `[⏸️ Pausa larga]` y alimentar "Saltar Silencios"
    private var silenceStartTime: TimeInterval?
    private var lastEventByType: [AcousticEventType: TimeInterval] = [:]

    /// Umbral en segundos para considerar un silencio como `[⏸️ Pausa larga]` en la transcripción
    private let longPauseThresholdSeconds: TimeInterval = 2.5
    /// Umbral en segundos para registrar un `SilenceInterval` omitible por el reproductor "Saltar silencios"
    private let skippableSilenceThresholdSeconds: TimeInterval = 0.45

    /// Callback disparado en el hilo principal cada vez que se detecta un nuevo evento acústico no verbal
    var onAcousticEventDetected: ((AcousticEvent) -> Void)?
    /// Callback para el estado sutil en vivo de la cabina de grabación
    var onLiveStatusChanged: ((String, AcousticEventType?) -> Void)?

    func reset() {
        detectedEvents.removeAll()
        silenceIntervals.removeAll()
        silenceStartTime = nil
        lastEventByType.removeAll()
        currentSampleTime = 0
    }

    /// Configura el `SNAudioStreamAnalyzer` con el formato del bus de entrada de `AVAudioEngine`.
    func startLiveStreamAnalysis(format: AVAudioFormat) {
        analysisQueue.sync {
            let analyzer = SNAudioStreamAnalyzer(format: format)
            self.streamAnalyzer = analyzer
            do {
                let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                request.windowDuration = CMTimeMakeWithSeconds(1.2, preferredTimescale: 48000)
                request.overlapFactor = 0.5
                try analyzer.add(request, withObserver: self)
            } catch {
                // El detector DSP de pausas sigue activo
            }
        }
    }

    func stopLiveStreamAnalysis(finalDuration: TimeInterval) {
        if let start = silenceStartTime {
            finalizeSilenceInterval(from: start, to: finalDuration)
            silenceStartTime = nil
        }
        analysisQueue.sync {
            streamAnalyzer?.removeAllRequests()
            streamAnalyzer = nil
        }
    }

    /// Alimenta un `AVAudioPCMBuffer` tanto al `SNAudioStreamAnalyzer` como al detector de pausas y silencios DSP.
    func analyzeBuffer(_ buffer: AVAudioPCMBuffer, at timestamp: TimeInterval, runMLStream: Bool = true) {
        let framePosition = currentSampleTime
        currentSampleTime += AVAudioFramePosition(buffer.frameLength)

        if runMLStream {
            analysisQueue.async { [weak self] in
                self?.streamAnalyzer?.analyze(buffer, atAudioFramePosition: framePosition)
            }
        }

        // Análisis ligero de energía RMS para detectar silencios largos e intervalos omitibles con consumo casi nulo de CPU
        guard let floatData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var rms: Float = 0.0
        vDSP_rmsqv(floatData, 1, &rms, vDSP_Length(frameCount))

        let isSilent = rms < 0.011
        if isSilent {
            if silenceStartTime == nil {
                silenceStartTime = timestamp
            } else if let start = silenceStartTime {
                let elapsedSilence = timestamp - start
                if elapsedSilence >= longPauseThresholdSeconds {
                    let lastPauseTime = lastEventByType[.longPause] ?? -100.0
                    if timestamp - lastPauseTime >= 6.0 {
                        let event = AcousticEvent(
                            type: .longPause,
                            timestamp: start,
                            duration: elapsedSilence,
                            confidence: 0.96
                        )
                        recordDetectedEvent(event)
                    }
                }
            }
        } else {
            if let start = silenceStartTime {
                finalizeSilenceInterval(from: start, to: timestamp)
                silenceStartTime = nil
            }
        }
    }

    /// Analiza el archivo de audio completo al finalizar la grabación (`SNAudioFileAnalyzer`) cuando el usuario grabó en modo ahorro de batería.
    func analyzeCompleteAudioFileIfNeeded(at fileURL: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            analysisQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                do {
                    let fileAnalyzer = try SNAudioFileAnalyzer(url: fileURL)
                    let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                    request.windowDuration = CMTimeMakeWithSeconds(1.5, preferredTimescale: 48000)
                    request.overlapFactor = 0.35
                    try fileAnalyzer.add(request, withObserver: self)
                    fileAnalyzer.analyze()
                } catch {
                    // Si el archivo es muy corto o falla el clasificador, continúa con los eventos ya registrados
                }
                continuation.resume()
            }
        }
    }

    /// Permite registrar un evento acústico directamente o desde post-procesamiento.
    func recordDetectedEvent(_ event: AcousticEvent) {
        let lastTime = lastEventByType[event.type] ?? -100.0
        // Evitar duplicados consecutivos del mismo evento en menos de 6.0 segundos
        guard (event.timestamp - lastTime) >= 6.0 else { return }

        lastEventByType[event.type] = event.timestamp
        detectedEvents.append(event)

        DispatchQueue.main.async { [weak self] in
            self?.onAcousticEventDetected?(event)
            self?.onLiveStatusChanged?(
                "\(event.type.emoji) \(event.type.spanishTitle) detectado (\(Int(event.confidence * 100))%)",
                event.type
            )
        }
    }

    private func finalizeSilenceInterval(from start: TimeInterval, to end: TimeInterval) {
        let duration = end - start
        guard duration >= skippableSilenceThresholdSeconds else { return }
        let interval = SilenceInterval(startTime: start, endTime: end)
        silenceIntervals.append(interval)

        if duration >= longPauseThresholdSeconds {
            let lastPauseTime = lastEventByType[.longPause] ?? -100.0
            if start - lastPauseTime >= 6.0 {
                let event = AcousticEvent(
                    type: .longPause,
                    timestamp: start,
                    duration: duration,
                    confidence: 0.95
                )
                recordDetectedEvent(event)
            }
        }
    }

    // MARK: - SNResultsObserving (Apple SoundAnalysis Framework)

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }
        let timestampSeconds = CMTimeGetSeconds(classificationResult.timeRange.start)
        let durationSeconds = max(0.8, CMTimeGetSeconds(classificationResult.timeRange.duration))

        for classification in classificationResult.classifications.prefix(3) {
            guard classification.confidence >= 0.62 else { continue }
            if let mappedType = mapAppleSoundIdentifier(classification.identifier) {
                let event = AcousticEvent(
                    type: mappedType,
                    timestamp: max(0, timestampSeconds),
                    duration: durationSeconds,
                    confidence: Double(classification.confidence)
                )
                recordDetectedEvent(event)
                break
            }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}

    func requestDidComplete(_ request: SNRequest) {}

    private func mapAppleSoundIdentifier(_ identifier: String) -> AcousticEventType? {
        let normalized = identifier.lowercased()

        if normalized.contains("laughter") ||
           normalized.contains("giggle") ||
           normalized.contains("snicker") ||
           normalized.contains("chuckle") ||
           normalized.contains("belly_laugh") ||
           normalized.contains("cackle") {
            return .laughter
        }

        if normalized.contains("applause") ||
           normalized.contains("clapping") ||
           normalized.contains("cheering") ||
           normalized.contains("finger_snapping") {
            return .applause
        }

        if normalized.contains("music") ||
           normalized.contains("singing") ||
           normalized.contains("musical_instrument") ||
           normalized.contains("guitar") ||
           normalized.contains("piano") ||
           normalized.contains("drum") ||
           normalized.contains("orchestra") ||
           normalized.contains("synthesizer") {
            return .music
        }

        if normalized.contains("sigh") ||
           normalized.contains("gasp") ||
           normalized.contains("yawn") ||
           normalized.contains("pant") {
            return .sigh
        }

        if normalized.contains("cough") ||
           normalized.contains("throat_clearing") ||
           normalized.contains("sneeze") {
            return .cough
        }

        return nil
    }
}
