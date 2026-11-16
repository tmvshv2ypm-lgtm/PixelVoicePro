import SwiftUI

/// Vista 2 (Cabina de Grabación en Vivo optimizada para Clases Universitarias Largas):
/// Incluye Línea de Tiempo con Zoom Gestual tipo CapCut (`LiveBoothWaveformView`),
/// Transcripción en Vivo Plegable (oculta por defecto para máximo ahorro de RAM y batería),
/// sincronización con Pantalla Bloqueada (`LiveActivityManager`) y Pantalla de Post-Procesamiento por fragmentos de 45s.
struct RecordingBoothView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var recorderService: AudioRecorderService

    @State private var selectedDraftTags: [TagItem] = []
    @State private var quickBookmarkNote: String = ""
    @State private var showBookmarkAddedToast: Bool = false
    @State private var lastAddedBookmarkText: String = ""
    @State private var recordingErrorMessage: String?

    private var activeSpeakerProfile: SpeakerProfile {
        recorderService.liveSpeakers.first(where: { $0.id == recorderService.activeSpeakerId })
            ?? SpeakerProfile.createDefault(number: 1)
    }

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

                ZStack {
                    VStack(spacing: 10) {
                        // 1. Cabecera con Fecha y Hora Exacta de Inicio (DD/MM/YYYY - HH:MM:SS AM/PM)
                        topExactMetadataBanner(contentWidth: contentWidth)

                        // 2. Cronómetro de Alta Precisión con Milisegundos (HH:MM:SS.cc) + Detector Visual de Eventos
                        chronometerAndLiveDetectorSection(contentWidth: contentWidth)

                        // 3. Línea de Tiempo con Zoom Gestual tipo CapCut (Pinch-to-Zoom + "Seguir en vivo")
                        LiveBoothWaveformView(
                            waveformSamples: recorderService.liveWaveformWindow,
                            timelineSamples: recorderService.liveTimelineSamples,
                            spectrumBands: recorderService.liveSpectrumBands,
                            elapsedTime: recorderService.elapsedTime,
                            isRecording: recorderService.state == .recording,
                            activeSpeakerColor: activeSpeakerProfile.color,
                            liveEvents: recorderService.liveAcousticEvents,
                            liveBookmarks: recorderService.liveBookmarks,
                            liveSpeakerTurns: recorderService.liveSpeakerTurns,
                            speakers: recorderService.liveSpeakers
                        )
                        .frame(width: contentWidth)

                        // 4. Barra de Locutores en Vivo y Eventos Acústicos con Scroll Horizontal Estricto
                        liveSpeakersAndAcousticQuickBar(contentWidth: contentWidth)

                        // 5. Sección de Transcripción en Vivo Plegable (Ahorro de RAM y Batería para Clases Largas)
                        collapsibleLiveTranscriptionSection(contentWidth: contentWidth)

                        Spacer(minLength: 2)

                        // 6. Controles Inferiores Responsivos (Marcador en Vivo, Pausar/Reanudar y Finalizar)
                        bottomRecordingControls(contentWidth: contentWidth)
                    }
                    .padding(.vertical, 6)
                    .frame(width: safeScreenWidth, height: geo.size.height, alignment: .top)
                    .clipped()
                    .disabled(recorderService.state == .finalizing)

                    // 7. Pantalla Superpuesta de Post-Procesamiento Completo (Fragmentos de 45s) al Finalizar
                    if recorderService.state == .finalizing {
                        postProcessingProgressOverlay(contentWidth: contentWidth)
                    }
                }
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            }
            .navigationTitle("Cabina PixelVoice Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        Task {
                            _ = await recorderService.stopAndFinalizeRecording(performFullPostProcessing: false)
                            dismiss()
                        }
                    }
                    .foregroundStyle(.red)
                    .disabled(recorderService.state == .finalizing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(PixelTheme.recordRed)
                            .frame(width: 7, height: 7)
                        Text("Lock Screen Live")
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PixelTheme.recordRed.opacity(0.14), in: Capsule())
                    .foregroundStyle(PixelTheme.recordRed)
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
                TextField("Título de la clase/nota (se muestra en pantalla bloqueada)...", text: $recorderService.liveCustomDraftTitle)
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
        VStack(spacing: 5) {
            Text(ExactDateFormatter.preciseChronometer(recorderService.elapsedTime, alwaysShowHours: true))
                .font(.system(size: 36, weight: .heavy, design: .monospaced))
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

    // MARK: - 5. Transcripción en Vivo Plegable (Ahorro de RAM y Batería por Defecto)

    private func collapsibleLiveTranscriptionSection(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Botón/Interruptor para desplegar u ocultar la transcripción en vivo
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        recorderService.setLiveTranscriptionEnabled(!recorderService.isLiveTranscriptionEnabled)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(
                            systemName: recorderService.isLiveTranscriptionEnabled
                                ? "eye.fill"
                                : "bolt.shield.fill"
                        )
                        .foregroundStyle(
                            recorderService.isLiveTranscriptionEnabled
                                ? PixelTheme.accentBlue
                                : PixelTheme.successEmerald
                        )

                        Text(
                            recorderService.isLiveTranscriptionEnabled
                                ? "Ocultar transcripción en vivo (Ahorrar batería)"
                                : "Ver transcripción en vivo"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                        Spacer(minLength: 4)

                        Image(systemName: recorderService.isLiveTranscriptionEnabled ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if !recorderService.liveBookmarks.isEmpty {
                    Label("\(recorderService.liveBookmarks.count)", systemImage: "bookmark.fill")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(PixelTheme.bookmarkAmber.opacity(0.16), in: Capsule())
                        .foregroundStyle(PixelTheme.bookmarkAmber)
                }
            }

            if recorderService.isLiveTranscriptionEnabled {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let errorMessage = recordingErrorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(10)
                            } else if recorderService.liveSegments.isEmpty && recorderService.liveAcousticEvents.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Escuchando en español...")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(PixelTheme.accentBlue)
                                    Text("Las palabras aparecerán aquí en vivo. Puedes ocultar este panel en cualquier momento para ahorrar batería durante una clase larga.")
                                        .font(.caption2)
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

                            Color.clear
                                .frame(height: 1)
                                .id("LIVE_TRANSCRIPT_BOTTOM_ANCHOR")
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: contentWidth)
                    .frame(height: 145)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .clipped()
                    .onChange(of: liveTranscriptScrollTrigger) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("LIVE_TRANSCRIPT_BOTTOM_ANCHOR", anchor: .bottom)
                        }
                    }
                }
            } else {
                // Tarjeta compacta de modo ahorro de RAM y batería para clases de varias horas
                HStack(spacing: 10) {
                    Image(systemName: "battery.100percent.bolt")
                        .font(.title3)
                        .foregroundStyle(PixelTheme.successEmerald)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Modo Ahorro para Clases Largas Activo")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Grabando audio ligero con mínimo uso de RAM y batería. Al finalizar se procesará el 100% de la transcripción, locutores y eventos en bloques de 45s.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding(10)
                .frame(width: contentWidth, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(PixelTheme.successEmerald.opacity(0.09))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(PixelTheme.successEmerald.opacity(0.3), lineWidth: 1)
                )
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
                            customTitle: recorderService.liveCustomDraftTitle.isEmpty ? nil : recorderService.liveCustomDraftTitle,
                            initialTags: selectedDraftTags,
                            performFullPostProcessing: true
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

    // MARK: - 7. Pantalla de Progreso de Post-Procesamiento Completo (Fragmentos de 45s)

    private func postProcessingProgressOverlay(contentWidth: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.35)
                    .tint(PixelTheme.accentBlue)

                Text("Procesando Grabación Completa")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(recorderService.postProcessingStatusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                VStack(spacing: 6) {
                    ProgressView(value: recorderService.postProcessingProgress, total: 1.0)
                        .tint(PixelTheme.accentBlue)

                    Text("\(Int(recorderService.postProcessingProgress * 100))% completado")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(PixelTheme.accentBlue)
                }

                Text("Separando locutores (Locutor 1, 2, 3...), detectando eventos acústicos y transcribiendo en bloques seguros de 45s.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(22)
            .frame(width: min(340, contentWidth))
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
        }
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
