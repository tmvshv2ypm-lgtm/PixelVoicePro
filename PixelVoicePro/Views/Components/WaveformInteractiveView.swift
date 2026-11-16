import SwiftUI

/// Visualizador de Línea de Tiempo con Zoom Gestual tipo CapCut (`MagnificationGesture` + `ScrollView(.horizontal)`)
/// y Espectrograma FFT a 60 FPS para la Cabina de Grabación en Vivo (Vista 2).
struct LiveBoothWaveformView: View {
    let waveformSamples: [Float]
    let timelineSamples: [Float]
    let spectrumBands: [Float]
    let elapsedTime: TimeInterval
    let isRecording: Bool
    let activeSpeakerColor: Color
    let liveEvents: [AcousticEvent]
    let liveBookmarks: [RecordingBookmark]
    let liveSpeakerTurns: [SpeakerTurnMarker]
    let speakers: [SpeakerProfile]

    @State private var showSpectrumMode: Bool = false
    /// Escala en puntos por segundo (zoom estilo CapCut: de 14 pt/s a 80 pt/s)
    @State private var pointsPerSecond: CGFloat = 28.0
    @State private var basePointsPerSecond: CGFloat = 28.0
    @State private var followLivePlayhead: Bool = true

    private var effectiveDuration: TimeInterval {
        max(8.0, elapsedTime + 2.0)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Barra de herramientas de la línea de tiempo CapCut: Zoom +/-, "Seguir en vivo" y modo Espectro
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Button {
                        let newScale = max(12.0, pointsPerSecond - 12.0)
                        pointsPerSecond = newScale
                        basePointsPerSecond = newScale
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.caption.weight(.bold))
                            .padding(5)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Text("\(Int(pointsPerSecond))px/s")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 42)

                    Button {
                        let newScale = min(80.0, pointsPerSecond + 12.0)
                        pointsPerSecond = newScale
                        basePointsPerSecond = newScale
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.caption.weight(.bold))
                            .padding(5)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 4)

                // Botón rápido "Seguir en vivo / Centrar cabezal"
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        followLivePlayhead = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: followLivePlayhead ? "scope" : "location.fill")
                        Text(followLivePlayhead ? "Siguiendo" : "Seguir en vivo")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        followLivePlayhead
                            ? PixelTheme.accentBlue.opacity(0.16)
                            : PixelTheme.recordRed,
                        in: Capsule()
                    )
                    .foregroundStyle(followLivePlayhead ? PixelTheme.accentBlue : .white)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        showSpectrumMode.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showSpectrumMode ? "waveform" : "chart.bar.xaxis")
                        Text(showSpectrumMode ? "Onda" : "FFT")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(activeSpeakerColor.opacity(0.28), lineWidth: 1)
                    )

                if showSpectrumMode {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array(spectrumBands.enumerated()), id: \.offset) { _, bandLevel in
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
                                .frame(height: max(8, clamped * 110))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                } else {
                    // Línea de tiempo con Zoom Gestual tipo CapCut (Pinch-to-Zoom + Scroll Horizontal)
                    GeometryReader { outerGeo in
                        let viewportWidth = max(260.0, outerGeo.size.width)
                        let totalCanvasWidth = max(viewportWidth, CGFloat(effectiveDuration) * pointsPerSecond + 80.0)
                        let height = outerGeo.size.height

                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: true) {
                                ZStack(alignment: .topLeading) {
                                    // 1. Regla de tiempo superior estilo CapCut
                                    capCutTimeRuler(totalWidth: totalCanvasWidth, duration: effectiveDuration)

                                    // 2. Carril de indicadores (👤 Locutores, 😂 Eventos, 🔖 Marcadores) separados por el zoom
                                    capCutLiveMarkersTrack(
                                         { sec in CGFloat(sec) * pointsPerSecond }
                                    )
                                    .offset(y: 18)

                                    // 3. Barras de onda indexadas por tiempo real (10 muestras por segundo)
                                    Canvas { context, size in
                                        let midY = (size.height + 34.0) / 2.0
                                        let maxBarHalfHeight = (size.height - 46.0) / 2.0
                                        let barStep = max(2.2, pointsPerSecond / 10.0)
                                        let barWidth = max(1.6, min(5.0, barStep * 0.68))

                                        // Línea central punteada
                                        var centerLine = Path()
                                        centerLine.move(to: CGPoint(x: 0, y: midY))
                                        centerLine.addLine(to: CGPoint(x: size.width, y: midY))
                                        context.stroke(
                                            centerLine,
                                            with: .color(.secondary.opacity(0.2)),
                                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                                        )

                                        for (idx, amp) in timelineSamples.enumerated() {
                                            let sec = Double(idx) * 0.1
                                            let x = CGFloat(sec) * pointsPerSecond
                                            let halfH = max(2.5, CGFloat(amp) * maxBarHalfHeight)
                                            let rect = CGRect(
                                                x: x - barWidth / 2.0,
                                                y: midY - halfH,
                                                width: barWidth,
                                                height: halfH * 2.0
                                            )
                                            let isLatest = sec >= (elapsedTime - 0.35)
                                            let barColor = isLatest && isRecording
                                                ? PixelTheme.recordRed
                                                : resolveLiveSpeakerColor(at: sec)
                                            context.fill(
                                                Path(roundedRect: rect, cornerRadius: barWidth / 2.0),
                                                with: .color(barColor)
                                            )
                                        }

                                        // Cabezal rojo de grabación en vivo (Playhead)
                                        let playheadX = CGFloat(elapsedTime) * pointsPerSecond
                                        let headRect = CGRect(x: playheadX - 1.2, y: 16, width: 2.4, height: size.height - 20)
                                        context.fill(Path(headRect), with: .color(PixelTheme.recordRed))
                                    }
                                    .frame(width: totalCanvasWidth, height: height)

                                    // Ancla móvil posicionada exactamente en el cabezal de grabación actual
                                    HStack(spacing: 0) {
                                        Spacer()
                                            .frame(width: max(0, CGFloat(elapsedTime) * pointsPerSecond))
                                        Color.clear
                                            .frame(width: 24, height: height)
                                            .id("CAPCUT_LIVE_PLAYHEAD")
                                    }
                                }
                                .frame(width: totalCanvasWidth, height: height)
                            }
                            .SimultaneousPinchZoom(
                                pointsPerSecond: $pointsPerSecond,
                                basePointsPerSecond: $basePointsPerSecond,
                                minScale: 12.0,
                                maxScale: 80.0
                            )
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 8)
                                    .onChanged { _ in
                                        if followLivePlayhead {
                                            followLivePlayhead = false
                                        }
                                    }
                            )
                            .onChange(of: Int(elapsedTime * 5)) { _, _ in
                                if followLivePlayhead {
                                    withAnimation(.linear(duration: 0.15)) {
                                        proxy.scrollTo("CAPCUT_LIVE_PLAYHEAD", anchor: .trailing)
                                    }
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .frame(height: 132)
        }
    }

    @ViewBuilder
    private func capCutTimeRuler(totalWidth: CGFloat, duration: TimeInterval) -> some View {
        let tickStepSeconds: Int = {
            if pointsPerSecond >= 55 { return 1 }
            if pointsPerSecond >= 26 { return 2 }
            if pointsPerSecond >= 16 { return 5 }
            return 10
        }()
        let totalTicks = max(1, Int(duration) / tickStepSeconds + 2)

        ZStack(alignment: .topLeading) {
            ForEach(0..<totalTicks, id: \.self) { i in
                let sec = i * tickStepSeconds
                let x = CGFloat(sec) * pointsPerSecond
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 1, height: 8)
                    Text(ExactDateFormatter.standardDuration(TimeInterval(sec)))
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .offset(x: x, y: 3)
            }
        }
        .frame(width: totalWidth, height: 16, alignment: .topLeading)
    }

    @ViewBuilder
    private func capCutLiveMarkersTrack(_ xPosition: @escaping (TimeInterval) -> CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Cambios de locutor (👤 Locutor 1, 2, 3...)
            ForEach(liveSpeakerTurns) { turn in
                let spk = speakers.first(where: { $0.id == turn.speakerId }) ?? SpeakerProfile.createDefault(number: 1)
                HStack(spacing: 2) {
                    Text("👤")
                        .font(.system(size: 8))
                    Text(spk.displayName)
                        .font(.system(size: 8.5, weight: .bold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(spk.color.opacity(0.22), in: Capsule())
                .foregroundStyle(spk.color)
                .offset(x: max(2, xPosition(turn.timestamp)), y: 0)
            }

            // Eventos acústicos (😂 Risas, 🎵 Música, 👏 Aplausos...)
            ForEach(liveEvents) { event in
                Text("\(event.type.emoji) \(event.type.spanishTitle)")
                    .font(.system(size: 8.5, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(event.type.color.opacity(0.24), in: Capsule())
                    .foregroundStyle(event.type.color)
                    .offset(x: max(2, xPosition(event.timestamp)), y: 15)
            }

            // Marcadores en vivo (🔖)
            ForEach(liveBookmarks) { bm in
                HStack(spacing: 2) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 8))
                    Text(bm.label)
                        .font(.system(size: 8, weight: .bold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(PixelTheme.bookmarkAmber.opacity(0.25), in: Capsule())
                .foregroundStyle(PixelTheme.bookmarkAmber)
                .offset(x: max(2, xPosition(bm.timestamp)), y: 15)
            }
        }
    }

    private func resolveLiveSpeakerColor(at second: TimeInterval) -> Color {
        var matchedId = "speaker_1"
        for turn in liveSpeakerTurns {
            if turn.timestamp <= second + 0.1 {
                matchedId = turn.speakerId
            } else {
                break
            }
        }
        return speakers.first(where: { $0.id == matchedId })?.color ?? activeSpeakerColor.opacity(0.85)
    }
}

/// Línea de tiempo interactiva con Zoom Gestual tipo CapCut (`MagnificationGesture` + `ScrollView(.horizontal)`)
/// para el Reproductor de la Vista de Detalle (Vista 3).
struct InteractiveTimelineWaveformView: View {
    let recording: VoiceRecording
    let currentTime: TimeInterval
    let duration: TimeInterval
    let searchHits: [LocalWordSearchHit]
    let onSeek: (TimeInterval) -> Void

    @State private var pointsPerSecond: CGFloat = 24.0
    @State private var basePointsPerSecond: CGFloat = 24.0
    @State private var followPlayhead: Bool = true

    private var safeDuration: TimeInterval {
        max(1.0, duration)
    }

    var body: some View {
        let samples = recording.waveformSamples.isEmpty
            ? Array(repeating: Float(0.35), count: 140)
            : recording.waveformSamples

        VStack(spacing: 6) {
            // Controles de Zoom CapCut y botón "Centrar cabezal"
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Button {
                        let next = max(10.0, pointsPerSecond - 12.0)
                        pointsPerSecond = next
                        basePointsPerSecond = next
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.caption2.weight(.bold))
                            .padding(5)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Text("Zoom \(Int(pointsPerSecond))px/s")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button {
                        let next = min(85.0, pointsPerSecond + 12.0)
                        pointsPerSecond = next
                        basePointsPerSecond = next
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.caption2.weight(.bold))
                            .padding(5)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text("• Pellizca con 2 dedos")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        followPlayhead = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: followPlayhead ? "scope" : "location.fill")
                        Text(followPlayhead ? "Cabezal centrado" : "Centrar cabezal")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        followPlayhead ? PixelTheme.accentBlue.opacity(0.15) : PixelTheme.accentBlue,
                        in: Capsule()
                    )
                    .foregroundStyle(followPlayhead ? PixelTheme.accentBlue : .white)
                }
                .buttonStyle(.plain)
            }

            // Contenedor desplazable horizontalmente con Zoom tipo CapCut
            GeometryReader { outerGeo in
                let viewportWidth = max(260.0, outerGeo.size.width)
                let canvasWidth = max(viewportWidth, CGFloat(safeDuration) * pointsPerSecond)
                let effectivePPS = canvasWidth / CGFloat(safeDuration)
                let height = outerGeo.size.height

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            // 1. Regla de tiempo CapCut arriba
                            playbackTimeRuler(canvasWidth: canvasWidth, effectivePPS: effectivePPS)

                            // 2. Pines interactivos de Locutores (👤), Eventos (😂, 🎵), Marcadores (🔖) y Búsqueda (🔍)
                            ZStack(alignment: .topLeading) {
                                // Segmentos de Locutor
                                ForEach(recording.segments) { seg in
                                    let spk = recording.speakerProfile(for: seg.speakerId)
                                    let x = CGFloat(seg.startTime) * effectivePPS
                                    Button {
                                        onSeek(seg.startTime)
                                    } label: {
                                        HStack(spacing: 2) {
                                            Text("👤")
                                                .font(.system(size: 8))
                                            Text(spk.displayName)
                                                .font(.system(size: 8.5, weight: .bold))
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(spk.color.opacity(0.22), in: Capsule())
                                        .foregroundStyle(spk.color)
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: max(2, x), y: 14)
                                }

                                // Eventos Acústicos (Risas, Música, Aplausos, Pausas)
                                ForEach(recording.acousticEvents) { event in
                                    let x = CGFloat(event.timestamp) * effectivePPS
                                    Button {
                                        onSeek(event.timestamp)
                                    } label: {
                                        HStack(spacing: 2) {
                                            Text(event.type.emoji)
                                                .font(.system(size: 10))
                                            if effectivePPS >= 32 {
                                                Text(event.type.spanishTitle)
                                                    .font(.system(size: 8.5, weight: .bold))
                                            }
                                        }
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(event.type.color.opacity(0.26), in: Capsule())
                                        .overlay(Capsule().stroke(event.type.color, lineWidth: 0.8))
                                        .foregroundStyle(event.type.color)
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: max(2, x), y: 30)
                                }

                                // Marcadores (Bookmarks)
                                ForEach(recording.bookmarks) { bookmark in
                                    let x = CGFloat(bookmark.timestamp) * effectivePPS
                                    Button {
                                        onSeek(bookmark.timestamp)
                                    } label: {
                                        HStack(spacing: 2) {
                                            Image(systemName: "bookmark.fill")
                                                .font(.system(size: 9, weight: .bold))
                                            if effectivePPS >= 36 {
                                                Text(bookmark.label)
                                                    .font(.system(size: 8, weight: .bold))
                                                    .lineLimit(1)
                                            }
                                        }
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(PixelTheme.bookmarkAmber.opacity(0.22), in: Capsule())
                                        .foregroundStyle(PixelTheme.bookmarkAmber)
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: max(2, x), y: 30)
                                }

                                // Coincidencias de búsqueda local
                                ForEach(searchHits) { hit in
                                    let x = CGFloat(hit.timestamp) * effectivePPS
                                    Circle()
                                        .fill(Color.yellow)
                                        .frame(width: 8, height: 8)
                                        .shadow(color: .yellow, radius: 3)
                                        .offset(x: max(2, x), y: 32)
                                }
                            }

                            // 3. Onda de audio dibujada en Canvas de alto rendimiento (soporta cualquier nivel de zoom sin perder fluidez)
                            Canvas { context, size in
                                let waveTop: CGFloat = 46.0
                                let waveHeight = max(24.0, size.height - waveTop - 4.0)
                                let midY = waveTop + waveHeight / 2.0

                                // Sombras de eventos acústicos
                                for event in recording.acousticEvents {
                                    let startX = CGFloat(event.timestamp) * effectivePPS
                                    let evWidth = max(6.0, CGFloat(event.duration) * effectivePPS)
                                    let evRect = CGRect(x: startX, y: waveTop, width: evWidth, height: waveHeight)
                                    context.fill(Path(roundedRect: evRect, cornerRadius: 4), with: .color(event.type.color.opacity(0.16)))
                                }

                                let totalBars = max(samples.count, Int(canvasWidth / 3.8))
                                let spacing: CGFloat = 1.6
                                let barWidth = max(1.6, (canvasWidth - CGFloat(totalBars) * spacing) / CGFloat(max(1, totalBars)))

                                for barIdx in 0..<totalBars {
                                    let ratio = Double(barIdx) / Double(max(1, totalBars))
                                    let sampleIdx = min(samples.count - 1, Int(ratio * Double(samples.count)))
                                    let amp = samples[sampleIdx]
                                    let barTime = ratio * safeDuration
                                    let isPlayed = barTime <= currentTime
                                    let barColor = resolveBarColor(at: barTime, isPlayed: isPlayed)
                                    let barH = max(4.0, CGFloat(amp) * (waveHeight - 4.0))
                                    let x = CGFloat(barIdx) * (barWidth + spacing)
                                    let rect = CGRect(x: x, y: midY - barH / 2.0, width: barWidth, height: barH)
                                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2.0), with: .color(barColor))
                                }

                                // Cabezal de reproducción (Playhead)
                                let playheadX = CGFloat(min(safeDuration, max(0, currentTime))) * effectivePPS
                                let headRect = CGRect(x: playheadX - 1.2, y: 12, width: 2.4, height: size.height - 14)
                                context.fill(Path(headRect), with: .color(.primary))
                            }
                            .frame(width: canvasWidth, height: height)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                let tappedTime = Double(location.x / max(1.0, canvasWidth)) * safeDuration
                                onSeek(max(0, min(safeDuration, tappedTime)))
                            }

                            // Ancla invisible en el cabezal actual para "Centrar cabezal" y seguimiento automático
                            HStack(spacing: 0) {
                                Spacer()
                                    .frame(width: max(0, CGFloat(currentTime) * effectivePPS))
                                Color.clear
                                    .frame(width: 20, height: height)
                                    .id("CAPCUT_PLAYBACK_PLAYHEAD")
                            }
                        }
                        .frame(width: canvasWidth, height: height)
                    }
                    .SimultaneousPinchZoom(
                        pointsPerSecond: $pointsPerSecond,
                        basePointsPerSecond: $basePointsPerSecond,
                        minScale: 10.0,
                        maxScale: 85.0
                    )
                    .onChange(of: Int(currentTime * 4)) { _, _ in
                        if followPlayhead {
                            withAnimation(.linear(duration: 0.18)) {
                                proxy.scrollTo("CAPCUT_PLAYBACK_PLAYHEAD", anchor: .center)
                            }
                        }
                    }
                    .onChange(of: followPlayhead) { _, isFollowing in
                        if isFollowing {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                proxy.scrollTo("CAPCUT_PLAYBACK_PLAYHEAD", anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(height: 98)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func playbackTimeRuler(canvasWidth: CGFloat, effectivePPS: CGFloat) -> some View {
        let stepSec: Int = {
            if effectivePPS >= 55 { return 1 }
            if effectivePPS >= 25 { return 2 }
            if effectivePPS >= 14 { return 5 }
            return 10
        }()
        let tickCount = max(1, Int(safeDuration) / stepSec + 2)

        ZStack(alignment: .topLeading) {
            ForEach(0..<tickCount, id: \.self) { i in
                let sec = i * stepSec
                let x = CGFloat(sec) * effectivePPS
                if x < canvasWidth - 18 {
                    HStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 1, height: 7)
                        Text(ExactDateFormatter.standardDuration(TimeInterval(sec)))
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .offset(x: x, y: 2)
                }
            }
        }
        .frame(width: canvasWidth, height: 12, alignment: .topLeading)
    }

    private func resolveBarColor(at timestamp: TimeInterval, isPlayed: Bool) -> Color {
        if searchHits.contains(where: { abs($0.timestamp - timestamp) < 0.35 }) {
            return .yellow
        }
        if let event = recording.acousticEvents.first(where: {
            timestamp >= $0.timestamp && timestamp <= ($0.timestamp + max(0.6, $0.duration))
        }) {
            return isPlayed ? event.type.color : event.type.color.opacity(0.55)
        }
        if let segment = recording.segments.first(where: {
            timestamp >= $0.startTime && timestamp <= $0.endTime
        }) {
            let speakerColor = recording.speakerProfile(for: segment.speakerId).color
            return isPlayed ? speakerColor : speakerColor.opacity(0.35)
        }
        return isPlayed ? PixelTheme.accentBlue : Color.secondary.opacity(0.28)
    }
}

// MARK: - Modificador de Gesto Pinch-to-Zoom de 2 Dedos estilo CapCut

private extension View {
    func SimultaneousPinchZoom(
        pointsPerSecond: Binding<CGFloat>,
        basePointsPerSecond: Binding<CGFloat>,
        minScale: CGFloat,
        maxScale: CGFloat
    ) -> some View {
        self.simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    let proposed = basePointsPerSecond.wrappedValue * value
                    pointsPerSecond.wrappedValue = min(maxScale, max(minScale, proposed))
                }
                .onEnded { _ in
                    basePointsPerSecond.wrappedValue = pointsPerSecond.wrappedValue
                }
        )
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
