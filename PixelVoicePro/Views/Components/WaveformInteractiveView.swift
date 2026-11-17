import SwiftUI

/// Visualizador de Línea de Tiempo con Zoom Gestual tipo CapCut (`MagnificationGesture` + `ScrollView(.horizontal)`)
/// virtualizado en bloques de 4s para soportar clases universitarias de varias horas a 60 FPS sin límite de textura Metal.
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
    var expandVertically: Bool = false
    var minCanvasHeight: CGFloat = 132

    @State private var showSpectrumMode: Bool = false
    /// Escala en puntos por segundo (zoom estilo CapCut: de 12 pt/s a 80 pt/s)
    @State private var pointsPerSecond: CGFloat = 28.0
    @State private var basePointsPerSecond: CGFloat = 28.0
    @State private var followLivePlayhead: Bool = true

    private let tileDuration: TimeInterval = 4.0

    private var effectiveDuration: TimeInterval {
        max(8.0, elapsedTime + 2.0)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Controles limpios: solo íconos de lupa [-] [+], botón rápido Seguir y selector Onda/FFT
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Button {
                        let newScale = max(12.0, pointsPerSecond - 12.0)
                        pointsPerSecond = newScale
                        basePointsPerSecond = newScale
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.caption.weight(.bold))
                            .frame(width: 30, height: 30)
                            .liquidGlassCircle()
                    }
                    .buttonStyle(.plain)

                    Button {
                        let newScale = min(80.0, pointsPerSecond + 12.0)
                        pointsPerSecond = newScale
                        basePointsPerSecond = newScale
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.caption.weight(.bold))
                            .frame(width: 30, height: 30)
                            .liquidGlassCircle()
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 4)

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        followLivePlayhead = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: followLivePlayhead ? "scope" : "location.fill")
                        Text(followLivePlayhead ? L10n.waveformFollowing : L10n.waveformFollow)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .liquidGlassCapsule(
                        tint: followLivePlayhead ? PixelTheme.accentBlue.opacity(0.28) : PixelTheme.recordRed.opacity(0.85)
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
                        Text(showSpectrumMode ? L10n.waveformWave : L10n.waveformFFT)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .liquidGlassCapsule()
                }
                .buttonStyle(.plain)
            }

            ZStack {
                if showSpectrumMode {
                    GeometryReader { specGeo in
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(Array(spectrumBands.enumerated()), id: \.offset) { _, bandLevel in
                                let clamped = CGFloat(max(0.06, min(1.0, bandLevel)))
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(activeSpeakerColor)
                                    .frame(height: max(10, clamped * max(max(44, minCanvasHeight - 40), specGeo.size.height - 28)))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                } else {
                    GeometryReader { outerGeo in
                        let height = max(minCanvasHeight, outerGeo.size.height)
                        let tileCount = max(2, Int(ceil(effectiveDuration / tileDuration)))
                        let playheadTileIdx = min(tileCount - 1, max(0, Int(elapsedTime / tileDuration)))

                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 0) {
                                    ForEach(0..<tileCount, id: \.self) { tileIdx in
                                        let tileStart = Double(tileIdx) * tileDuration
                                        let tileEnd = tileStart + tileDuration
                                        LiveWaveformTileView(
                                            tileStart: tileStart,
                                            tileEnd: tileEnd,
                                            tileHeight: height,
                                            pointsPerSecond: pointsPerSecond,
                                            elapsedTime: elapsedTime,
                                            timelineSamples: timelineSamples,
                                            turnsInWindow: liveSpeakerTurns.filter { $0.timestamp >= tileStart - 1.5 && $0.timestamp < tileEnd + 0.5 },
                                            allTurns: liveSpeakerTurns,
                                            eventsInWindow: liveEvents.filter { $0.timestamp >= tileStart - 0.5 && $0.timestamp < tileEnd + 0.5 },
                                            bookmarksInWindow: liveBookmarks.filter { $0.timestamp >= tileStart - 0.5 && $0.timestamp < tileEnd + 0.5 },
                                            speakers: speakers,
                                            fallbackSpeakerColor: activeSpeakerColor
                                        )
                                        .id("LIVE_TILE_\(tileIdx)")
                                    }
                                }
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
                            .onChange(of: Int(elapsedTime)) { _, _ in
                                if followLivePlayhead {
                                    withAnimation(.linear(duration: 0.2)) {
                                        proxy.scrollTo("LIVE_TILE_\(playheadTileIdx)", anchor: .trailing)
                                    }
                                }
                            }
                            .onChange(of: followLivePlayhead) { _, isFollowing in
                                if isFollowing {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        proxy.scrollTo("LIVE_TILE_\(playheadTileIdx)", anchor: .trailing)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: minCanvasHeight, maxHeight: expandVertically ? .infinity : 164)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Bloque virtualizado de 4 segundos para la cabina en vivo (`LazyHStack`).
private struct LiveWaveformTileView: View {
    let tileStart: TimeInterval
    let tileEnd: TimeInterval
    let tileHeight: CGFloat
    let pointsPerSecond: CGFloat
    let elapsedTime: TimeInterval
    let timelineSamples: [Float]
    let turnsInWindow: [SpeakerTurnMarker]
    let allTurns: [SpeakerTurnMarker]
    let eventsInWindow: [AcousticEvent]
    let bookmarksInWindow: [RecordingBookmark]
    let speakers: [SpeakerProfile]
    let fallbackSpeakerColor: Color

    private var tileWidth: CGFloat {
        CGFloat(tileEnd - tileStart) * pointsPerSecond
    }

    private var tickStepSeconds: Int {
        if pointsPerSecond >= 55 { return 1 }
        if pointsPerSecond >= 24 { return 2 }
        return 4
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. Canvas de barras de onda con color sólido asignado al locutor
            Canvas { context, size in
                let midY = (size.height + 36.0) / 2.0
                let maxBarHalfHeight = max(18.0, (size.height - 48.0) / 2.0)
                let barStep = max(2.2, pointsPerSecond / 10.0)
                let barWidth = max(1.8, min(5.0, barStep * 0.68))

                var centerLine = Path()
                centerLine.move(to: CGPoint(x: 0, y: midY))
                centerLine.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(
                    centerLine,
                    with: .color(.secondary.opacity(0.18)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )

                let startIdx = max(0, Int(floor(tileStart * 10.0)))
                let endIdx = min(timelineSamples.count, Int(ceil(tileEnd * 10.0)))

                if endIdx > startIdx {
                    for idx in startIdx..<endIdx {
                        let sec = Double(idx) * 0.1
                        let localX = CGFloat(sec - tileStart) * pointsPerSecond
                        let amp = timelineSamples[idx]
                        let halfH = max(2.5, CGFloat(amp) * maxBarHalfHeight)
                        let rect = CGRect(
                            x: localX - barWidth / 2.0,
                            y: midY - halfH,
                            width: barWidth,
                            height: halfH * 2.0
                        )
                        let speakerColor = resolveSpeakerColorFast(at: sec)
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: barWidth / 2.0),
                            with: .color(speakerColor)
                        )
                    }
                }

                // Dibujar cabezal rojo si cae dentro de este bloque de 4s
                if elapsedTime >= tileStart && elapsedTime < tileEnd {
                    let playheadX = CGFloat(elapsedTime - tileStart) * pointsPerSecond
                    let headRect = CGRect(x: playheadX - 1.2, y: 16, width: 2.4, height: size.height - 20)
                    context.fill(Path(headRect), with: .color(PixelTheme.recordRed))
                }
            }
            .frame(width: tileWidth, height: tileHeight)

            // 2. Regla de tiempo dentro del bloque
            let firstTick = Int(ceil(tileStart / Double(tickStepSeconds))) * tickStepSeconds
            let lastTick = Int(floor((tileEnd - 0.01) / Double(tickStepSeconds))) * tickStepSeconds
            if lastTick >= firstTick {
                ForEach(Array(stride(from: firstTick, through: lastTick, by: tickStepSeconds)), id: \.self) { sec in
                    let x = CGFloat(Double(sec) - tileStart) * pointsPerSecond
                    HStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 1, height: 7)
                        Text(ExactDateFormatter.standardDuration(TimeInterval(sec)))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .offset(x: x, y: 3)
                }
            }

            // 3. Insignias compactas de locutores (L1, L2, L3...) solo de este bloque
            ForEach(turnsInWindow.filter { $0.timestamp >= tileStart && $0.timestamp < tileEnd }) { turn in
                let spk = speakers.first(where: { $0.id == turn.speakerId }) ?? SpeakerProfile.createDefault(number: 1)
                let x = CGFloat(turn.timestamp - tileStart) * pointsPerSecond
                Text(spk.shortBadgeCode)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(spk.color.opacity(0.24), in: Capsule())
                    .foregroundStyle(spk.color)
                    .fixedSize()
                    .offset(x: max(2, x), y: 18)
            }

            // 4. Eventos acústicos (emojis) dentro de este bloque
            ForEach(eventsInWindow.filter { $0.timestamp >= tileStart && $0.timestamp < tileEnd }) { event in
                let x = CGFloat(event.timestamp - tileStart) * pointsPerSecond
                Text(event.type.emoji)
                    .font(.system(size: 11))
                    .padding(3)
                    .background(event.type.color.opacity(0.25), in: Circle())
                    .offset(x: max(2, x), y: 36)
            }

            // 5. Marcadores dentro de este bloque
            ForEach(bookmarksInWindow.filter { $0.timestamp >= tileStart && $0.timestamp < tileEnd }) { bm in
                let x = CGFloat(bm.timestamp - tileStart) * pointsPerSecond
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 10, weight: .bold))
                    .padding(4)
                    .background(PixelTheme.bookmarkAmber.opacity(0.24), in: Circle())
                    .foregroundStyle(PixelTheme.bookmarkAmber)
                    .offset(x: max(2, x), y: 36)
            }
        }
        .frame(width: tileWidth, height: tileHeight, alignment: .topLeading)
    }

    private func resolveSpeakerColorFast(at second: TimeInterval) -> Color {
        var low = 0
        var high = allTurns.count - 1
        var matchedIdx = -1
        while low <= high {
            let mid = (low + high) / 2
            if allTurns[mid].timestamp <= second + 0.08 {
                matchedIdx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard matchedIdx >= 0 else {
            return fallbackSpeakerColor
        }
        let spkId = allTurns[matchedIdx].speakerId
        return speakers.first(where: { $0.id == spkId })?.color ?? fallbackSpeakerColor
    }
}

/// Línea de tiempo interactiva con Zoom Gestual tipo CapCut (`MagnificationGesture` + `ScrollView(.horizontal)`)
/// virtualizada en bloques de 4s y con diseño sin bordes para el reproductor a pantalla completa (Vista 3).
struct InteractiveTimelineWaveformView: View {
    let recording: VoiceRecording
    let currentTime: TimeInterval
    let duration: TimeInterval
    let searchHits: [LocalWordSearchHit]
    let onSeek: (TimeInterval) -> Void
    var isFullScreenExpanded: Bool = true
    var minWaveformHeight: CGFloat = 120

    @State private var pointsPerSecond: CGFloat = 24.0
    @State private var basePointsPerSecond: CGFloat = 24.0
    @State private var followPlayhead: Bool = true

    private let tileDuration: TimeInterval = 4.0

    private var safeDuration: TimeInterval {
        max(1.0, duration)
    }

    var body: some View {
        let samples = recording.waveformSamples.isEmpty
            ? Array(repeating: Float(0.35), count: 140)
            : recording.waveformSamples
        let segments = recording.segments
        let events = recording.acousticEvents
        let bookmarks = recording.bookmarks
        let speakers = recording.speakers
        let tileCount = max(1, Int(ceil(safeDuration / tileDuration)))
        let playheadTileIdx = min(tileCount - 1, max(0, Int(currentTime / tileDuration)))

        VStack(spacing: 10) {
            // Controles minimalistas: únicamente íconos de lupa [-] [+], sin textos redundantes
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        let next = max(10.0, pointsPerSecond - 12.0)
                        pointsPerSecond = next
                        basePointsPerSecond = next
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .liquidGlassCircle()
                    }
                    .buttonStyle(.plain)

                    Button {
                        let next = min(85.0, pointsPerSecond + 12.0)
                        pointsPerSecond = next
                        basePointsPerSecond = next
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .liquidGlassCircle()
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        followPlayhead = true
                    }
                } label: {
                    Image(systemName: followPlayhead ? "scope" : "location.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                        .liquidGlassCircle(
                            tint: followPlayhead ? PixelTheme.accentBlue.opacity(0.28) : PixelTheme.accentBlue.opacity(0.85)
                        )
                        .foregroundStyle(followPlayhead ? PixelTheme.accentBlue : .white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)

            // Contenedor desplazable horizontalmente a todo lo ancho (sin caja gris)
            GeometryReader { outerGeo in
                let height = max(minWaveformHeight, outerGeo.size.height)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(0..<tileCount, id: \.self) { tileIdx in
                                let tileStart = Double(tileIdx) * tileDuration
                                let tileEnd = min(safeDuration, tileStart + tileDuration)
                                PlaybackWaveformTileView(
                                    tileStart: tileStart,
                                    tileEnd: max(tileStart + 0.25, tileEnd),
                                    tileHeight: height,
                                    safeDuration: safeDuration,
                                    currentTime: currentTime,
                                    pointsPerSecond: pointsPerSecond,
                                    samples: samples,
                                    segmentsInWindow: segments.filter { $0.endTime >= tileStart && $0.startTime <= tileEnd },
                                    eventsInWindow: events.filter { ($0.timestamp + max(0.6, $0.duration)) >= tileStart && $0.timestamp <= tileEnd },
                                    bookmarksInWindow: bookmarks.filter { $0.timestamp >= tileStart && $0.timestamp <= tileEnd },
                                    hitsInWindow: searchHits.filter { $0.timestamp >= tileStart && $0.timestamp <= tileEnd },
                                    speakers: speakers,
                                    onSeek: onSeek
                                )
                                .id("PLAYBACK_TILE_\(tileIdx)")
                            }
                        }
                    }
                    .SimultaneousPinchZoom(
                        pointsPerSecond: $pointsPerSecond,
                        basePointsPerSecond: $basePointsPerSecond,
                        minScale: 10.0,
                        maxScale: 85.0
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { _ in
                                if followPlayhead {
                                    followPlayhead = false
                                }
                            }
                    )
                    .onChange(of: Int(currentTime)) { _, _ in
                        if followPlayhead {
                            withAnimation(.linear(duration: 0.2)) {
                                proxy.scrollTo("PLAYBACK_TILE_\(playheadTileIdx)", anchor: .center)
                            }
                        }
                    }
                    .onChange(of: followPlayhead) { _, isFollowing in
                        if isFollowing {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                proxy.scrollTo("PLAYBACK_TILE_\(playheadTileIdx)", anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 130, maxHeight: isFullScreenExpanded ? .infinity : 160)
        }
    }
}

/// Bloque virtualizado de reproducción de 4s para eliminar sobrecarga de Metal en audios largos.
private struct PlaybackWaveformTileView: View {
    let tileStart: TimeInterval
    let tileEnd: TimeInterval
    let tileHeight: CGFloat
    let safeDuration: TimeInterval
    let currentTime: TimeInterval
    let pointsPerSecond: CGFloat
    let samples: [Float]
    let segmentsInWindow: [TranscriptSegment]
    let eventsInWindow: [AcousticEvent]
    let bookmarksInWindow: [RecordingBookmark]
    let hitsInWindow: [LocalWordSearchHit]
    let speakers: [SpeakerProfile]
    let onSeek: (TimeInterval) -> Void

    private var tileWidth: CGFloat {
        max(16, CGFloat(tileEnd - tileStart) * pointsPerSecond)
    }

    private var tickStepSeconds: Int {
        if pointsPerSecond >= 55 { return 1 }
        if pointsPerSecond >= 24 { return 2 }
        return 4
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. Onda de audio edge-to-edge con colores sólidos de locutor
            Canvas { context, size in
                let waveTop: CGFloat = 46.0
                let waveHeight = max(28.0, size.height - waveTop - 6.0)
                let midY = waveTop + waveHeight / 2.0

                // Franjas tenues de eventos acústicos dentro del bloque
                for event in eventsInWindow {
                    let startX = CGFloat(max(0, event.timestamp - tileStart)) * pointsPerSecond
                    let evWidth = max(6.0, CGFloat(event.duration) * pointsPerSecond)
                    let evRect = CGRect(x: startX, y: waveTop, width: evWidth, height: waveHeight)
                    context.fill(Path(roundedRect: evRect, cornerRadius: 4), with: .color(event.type.color.opacity(0.14)))
                }

                let barSpacing: CGFloat = 4.0
                let barCount = max(4, Int(tileWidth / barSpacing))
                let actualStep = tileWidth / CGFloat(barCount)
                let barWidth = max(1.8, actualStep * 0.62)

                for barIdx in 0..<barCount {
                    let localX = (CGFloat(barIdx) + 0.5) * actualStep
                    let barTime = tileStart + TimeInterval(localX / max(1.0, pointsPerSecond))
                    let sampleRatio = min(1.0, max(0.0, barTime / max(1.0, safeDuration)))
                    let sampleIdx = min(samples.count - 1, max(0, Int(sampleRatio * Double(samples.count))))
                    let amp = samples[sampleIdx]
                    let isPlayed = barTime <= currentTime
                    let barColor = resolveBarColor(at: barTime, isPlayed: isPlayed)
                    let barH = max(4.0, CGFloat(amp) * (waveHeight - 6.0))
                    let rect = CGRect(
                        x: localX - barWidth / 2.0,
                        y: midY - barH / 2.0,
                        width: barWidth,
                        height: barH
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2.0), with: .color(barColor))
                }

                // Cabezal vertical nítido si cae dentro de este bloque
                if currentTime >= tileStart && currentTime <= tileEnd {
                    let playheadX = CGFloat(currentTime - tileStart) * pointsPerSecond
                    let headRect = CGRect(x: playheadX - 1.3, y: 12, width: 2.6, height: size.height - 14)
                    context.fill(Path(headRect), with: .color(.primary))
                }
            }
            .frame(width: tileWidth, height: tileHeight)
            .contentShape(Rectangle())
            .onTapGesture { location in
                let tapped = tileStart + TimeInterval(location.x / max(1.0, pointsPerSecond))
                onSeek(max(0, min(safeDuration, tapped)))
            }

            // 2. Regla de tiempo superior
            let firstTick = Int(ceil(tileStart / Double(tickStepSeconds))) * tickStepSeconds
            let lastTick = Int(floor((tileEnd - 0.01) / Double(tickStepSeconds))) * tickStepSeconds
            if lastTick >= firstTick {
                ForEach(Array(stride(from: firstTick, through: lastTick, by: tickStepSeconds)), id: \.self) { sec in
                    let x = CGFloat(Double(sec) - tileStart) * pointsPerSecond
                    HStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 1, height: 7)
                        Text(ExactDateFormatter.standardDuration(TimeInterval(sec)))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .offset(x: x, y: 2)
                }
            }

            // 3. Insignias compactas L1, L2, L3... interactivas
            ForEach(segmentsInWindow.filter { $0.startTime >= tileStart && $0.startTime < tileEnd }) { seg in
                let spk = speakers.first(where: { $0.id == seg.speakerId }) ?? SpeakerProfile.createDefault(number: 1)
                let x = CGFloat(seg.startTime - tileStart) * pointsPerSecond
                Button {
                    onSeek(seg.startTime)
                } label: {
                    Text(spk.shortBadgeCode)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(spk.color.opacity(0.24), in: Capsule())
                        .foregroundStyle(spk.color)
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .offset(x: max(2, x), y: 16)
            }

            // 4. Eventos acústicos (emojis) dentro de este bloque
            ForEach(eventsInWindow.filter { $0.timestamp >= tileStart && $0.timestamp < tileEnd }) { event in
                let x = CGFloat(event.timestamp - tileStart) * pointsPerSecond
                Button {
                    onSeek(event.timestamp)
                } label: {
                    Text(event.type.emoji)
                        .font(.system(size: 11))
                        .padding(3)
                        .background(event.type.color.opacity(0.26), in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: max(2, x), y: 31)
            }

            // 5. Marcadores
            ForEach(bookmarksInWindow) { bookmark in
                let x = CGFloat(bookmark.timestamp - tileStart) * pointsPerSecond
                Button {
                    onSeek(bookmark.timestamp)
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(4)
                        .background(PixelTheme.bookmarkAmber.opacity(0.24), in: Circle())
                        .foregroundStyle(PixelTheme.bookmarkAmber)
                }
                .buttonStyle(.plain)
                .offset(x: max(2, x), y: 31)
            }

            // 6. Puntos de búsqueda
            ForEach(hitsInWindow) { hit in
                let x = CGFloat(hit.timestamp - tileStart) * pointsPerSecond
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 8, height: 8)
                    .offset(x: max(2, x), y: 34)
            }
        }
        .frame(width: tileWidth, height: tileHeight, alignment: .topLeading)
    }

    private func resolveBarColor(at timestamp: TimeInterval, isPlayed: Bool) -> Color {
        if hitsInWindow.contains(where: { abs($0.timestamp - timestamp) < 0.35 }) {
            return .yellow
        }
        if let event = eventsInWindow.first(where: {
            timestamp >= $0.timestamp && timestamp <= ($0.timestamp + max(0.6, $0.duration))
        }) {
            return isPlayed ? event.type.color : event.type.color.opacity(0.50)
        }
        if let segment = segmentsInWindow.first(where: {
            timestamp >= $0.startTime && timestamp <= $0.endTime
        }) {
            let speakerColor = speakers.first(where: { $0.id == segment.speakerId })?.color ?? PixelTheme.accentBlue
            return isPlayed ? speakerColor : speakerColor.opacity(0.32)
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
