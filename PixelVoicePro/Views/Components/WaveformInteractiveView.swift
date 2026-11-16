import SwiftUI

/// Visualizador de onda y espectro de frecuencias en vivo a 60 FPS para la Cabina de Grabación (Vista 2).
struct LiveBoothWaveformView: View {
    let waveformSamples: [Float]
    let spectrumBands: [Float]
    let isRecording: Bool
    let activeSpeakerColor: Color

    @State private var showSpectrumMode: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(
                    showSpectrumMode ? "Espectrograma FFT (28 Bandas)" : "Onda de Voz en Tiempo Real (60 FPS)",
                    systemImage: showSpectrumMode ? "chart.bar.xaxis" : "waveform.path.ecg"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        showSpectrumMode.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showSpectrumMode ? "waveform" : "slider.vertical.3")
                        Text(showSpectrumMode ? "Ver Onda" : "Ver Espectro")
                    }
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(activeSpeakerColor.opacity(0.28), lineWidth: 1)
                    )

                if showSpectrumMode {
                    // Analizador de espectro de frecuencias en tiempo real
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array(spectrumBands.enumerated()), id: \.offset) { index, bandLevel in
                            let clamped = CGFloat(max(0.06, min(1.0, bandLevel)))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            PixelTheme.accentCyan,
                                            activeSpeakerColor,
                                            PixelTheme.accentIndigo
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: max(8, clamped * 116))
                                .animation(.linear(duration: 0.016), value: bandLevel)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                } else {
                    // Gráfica de onda fluida a 60 FPS con línea central de referencia
                    GeometryReader { geo in
                        let width = geo.size.width
                        let height = geo.size.height
                        let midY = height / 2.0
                        let count = max(1, waveformSamples.count)
                        let spacing: CGFloat = 2.0
                        let barWidth = max(2.0, (width - CGFloat(count) * spacing) / CGFloat(count))

                        ZStack {
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: midY))
                                path.addLine(to: CGPoint(x: width, y: midY))
                            }
                            .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                            HStack(alignment: .center, spacing: spacing) {
                                ForEach(Array(waveformSamples.enumerated()), id: \.offset) { idx, level in
                                    let isRecent = idx >= count - 6
                                    let barHeight = max(4.0, CGFloat(level) * (height - 18.0))
                                    Capsule()
                                        .fill(
                                            isRecent && isRecording
                                                ? PixelTheme.recordRed
                                                : activeSpeakerColor.opacity(0.85)
                                        )
                                        .frame(width: barWidth, height: barHeight)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            .frame(height: 138)
        }
    }
}

/// Línea de tiempo de onda interactiva para la Vista de Detalle y Reproducción (Vista 3).
/// Pinta colores por locutor, eventos acústicos (`[😂 Risas]`, `[🎵 Música]`, `[⏸️ Pausa]`), marcadores (`🔖`)
/// y resalta todas las ocurrencias de la palabra buscada localmente.
struct InteractiveTimelineWaveformView: View {
    let recording: VoiceRecording
    let currentTime: TimeInterval
    let duration: TimeInterval
    let searchHits: [LocalWordSearchHit]
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging: Bool = false
    @State private var dragTime: TimeInterval = 0.0

    private var effectiveTime: TimeInterval {
        isDragging ? dragTime : currentTime
    }

    private var progressRatio: Double {
        guard duration > 0 else { return 0 }
        return min(1.0, max(0.0, effectiveTime / duration))
    }

    var body: some View {
        let samples = recording.waveformSamples.isEmpty
            ? Array(repeating: Float(0.35), count: 120)
            : recording.waveformSamples

        VStack(spacing: 6) {
            // Capa superior de pines de Eventos Acústicos, Marcadores y Búsqueda Local
            GeometryReader { geo in
                let totalWidth = max(1, geo.size.width)
                let safeDuration = max(0.1, duration)

                ZStack(alignment: .leading) {
                    // Pines de Eventos Acústicos (Risas, Música, Aplausos, Pausas)
                    ForEach(recording.acousticEvents) { event in
                        let ratio = min(0.98, max(0.02, event.timestamp / safeDuration))
                        Button {
                            onSeek(event.timestamp)
                        } label: {
                            Text(event.type.emoji)
                                .font(.system(size: 11))
                                .padding(3)
                                .background(event.type.color.opacity(0.25), in: Circle())
                                .overlay(Circle().stroke(event.type.color, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .position(x: totalWidth * ratio, y: 11)
                    }

                    // Banderines de Marcadores en Vivo (Bookmarks)
                    ForEach(recording.bookmarks) { bookmark in
                        let ratio = min(0.98, max(0.02, bookmark.timestamp / safeDuration))
                        Button {
                            onSeek(bookmark.timestamp)
                        } label: {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(PixelTheme.bookmarkAmber)
                        }
                        .buttonStyle(.plain)
                        .position(x: totalWidth * ratio, y: 11)
                    }

                    // Pines luminosos de coincidencias de búsqueda local
                    ForEach(searchHits) { hit in
                        let ratio = min(0.98, max(0.02, hit.timestamp / safeDuration))
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 8, height: 8)
                            .shadow(color: .yellow, radius: 3)
                            .position(x: totalWidth * ratio, y: 11)
                    }
                }
            }
            .frame(height: 22)

            // Onda interactiva con soporte de arrastre táctil (Scrubbing)
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let height = geo.size.height
                let count = max(1, samples.count)
                let spacing: CGFloat = 1.6
                let barWidth = max(1.5, (width - CGFloat(count) * spacing) / CGFloat(count))
                let safeDuration = max(0.1, duration)

                ZStack(alignment: .leading) {
                    // Sombras de fondo para los eventos acústicos en la línea de tiempo
                    ForEach(recording.acousticEvents) { event in
                        let startX = width * CGFloat(min(1.0, max(0.0, event.timestamp / safeDuration)))
                        let eventWidth = max(6.0, width * CGFloat(min(1.0, event.duration / safeDuration)))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(event.type.color.opacity(0.18))
                            .frame(width: eventWidth, height: height)
                            .offset(x: startX)
                    }

                    // Barras de la onda coloreadas por el locutor activo en cada instante
                    HStack(alignment: .center, spacing: spacing) {
                        ForEach(Array(samples.enumerated()), id: \.offset) { index, amp in
                            let barRatio = Double(index) / Double(count)
                            let barTimestamp = barRatio * safeDuration
                            let isPlayed = barRatio <= progressRatio
                            let barColor = resolveBarColor(at: barTimestamp, isPlayed: isPlayed)
                            let barHeight = max(5.0, CGFloat(amp) * (height - 8.0))

                            Capsule()
                                .fill(barColor)
                                .frame(width: barWidth, height: barHeight)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Cabezal de reproducción (Playhead)
                    let playheadX = width * CGFloat(progressRatio)
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 2.5, height: height + 6)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .offset(x: min(width - 2.5, max(0, playheadX)))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let ratio = min(1.0, max(0.0, value.location.x / width))
                            dragTime = Double(ratio) * safeDuration
                        }
                        .onEnded { value in
                            let ratio = min(1.0, max(0.0, value.location.x / width))
                            let targetTime = Double(ratio) * safeDuration
                            isDragging = false
                            onSeek(targetTime)
                        }
                )
            }
            .frame(height: 62)
        }
    }

    private func resolveBarColor(at timestamp: TimeInterval, isPlayed: Bool) -> Color {
        // Si coincide con una búsqueda local, resaltar en amarillo intenso
        if searchHits.contains(where: { abs($0.timestamp - timestamp) < 0.35 }) {
            return .yellow
        }

        // Si coincide con un evento acústico, resaltar con el color del evento
        if let event = recording.acousticEvents.first(where: {
            timestamp >= $0.timestamp && timestamp <= ($0.timestamp + max(0.6, $0.duration))
        }) {
            return isPlayed ? event.type.color : event.type.color.opacity(0.55)
        }

        // Color del locutor activo en ese segmento
        if let segment = recording.segments.first(where: {
            timestamp >= $0.startTime && timestamp <= $0.endTime
        }) {
            let speakerColor = recording.speakerProfile(for: segment.speakerId).color
            return isPlayed ? speakerColor : speakerColor.opacity(0.35)
        }

        return isPlayed ? PixelTheme.accentBlue : Color.secondary.opacity(0.28)
    }
}

/// Mini vista previa de onda para las tarjetas del listado principal (Dashboard).
struct CompactCardWaveformPreview: View {
    let samples: [Float]
    let events: [AcousticEvent]
    let duration: TimeInterval

    var body: some View {
        let displaySamples = sliceSamples(samples, count: 44)
        GeometryReader { geo in
            let height = geo.size.height
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(displaySamples.enumerated()), id: \.offset) { idx, level in
                    let t = (Double(idx) / Double(max(1, displaySamples.count))) * max(1.0, duration)
                    let eventMatch = events.first { abs($0.timestamp - t) < 0.7 }
                    let barColor = eventMatch?.type.color ?? PixelTheme.accentBlue.opacity(0.75)

                    Capsule()
                        .fill(barColor)
                        .frame(height: max(4, CGFloat(level) * height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 26)
    }

    private func sliceSamples(_ input: [Float], count: Int) -> [Float] {
        guard !input.isEmpty else {
            return (0..<count).map { Float(0.2 + 0.5 * abs(sin(Double($0) * 0.4))) }
        }
        if input.count <= count { return input }
        let step = Double(input.count) / Double(count)
        return (0..<count).map { idx in
            input[min(input.count - 1, Int(Double(idx) * step))]
        }
    }
}
