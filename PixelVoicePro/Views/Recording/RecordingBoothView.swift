import SwiftUI

/// Vista 2 (Cabina de Grabación en Vivo):
/// Onda a 60 FPS y espectrograma, cronómetro con milisegundos (`HH:MM:SS.cc`), hora exacta `DD/MM/YYYY - HH:MM:SS AM/PM`,
/// detector visual de voz y eventos acústicos (`SoundAnalysis`), transcripción saliendo en vivo y botón de Marcadores rápidos (Bookmarks).
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                // 1. Cabecera con Fecha y Hora Exacta de Inicio (DD/MM/YYYY - HH:MM:SS AM/PM) + Estado Background
                topExactMetadataBanner

                // 2. Cronómetro de Alta Precisión con Milisegundos (HH:MM:SS.cc) + Detector Visual de Eventos
                chronometerAndLiveDetectorSection

                // 3. Visualizador de Onda / Espectrograma en Tiempo Real a 60 FPS
                LiveBoothWaveformView(
                    waveformSamples: recorderService.liveWaveformWindow,
                    spectrumBands: recorderService.liveSpectrumBands,
                    isRecording: recorderService.state == .recording,
                    activeSpeakerColor: activeSpeakerProfile.color
                )
                .padding(.horizontal, 16)

                // 4. Barra de Locutores en Vivo y Detector de Eventos Acústicos
                liveSpeakersAndAcousticQuickBar

                // 5. Vista Previa de la Transcripción Saliendo en Vivo (con Locutores y Etiquetas de Risas/Eventos)
                liveScrollingTranscriptPreview

                // 6. Controles de Cabina: Botón de Marcador en Vivo (Bookmark), Pausa/Reanudar y Finalizar
                bottomRecordingControls
            }
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
                    }
                    .padding(.horizontal, 9)
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

    // MARK: - Secciones de la Cabina de Grabación

    private var topExactMetadataBanner: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "clock.badge.checkmark.fill")
                    .foregroundStyle(PixelTheme.accentBlue)
                Text(
                    ExactDateFormatter.fullExactTimestamp(
                        from: recorderService.recordingStartDate ?? Date()
                    )
                )
                .font(.system(.caption, design: .monospaced).weight(.bold))

                Spacer()

                Text("\(recorderService.selectedFormat.shortBadge) · \(Int(recorderService.selectedSampleRate.rawValue / 1000))kHz")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
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
        .padding(.horizontal, 16)
    }

    private var chronometerAndLiveDetectorSection: some View {
        VStack(spacing: 8) {
            // Cronómetro preciso con centésimas/milisegundos
            Text(ExactDateFormatter.preciseChronometer(recorderService.elapsedTime, alwaysShowHours: true))
                .font(.system(size: 42, weight: .heavy, design: .monospaced))
                .foregroundStyle(recorderService.state == .paused ? .secondary : .primary)
                .contentTransition(.numericText())

            // Píldora del Detector Visual Sutil (Voz / Locutor / Risas / Música / Silencio)
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

                Spacer(minLength: 4)

                Text(String(format: "%.0f dB", recorderService.currentDecibels))
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                Capsule()
                    .strokeBorder(activeSpeakerProfile.color.opacity(0.45), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    private var liveSpeakersAndAcousticQuickBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Locutor activo:")
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

                    // Botones rápidos de etiquetado acústico en vivo (además de la detección automática de SoundAnalysis)
                    ForEach([AcousticEventType.laughter, .applause, .music, .longPause]) { eventType in
                        Button {
                            recorderService.triggerAcousticEventMarker(eventType)
                        } label: {
                            Text("\(eventType.emoji) \(eventType.spanishTitle)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(eventType.color.opacity(0.15), in: Capsule())
                                .foregroundStyle(eventType.color)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var liveScrollingTranscriptPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Transcripción en Vivo (Español)", systemImage: "captions.bubble.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PixelTheme.accentBlue)

                Spacer()

                if !recorderService.liveBookmarks.isEmpty {
                    Label("\(recorderService.liveBookmarks.count) marcador(es)", systemImage: "bookmark.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PixelTheme.bookmarkAmber)
                }
            }
            .padding(.horizontal, 16)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
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
                                Text("Las palabras aparecerán aquí en tiempo real separadas por Locutor 1, Locutor 2, etc., junto con eventos acústicos como [😂 Risas] o [🎵 Música].")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                        } else {
                            ForEach(recorderService.liveSegments) { segment in
                                let speaker = recorderService.liveSpeakers.first(where: { $0.id == segment.speakerId })
                                    ?? SpeakerProfile.createDefault(number: 1)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(speaker.displayName)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(speaker.color)

                                        Text(ExactDateFormatter.standardDuration(segment.startTime))
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }

                                    if !segment.text.isEmpty {
                                        Text(segment.text)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                    }

                                    if !segment.inlineEvents.isEmpty {
                                        HStack(spacing: 6) {
                                            ForEach(segment.inlineEvents) { ev in
                                                Text(ev.formattedInlineTag)
                                                    .font(.caption2.weight(.bold))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(ev.type.color.opacity(0.18), in: Capsule())
                                                    .foregroundStyle(ev.type.color)
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
                    }
                    .padding(12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .padding(.horizontal, 16)
                .onChange(of: recorderService.liveSegments.count) { _, _ in
                    if let lastId = recorderService.liveSegments.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var bottomRecordingControls: some View {
        VStack(spacing: 10) {
            if showBookmarkAddedToast {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(PixelTheme.bookmarkAmber)
                    Text(lastAddedBookmarkText)
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(PixelTheme.bookmarkAmber.opacity(0.16), in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Campo rápido para añadir Marcador de Tiempo en Vivo con un toque
            HStack(spacing: 8) {
                TextField("Nota opcional para el marcador en vivo...", text: $quickBookmarkNote)
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
                    HStack(spacing: 5) {
                        Image(systemName: "bookmark.fill")
                        Text("Marcador")
                            .fontWeight(.bold)
                    }
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(PixelTheme.bookmarkAmber, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            // Botones principales de Pausa/Reanudar y Finalizar Grabación
            HStack(spacing: 20) {
                Button {
                    if recorderService.state == .recording {
                        recorderService.pauseRecording()
                    } else if recorderService.state == .paused {
                        try? recorderService.resumeRecording()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: recorderService.state == .paused ? "play.fill" : "pause.fill")
                        Text(recorderService.state == .paused ? "Reanudar" : "Pausar")
                            .fontWeight(.bold)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
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
                    HStack(spacing: 8) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                        Text("Finalizar y Guardar")
                            .fontWeight(.bold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
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
            .padding(.horizontal, 16)
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
