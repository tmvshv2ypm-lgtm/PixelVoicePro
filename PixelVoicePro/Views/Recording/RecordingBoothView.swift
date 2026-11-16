import SwiftUI

/// Vista 2 (Cabina de Grabación en Vivo):
/// Diseño con ancho estrictamente bloqueado al dispositivo (`GeometryReader`), onda/espectrograma a 60 FPS,
/// cronómetro con milisegundos (`HH:MM:SS.cc`), hora exacta `DD/MM/YYYY - HH:MM:SS AM/PM`,
/// barra de locutores/eventos con scroll horizontal, caja de transcripción en vivo con altura acotada y auto-scroll (`ScrollViewReader`),
/// y botones inferiores responsivos que nunca desbordan los márgenes de la pantalla.
struct RecordingBoothView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var recorderService: AudioRecorderService

    @State private var customDraftTitle: String = ""
    @State private var selectedDraftTags: [TagItem] = []
    @State private var quickBookmarkNote: String = ""
    @State private var showBookmarkAddedToast: Bool = false
    @State private var lastAddedBookmarkText: String = ""
    @State private var recordingErrorMessage: String?

    private var activeSpeakerProfile: SpeakerProfile {
        recorderService.liveSpeakers.first(where: { $0.id == recorderService.activeSpeakerId })
            ?? SpeakerProfile.createDefault(number: 1)
    }

    /// Clave reactiva que cambia cada vez que entra una nueva palabra o evento en vivo para disparar el auto-scroll al final.
    private var liveTranscriptScrollTrigger: String {
        let segCount = recorderService.liveSegments.count
        let lastText = recorderService.liveSegments.last?.text ?? ""
        let eventCount = recorderService.liveAcousticEvents.count
        return "\(segCount)-\(lastText.count)-\(eventCount)"
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let safeScreenWidth = max(320.0, geo.size.width)
                let contentWidth = safeScreenWidth - 32.0

                VStack(spacing: 12) {
                    // 1. Cabecera con Fecha y Hora Exacta de Inicio (DD/MM/YYYY - HH:MM:SS AM/PM)
                    topExactMetadataBanner(contentWidth: contentWidth)

                    // 2. Cronómetro de Alta Precisión con Milisegundos (HH:MM:SS.cc) + Detector Visual de Eventos
                    chronometerAndLiveDetectorSection(contentWidth: contentWidth)

                    // 3. Visualizador de Onda / Espectrograma en Tiempo Real a 60 FPS
                    LiveBoothWaveformView(
                        waveformSamples: recorderService.liveWaveformWindow,
                        spectrumBands: recorderService.liveSpectrumBands,
                        isRecording: recorderService.state == .recording,
                        activeSpeakerColor: activeSpeakerProfile.color
                    )
                    .frame(width: contentWidth)

                    // 4. Barra de Locutores en Vivo y Eventos Acústicos con Scroll Horizontal Estricto
                    liveSpeakersAndAcousticQuickBar(contentWidth: contentWidth)

                    // 5. Caja de Transcripción en Vivo con Altura Fija/Acotada y Auto-Scroll (ScrollViewReader)
                    liveScrollingTranscriptPreview(contentWidth: contentWidth)

                    Spacer(minLength: 2)

                    // 6. Controles Inferiores Responsivos (Marcador en Vivo, Pausar/Reanudar y Finalizar)
                    bottomRecordingControls(contentWidth: contentWidth)
                }
                .padding(.vertical, 6)
                .frame(width: safeScreenWidth, height: geo.size.height, alignment: .top)
                .clipped()
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            }
            .navigationTitle("Cabina PixelVoice Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        Task {
                            _ = await recorderService.stopAndFinalizeRecording()
                            dismiss()
                        }
                    }
                    .foregroundStyle(.red)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(PixelTheme.successEmerald)
                            .frame(width: 7, height: 7)
                        Text("2º Plano Activo")
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PixelTheme.successEmerald.opacity(0.15), in: Capsule())
                    .foregroundStyle(PixelTheme.successEmerald)
                }
            }
            .task {
                await beginRecordingAutomatically()
            }
        }
    }

    // MARK: - 1. Cabecera con Fecha y Hora Exacta de Inicio

    private func topExactMetadataBanner(contentWidth: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.checkmark.fill")
                    .font(.caption)
                    .foregroundStyle(PixelTheme.accentBlue)

                Text(
                    ExactDateFormatter.fullExactTimestamp(
                        from: recorderService.recordingStartDate ?? Date()
                    )
                )
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                Spacer(minLength: 4)

                Text("\(recorderService.selectedFormat.shortBadge) · \(Int(recorderService.selectedSampleRate.rawValue / 1000))kHz")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }

            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Título opcional en vivo (ej. Clase de IA, Entrevista)...", text: $customDraftTitle)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(width: contentWidth)
    }

    // MARK: - 2. Cronómetro con Milisegundos y Detector Visual en Vivo

    private func chronometerAndLiveDetectorSection(contentWidth: CGFloat) -> some View {
        VStack(spacing: 6) {
            Text(ExactDateFormatter.preciseChronometer(recorderService.elapsedTime, alwaysShowHours: true))
                .font(.system(size: 38, weight: .heavy, design: .monospaced))
                .foregroundStyle(recorderService.state == .paused ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())

            HStack(spacing: 8) {
                Circle()
                    .fill(
                        recorderService.liveDetectedEventType?.color
                            ?? (recorderService.state == .recording ? activeSpeakerProfile.color : .secondary)
                    )
                    .frame(width: 9, height: 9)

                Text(recorderService.liveDetectorBanner)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                Text(String(format: "%.0f dB", recorderService.currentDecibels))
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                Capsule()
                    .strokeBorder(activeSpeakerProfile.color.opacity(0.45), lineWidth: 1)
            )
        }
        .frame(width: contentWidth)
    }

    // MARK: - 4. Fila de Chips de Locutores y Eventos con Scroll Horizontal Estricto

    private func liveSpeakersAndAcousticQuickBar(contentWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Locutor:")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                ForEach(1...3, id: \.self) { num in
                    let spkId = "speaker_\(num)"
                    let isCurrent = recorderService.activeSpeakerId == spkId
                    let label = recorderService.liveSpeakers.first(where: { $0.id == spkId })?.displayName ?? "Locutor \(num)"
                    let color = Color(hex: PixelTheme.colorHex(forSpeakerIndex: num - 1))

                    Button {
                        recorderService.switchActiveSpeakerManually(toNumber: num)
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isCurrent ? .white : color)
                                .frame(width: 6, height: 6)
                            Text(label)
                                .lineLimit(1)
                        }
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .foregroundStyle(isCurrent ? .white : color)
                        .background(
                            Capsule().fill(isCurrent ? color : color.opacity(0.14))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Divider().frame(height: 16)

                ForEach([AcousticEventType.laughter, .applause, .music, .longPause]) { eventType in
                    Button {
                        recorderService.triggerAcousticEventMarker(eventType)
                    } label: {
                        Text("\(eventType.emoji) \(eventType.spanishTitle)")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(eventType.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(eventType.color)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(width: contentWidth)
    }

    // MARK: - 5. Caja de Transcripción en Vivo con Altura Acotada y Auto-Scroll

    private func liveScrollingTranscriptPreview(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Transcripción en Vivo (Español)", systemImage: "captions.bubble.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PixelTheme.accentBlue)
                    .lineLimit(1)

                Spacer()

                if !recorderService.liveBookmarks.isEmpty {
                    Label("\(recorderService.liveBookmarks.count) marcador(es)", systemImage: "bookmark.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PixelTheme.bookmarkAmber)
                        .lineLimit(1)
                }
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let errorMessage = recordingErrorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(10)
                        } else if recorderService.liveSegments.isEmpty && recorderService.liveAcousticEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Habla al micrófono del iPhone...")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("Las palabras aparecerán aquí en tiempo real con auto-scroll automático hacia la última línea hablada.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(recorderService.liveSegments) { segment in
                                let speaker = recorderService.liveSpeakers.first(where: { $0.id == segment.speakerId })
                                    ?? SpeakerProfile.createDefault(number: 1)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(speaker.displayName)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(speaker.color)
                                            .lineLimit(1)

                                        Text(ExactDateFormatter.standardDuration(segment.startTime))
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }

                                    if !segment.text.isEmpty {
                                        Text(segment.text)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    // Eventos acústicos con scroll horizontal para no ensanchar jamás la vista
                                    if !segment.inlineEvents.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 6) {
                                                ForEach(segment.inlineEvents) { ev in
                                                    Text(ev.formattedInlineTag)
                                                        .font(.caption2.weight(.bold))
                                                        .lineLimit(1)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 3)
                                                        .background(ev.type.color.opacity(0.18), in: Capsule())
                                                        .foregroundStyle(ev.type.color)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                )
                                .id(segment.id)
                            }
                        }

                        // Ancla invisible al final para el auto-scroll suave mientras hablas
                        Color.clear
                            .frame(height: 1)
                            .id("LIVE_TRANSCRIPT_BOTTOM_ANCHOR")
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: contentWidth)
                .frame(minHeight: 130, maxHeight: 175)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .clipped()
                .onChange(of: liveTranscriptScrollTrigger) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("LIVE_TRANSCRIPT_BOTTOM_ANCHOR", anchor: .bottom)
                    }
                }
            }
        }
        .frame(width: contentWidth)
    }

    // MARK: - 6. Controles Inferiores Responsivos

    private func bottomRecordingControls(contentWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            if showBookmarkAddedToast {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(PixelTheme.bookmarkAmber)
                    Text(lastAddedBookmarkText)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(PixelTheme.bookmarkAmber.opacity(0.16), in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Fila de Marcador Rápido en Vivo
            HStack(spacing: 8) {
                TextField("Nota opcional para el marcador...", text: $quickBookmarkNote)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))

                Button {
                    let bm = recorderService.addLiveBookmark(
                        customLabel: quickBookmarkNote.isEmpty ? nil : quickBookmarkNote,
                        note: quickBookmarkNote
                    )
                    quickBookmarkNote = ""
                    lastAddedBookmarkText = "Marcador guardado en \(bm.formattedTimestamp)"
                    withAnimation {
                        showBookmarkAddedToast = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation {
                            showBookmarkAddedToast = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark.fill")
                        Text("Marcador")
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(PixelTheme.bookmarkAmber, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .frame(width: contentWidth)

            // Botones principales de Pausar/Reanudar y Finalizar y Guardar
            HStack(spacing: 12) {
                Button {
                    if recorderService.state == .recording {
                        recorderService.pauseRecording()
                    } else if recorderService.state == .paused {
                        try? recorderService.resumeRecording()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: recorderService.state == .paused ? "play.fill" : "pause.fill")
                        Text(recorderService.state == .paused ? "Reanudar" : "Pausar")
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        if let completedRecording = await recorderService.stopAndFinalizeRecording(
                            customTitle: customDraftTitle.isEmpty ? nil : customDraftTitle,
                            initialTags: selectedDraftTags
                        ) {
                            viewModel.insertNewRecording(completedRecording, presentQuickTitleEditor: true)
                        }
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.circle.fill")
                            .font(.body)
                        Text("Finalizar y Guardar")
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 10)
                    .background(
                        LinearGradient(
                            colors: [PixelTheme.accentBlue, PixelTheme.accentIndigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: PixelTheme.accentBlue.opacity(0.35), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }
            .frame(width: contentWidth)
        }
        .frame(width: contentWidth)
    }

    private func beginRecordingAutomatically() async {
        guard recorderService.state == .idle else { return }
        do {
            try await recorderService.startRecording(in: RecordingStorageService.recordingsDirectoryURL)
            recordingErrorMessage = nil
        } catch {
            recordingErrorMessage = error.localizedDescription
        }
    }
}
