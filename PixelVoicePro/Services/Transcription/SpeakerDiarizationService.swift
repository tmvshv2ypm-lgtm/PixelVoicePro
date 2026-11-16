import Foundation
import AVFoundation
import Accelerate

/// Vector de características acústicas extraídas de la voz en tiempo real mediante `Accelerate` (`vDSP`).
struct VocalFeatureVector: Sendable {
    let timestamp: TimeInterval
    let pitchHz: Double
    let spectralCentroidHz: Double
    let rmsEnergy: Float
    let zeroCrossingRate: Double
}

/// Motor de Identificación y Separación de Locutores (Speaker Diarization) basado en análisis acústico DSP (`vDSP`).
/// Detecta cambios de timbre y frecuencia fundamental ($F_0$) entre hablantes y los agrupa como Locutor 1, Locutor 2, etc.
final class SpeakerDiarizationService {
    private struct SpeakerCluster {
        var profile: SpeakerProfile
        var meanPitchHz: Double
        var meanCentroidHz: Double
        var sampleCount: Int
        var lastActiveTimestamp: TimeInterval
    }

    private var clusters: [SpeakerCluster] = []
    private(set) var currentSpeakerId: String = "speaker_1"
    private(set) var currentPitchHz: Double = 0.0
    private var lastSpeakerSwitchTime: TimeInterval = 0.0
    private var lastSpeechActiveTime: TimeInterval = 0.0

    /// Historial cronológico de asignaciones (timestamp -> speakerId) para alinear palabras de Speech/Whisper.
    private var timelineAssignments: [(timestamp: TimeInterval, speakerId: String)] = []

    /// Umbral mínimo de energía RMS para considerar que hay voz activa
    private let voiceActivityThreshold: Float = 0.014
    /// Tiempo mínimo entre cambios automáticos de locutor para evitar falsos positivos en entonaciones
    private let minimumTurnDuration: TimeInterval = 1.65
    /// Máximo número de locutores detectables automáticamente por sesión
    private let maxSpeakers: Int = 6

    init() {
        reset()
    }

    func reset() {
        let initialSpeaker = SpeakerProfile.createDefault(number: 1, pitchHz: 140.0, centroidHz: 1600.0)
        clusters = [
            SpeakerCluster(
                profile: initialSpeaker,
                meanPitchHz: 140.0,
                meanCentroidHz: 1600.0,
                sampleCount: 1,
                lastActiveTimestamp: 0.0
            )
        ]
        currentSpeakerId = initialSpeaker.id
        currentPitchHz = 0.0
        lastSpeakerSwitchTime = 0.0
        lastSpeechActiveTime = 0.0
        timelineAssignments = [(0.0, initialSpeaker.id)]
    }

    /// Devuelve todos los perfiles de locutores detectados hasta el momento.
    var detectedSpeakers: [SpeakerProfile] {
        clusters.map(\.profile)
    }

    /// Permite al usuario o al sistema forzar manualmente el cambio o creación de un locutor durante una entrevista en vivo.
    @discardableResult
    func selectOrCreateSpeaker(number: Int, at timestamp: TimeInterval) -> SpeakerProfile {
        let targetId = "speaker_\(number)"
        if let index = clusters.firstIndex(where: { $0.profile.id == targetId }) {
            currentSpeakerId = targetId
            clusters[index].lastActiveTimestamp = timestamp
            lastSpeakerSwitchTime = timestamp
            timelineAssignments.append((timestamp, targetId))
            return clusters[index].profile
        } else {
            let defaultPitch = 125.0 + Double(number * 28)
            let defaultCentroid = 1450.0 + Double(number * 220)
            let newProfile = SpeakerProfile.createDefault(
                number: number,
                pitchHz: defaultPitch,
                centroidHz: defaultCentroid
            )
            let newCluster = SpeakerCluster(
                profile: newProfile,
                meanPitchHz: defaultPitch,
                meanCentroidHz: defaultCentroid,
                sampleCount: 1,
                lastActiveTimestamp: timestamp
            )
            clusters.append(newCluster)
            currentSpeakerId = newProfile.id
            lastSpeakerSwitchTime = timestamp
            timelineAssignments.append((timestamp, newProfile.id))
            return newProfile
        }
    }

    /// Procesa un buffer de audio PCM en tiempo real, extrae el pitch fundamental ($F_0$) y el centroide espectral,
    /// y determina qué locutor está hablando en el instante `timestamp`.
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, at timestamp: TimeInterval) -> (speakerId: String, pitchHz: Double, isVoiceActive: Bool) {
        guard let channelData = buffer.floatChannelData?[0] else {
            return (currentSpeakerId, currentPitchHz, false)
        }
        let frameLength = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        guard frameLength >= 512, sampleRate > 0 else {
            return (currentSpeakerId, currentPitchHz, false)
        }

        // 1. Calcular energía RMS con vDSP
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))

        guard rms >= voiceActivityThreshold else {
            currentPitchHz = 0.0
            return (currentSpeakerId, 0.0, false)
        }

        // 2. Estimar Frecuencia Fundamental (Pitch F0) mediante autocorrelación acotada (75 Hz - 350 Hz)
        let estimatedPitch = estimateFundamentalFrequency(
            samples: channelData,
            frameCount: min(frameLength, 2048),
            sampleRate: sampleRate
        )

        // 3. Estimar Centroide Espectral y Tasa de Cruces por Cero (ZCR) para el timbre vocal
        let zcr = computeZeroCrossingRate(samples: channelData, frameCount: frameLength, sampleRate: sampleRate)
        let spectralCentroid = max(600.0, min(3800.0, (estimatedPitch * 6.5) + (zcr * 0.45)))

        guard estimatedPitch >= 75.0 && estimatedPitch <= 360.0 else {
            // Sonido no periódico o consonante fricativa: mantener el locutor actual
            lastSpeechActiveTime = timestamp
            return (currentSpeakerId, currentPitchHz, true)
        }

        currentPitchHz = estimatedPitch
        let pauseBeforeSpeech = timestamp - lastSpeechActiveTime
        lastSpeechActiveTime = timestamp

        let feature = VocalFeatureVector(
            timestamp: timestamp,
            pitchHz: estimatedPitch,
            spectralCentroidHz: spectralCentroid,
            rmsEnergy: rms,
            zeroCrossingRate: zcr
        )

        let assignedId = assignSpeakerCluster(for: feature, pauseDurationBeforeFrame: pauseBeforeSpeech)
        return (assignedId, estimatedPitch, true)
    }

    /// Devuelve el `speakerId` activo para cualquier instante de tiempo dado.
    func speakerId(at timestamp: TimeInterval) -> String {
        guard !timelineAssignments.isEmpty else { return "speaker_1" }
        var matched = timelineAssignments[0].speakerId
        for entry in timelineAssignments {
            if entry.timestamp <= timestamp + 0.15 {
                matched = entry.speakerId
            } else {
                break
            }
        }
        return matched
    }

    // MARK: - Algoritmo de Clustering Online con Histéresis Acústica

    private func assignSpeakerCluster(for feature: VocalFeatureVector, pauseDurationBeforeFrame: TimeInterval) -> String {
        if clusters.isEmpty {
            reset()
        }

        // Si el primer cluster apenas se inicializó con valores por defecto, calibrarlo con la primera voz real
        if clusters.count == 1 && clusters[0].sampleCount <= 2 {
            clusters[0].meanPitchHz = feature.pitchHz
            clusters[0].meanCentroidHz = feature.spectralCentroidHz
            clusters[0].profile.pitchMeanHz = feature.pitchHz
            clusters[0].profile.spectralCentroidHz = feature.spectralCentroidHz
            clusters[0].sampleCount += 1
            clusters[0].lastActiveTimestamp = feature.timestamp
            return clusters[0].profile.id
        }

        // Calcular distancia acústica ponderada a cada locutor conocido
        var bestClusterIndex = 0
        var smallestDistance = Double.greatestFiniteMagnitude

        for (index, cluster) in clusters.enumerated() {
            let pitchDiffNormalized = abs(feature.pitchHz - cluster.meanPitchHz) / 38.0
            let centroidDiffNormalized = abs(feature.spectralCentroidHz - cluster.meanCentroidHz) / 420.0
            let distance = sqrt((pitchDiffNormalized * pitchDiffNormalized * 0.72) + (centroidDiffNormalized * centroidDiffNormalized * 0.28))

            if distance < smallestDistance {
                smallestDistance = distance
                bestClusterIndex = index
            }
        }

        // Umbral adaptativo: si hubo una pausa > 0.55s es más probable que otro interlocutor haya tomado la palabra
        let newSpeakerDistanceThreshold: Double = pauseDurationBeforeFrame > 0.55 ? 1.15 : 1.48
        let canSwitchTurn = (feature.timestamp - lastSpeakerSwitchTime) >= minimumTurnDuration || pauseDurationBeforeFrame > 0.65

        if smallestDistance > newSpeakerDistanceThreshold && canSwitchTurn && clusters.count < maxSpeakers {
            // Crear un nuevo Locutor (Locutor 2, Locutor 3, etc.)
            let newSpeakerNumber = clusters.count + 1
            let newProfile = SpeakerProfile.createDefault(
                number: newSpeakerNumber,
                pitchHz: feature.pitchHz,
                centroidHz: feature.spectralCentroidHz
            )
            let newCluster = SpeakerCluster(
                profile: newProfile,
                meanPitchHz: feature.pitchHz,
                meanCentroidHz: feature.spectralCentroidHz,
                sampleCount: 1,
                lastActiveTimestamp: feature.timestamp
            )
            clusters.append(newCluster)
            currentSpeakerId = newProfile.id
            lastSpeakerSwitchTime = feature.timestamp
            timelineAssignments.append((feature.timestamp, newProfile.id))
            return newProfile.id
        } else {
            let matchedId = clusters[bestClusterIndex].profile.id
            if matchedId != currentSpeakerId && canSwitchTurn {
                currentSpeakerId = matchedId
                lastSpeakerSwitchTime = feature.timestamp
                timelineAssignments.append((feature.timestamp, matchedId))
            }

            // Actualizar centroide del cluster activo con media móvil exponencial suave
            if let activeIndex = clusters.firstIndex(where: { $0.profile.id == currentSpeakerId }) {
                let alpha = 0.12
                clusters[activeIndex].meanPitchHz = (1.0 - alpha) * clusters[activeIndex].meanPitchHz + alpha * feature.pitchHz
                clusters[activeIndex].meanCentroidHz = (1.0 - alpha) * clusters[activeIndex].meanCentroidHz + alpha * feature.spectralCentroidHz
                clusters[activeIndex].profile.pitchMeanHz = clusters[activeIndex].meanPitchHz
                clusters[activeIndex].profile.spectralCentroidHz = clusters[activeIndex].meanCentroidHz
                clusters[activeIndex].sampleCount += 1
                clusters[activeIndex].lastActiveTimestamp = feature.timestamp
            }
            return currentSpeakerId
        }
    }

    // MARK: - Consolidación de Segmentos por Locutor y Eventos Acústicos

    /// Agrupa una secuencia de palabras con timestamps en párrafos separados automáticamente por locutor
    /// e incrusta los eventos acústicos (`[😂 Risas - 02:14]`, `[🎵 Música]`, etc.) en el punto temporal correspondiente.
    func buildSpeakerSegments(
        words: [WordTimestamp],
        acousticEvents: [AcousticEvent],
         pauseSplitThreshold: TimeInterval = 2.0
    ) -> [TranscriptSegment] {
        guard !words.isEmpty else {
            if acousticEvents.isEmpty { return [] }
            // Si aún no hay palabras pero sí se detectaron eventos acústicos (ej. música o risas al inicio)
            return [
                TranscriptSegment(
                    speakerId: currentSpeakerId,
                    startTime: acousticEvents.first?.timestamp ?? 0,
                    endTime: (acousticEvents.last?.timestamp ?? 0) + (acousticEvents.last?.duration ?? 1.5),
                    text: "",
                    words: [],
                    inlineEvents: acousticEvents
                )
            ]
        }

        var segments: [TranscriptSegment] = []
        var currentWords: [WordTimestamp] = []
        var activeSpeaker = words[0].speakerId

        for word in words {
            if let lastWord = currentWords.last {
                let gap = word.startTime - lastWord.endTime
                let speakerChanged = (word.speakerId != activeSpeaker)
                let longPauseBreak = (gap >= pauseSplitThreshold && currentWords.count >= 6)

                if speakerChanged || longPauseBreak {
                    let segment = makeSegment(from: currentWords, speakerId: activeSpeaker)
                    segments.append(segment)
                    currentWords = [word]
                    activeSpeaker = word.speakerId
                } else {
                    currentWords.append(word)
                }
            } else {
                currentWords.append(word)
                activeSpeaker = word.speakerId
            }
        }

        if !currentWords.isEmpty {
            segments.append(makeSegment(from: currentWords, speakerId: activeSpeaker))
        }

        // Insertar los eventos acústicos en el segmento más cercano en el tiempo
        for event in acousticEvents.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let matchingIdx = segments.firstIndex(where: {
                event.timestamp >= ($0.startTime - 1.0) && event.timestamp <= ($0.endTime + 1.5)
            }) {
                if !segments[matchingIdx].inlineEvents.contains(where: { $0.id == event.id }) {
                    segments[matchingIdx].inlineEvents.append(event)
                }
            } else if let closestIdx = segments.enumerated().min(by: {
                abs($0.element.startTime - event.timestamp) < abs($1.element.startTime - event.timestamp)
            })?.offset {
                if !segments[closestIdx].inlineEvents.contains(where: { $0.id == event.id }) {
                    segments[closestIdx].inlineEvents.append(event)
                }
            }
        }

        return segments
    }

    private func makeSegment(from words: [WordTimestamp], speakerId: String) -> TranscriptSegment {
        let start = words.first?.startTime ?? 0
        let end = words.last?.endTime ?? start
        let joinedText = words.map(\.word).joined(separator: " ")
        return TranscriptSegment(
            speakerId: speakerId,
            startTime: start,
            endTime: end,
            text: joinedText,
            words: words,
            inlineEvents: []
        )
    }

    // MARK: - Primitivas DSP con Accelerate (vDSP)

    private func estimateFundamentalFrequency(samples: UnsafePointer<Float>, frameCount: Int, sampleRate: Double) -> Double {
        let minLag = max(1, Int(sampleRate / 360.0)) // ~360 Hz máx
        let maxLag = min(frameCount / 2, Int(sampleRate / 75.0)) // ~75 Hz mín
        guard maxLag > minLag else { return 0.0 }

        var zeroLagEnergy: Float = 0.0
        vDSP_dotpr(samples, 1, samples, 1, &zeroLagEnergy, vDSP_Length(frameCount - maxLag))
        guard zeroLagEnergy > 1e-5 else { return 0.0 }

        var bestLag = 0
        var maxCorrelation: Float = 0.0

        for lag in minLag...maxLag {
            var corr: Float = 0.0
            let compareLength = vDSP_Length(frameCount - maxLag)
            vDSP_dotpr(samples, 1, samples.advanced(by: lag), 1, &corr, compareLength)
            let normalizedCorr = corr / zeroLagEnergy
            if normalizedCorr > maxCorrelation {
                maxCorrelation = normalizedCorr
                bestLag = lag
            }
        }

        // Requerir periodicidad mínima clara (voz humana vs ruido blanco)
        guard maxCorrelation >= 0.28, bestLag > 0 else {
            return 0.0
        }
        return sampleRate / Double(bestLag)
    }

    private func computeZeroCrossingRate(samples: UnsafePointer<Float>, frameCount: Int, sampleRate: Double) -> Double {
        guard frameCount > 1 else { return 0.0 }
        var crossings = 0
        for i in 1..<frameCount {
            if (samples[i - 1] >= 0 && samples[i] < 0) || (samples[i - 1] < 0 && samples[i] >= 0) {
                crossings += 1
            }
        }
        let durationSeconds = Double(frameCount) / sampleRate
        return durationSeconds > 0 ? Double(crossings) / durationSeconds : 0.0
    }
}
