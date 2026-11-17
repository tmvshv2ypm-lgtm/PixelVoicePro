import Foundation
import SwiftUI
import SwiftData
import UIKit

/// Grupo cronológico exacto por día (DD/MM/YYYY) ordenado de la grabación más reciente a la más antigua.
struct ChronologicalDayGroup: Identifiable {
    let id: String // DD/MM/YYYY
    let headerTitle: String // Ej: "Domingo, 15/11/2026"
    let date: Date
    let recordings: [VoiceRecording]
}

/// Destino de navegación para abrir una grabación (opcionalmente saltando a un segundo exacto desde el Buscador Global).
struct RecordingNavigationTarget: Identifiable, Hashable {
    let id = UUID()
    let recordingId: UUID
    let initialSeekTimestamp: TimeInterval?
    let highlightKeyword: String?
}

/// Destino de navegación para abrir una carpeta cuadrada Liquid Glass en el Home de Voice Notes.
enum FolderDestination: Identifiable, Hashable {
    case all
    case favorites
    case tag(TagItem)

    var id: String {
        switch self {
        case .all: return "folder_all"
        case .favorites: return "folder_favorites"
        case .tag(let tag): return "folder_tag_\(tag.id)"
        }
    }

    var title: String {
        switch self {
        case .all: return L10n.folderAll
        case .favorites: return L10n.folderFavorites
        case .tag(let tag): return tag.localizedName
        }
    }

    var iconName: String {
        switch self {
        case .all: return "tray.full.fill"
        case .favorites: return "star.fill"
        case .tag(let tag): return tag.iconName
        }
    }

    var color: Color {
        switch self {
        case .all: return PixelTheme.accentBlue
        case .favorites: return PixelTheme.bookmarkAmber
        case .tag(let tag): return tag.color
        }
    }

    var associatedTag: TagItem? {
        if case .tag(let tag) = self { return tag }
        return nil
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var recordings: [VoiceRecording] = []
    @Published var globalSearchQuery: String = ""
    @Published var selectedTagFilter: TagItem?
    @Published var filterFavoritesOnly: Bool = false
    @Published var filterDayPeriod: DayPeriod?

    @Published var availableTags: [TagItem] = TagItem.predefinedTags
    @Published var hiddenDefaultTagIDs: Set<String> = []
    @Published var isShowingRecordingBooth: Bool = false
    @Published var pendingRecordingInitialTags: [TagItem] = []
    @Published var isShowingSettingsSheet: Bool = false
    @Published var navigationPath = NavigationPath()

    /// Modal de renombrado y etiquetado rápido (en listado o recién terminada una grabación)
    @Published var recordingPendingQuickEdit: VoiceRecording?

    /// Estado del coordinador de post-procesamiento en segundo plano (sin bloquear la UI)
    @Published var isBackgroundProcessingActive: Bool = false
    @Published var backgroundProcessingTitle: String = ""
    @Published var backgroundProcessingProgress: Double = 0.0
    @Published var backgroundProcessingStatus: String = ""
    @Published var activeBackgroundJobsCount: Int = 0

    private var modelContext: ModelContext?
    private let customTagsStorageKey = "com.pixelvoicepro.custom.tags"
    private let hiddenDefaultTagsStorageKey = "com.pixelvoicepro.hidden.default.tags"
    private let didSeedSampleKey = "com.pixelvoicepro.didSeedInitialSamples.v2"
    private let defaultTagIDs: Set<String> = Set(TagItem.predefinedTags.map { $0.id })

    private var pendingBackgroundJobs: [(recording: VoiceRecording, payload: BackgroundPostProcessingPayload)] = []
    private var backgroundQueueWorkerTask: Task<Void, Never>?

    init() {
        loadHiddenDefaultTags()
        loadCustomTags()
    }

    func attachModelContext(_ context: ModelContext) {
        guard self.modelContext == nil else {
            fetchRecordings()
            return
        }
        self.modelContext = context
        fetchRecordings()

        if recordings.isEmpty && !UserDefaults.standard.bool(forKey: didSeedSampleKey) {
            seedInitialSampleRecordings()
            UserDefaults.standard.set(true, forKey: didSeedSampleKey)
        }
    }

    func fetchRecordings() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<VoiceRecording>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let fetched = try? context.fetch(descriptor) {
            // Ordenar de la más antigua a la más reciente para numerar secuencialmente cualquier título automático antiguo
            let chronological = fetched.sorted { $0.createdAt < $1.createdAt }
            for (idx, rec) in chronological.enumerated() {
                if rec.title.hasPrefix("Grabación de la ") || rec.title == "__AUTO_SEQUENTIAL_TITLE__" {
                    rec.title = L10n.recordingDefaultTitle(idx + 1)
                }
                RecordingStorageService.ensurePlayableAudioFileExists(for: rec)
            }
            try? context.save()
            recordings = fetched.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func nextSequentialTitle() -> String {
        let knownPrefixes = Array(Set([L10n.recordingTitlePrefixCheck, "Grabación ", "Recording "]))
        let maxExisting = recordings.compactMap { rec -> Int? in
            for prefix in knownPrefixes where rec.title.hasPrefix(prefix) {
                let suffix = rec.title.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                if let parsed = Int(suffix) {
                    return parsed
                }
            }
            return nil
        }.max() ?? 0
        let nextNumber = max(recordings.count, maxExisting) + 1
        return L10n.recordingDefaultTitle(nextNumber)
    }

    func insertNewRecording(_ recording: VoiceRecording, presentQuickTitleEditor: Bool = true) {
        if recording.title.hasPrefix("Grabación de la ") || recording.title == "__AUTO_SEQUENTIAL_TITLE__" {
            recording.title = nextSequentialTitle()
        }
        if let context = modelContext {
            context.insert(recording)
            try? context.save()
        }
        fetchRecordings()
        if presentQuickTitleEditor {
            recordingPendingQuickEdit = recording
        }
    }

    func saveChanges() {
        try? modelContext?.save()
        fetchRecordings()
    }

    func deleteRecording(_ recording: VoiceRecording) {
        RecordingStorageService.deleteAudioFile(named: recording.audioFileName)
        if let context = modelContext {
            context.delete(recording)
            try? context.save()
        }
        fetchRecordings()
    }

    func toggleFavorite(_ recording: VoiceRecording) {
        recording.isFavorite.toggle()
        saveChanges()
    }

    func updateRecordingTitleAndTags(_ recording: VoiceRecording, newTitle: String, newTags: [TagItem]) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            recording.title = trimmed
        }
        recording.tags = newTags
        saveChanges()
    }

    func createCustomTag(name: String, colorHex: String, iconName: String = "tag.fill") -> TagItem {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateName = cleaned.isEmpty ? L10n.tagCustomDefault : cleaned
        if let existing = availableTags.first(where: {
            $0.localizedName.lowercased() == candidateName.lowercased() ||
            $0.name.lowercased() == candidateName.lowercased()
        }) {
            if isDefaultTag(existing) && hiddenDefaultTagIDs.contains(existing.id) {
                hiddenDefaultTagIDs.remove(existing.id)
                saveHiddenDefaultTags()
            }
            return existing
        }
        let newTag = TagItem(
            id: "tag_custom_\(UUID().uuidString.prefix(8))",
            name: candidateName,
            colorHex: colorHex,
            iconName: iconName
        )
        availableTags.append(newTag)
        saveCustomTags()
        return newTag
    }

    func isDefaultTag(_ tag: TagItem) -> Bool {
        defaultTagIDs.contains(tag.id)
    }

    func isTagHidden(_ tag: TagItem) -> Bool {
        isDefaultTag(tag) && hiddenDefaultTagIDs.contains(tag.id)
    }

    var visibleAvailableTags: [TagItem] {
        availableTags.filter { !hiddenDefaultTagIDs.contains($0.id) }
    }

    func toggleDefaultTagVisibility(_ tag: TagItem) {
        guard isDefaultTag(tag) else { return }
        if hiddenDefaultTagIDs.contains(tag.id) {
            hiddenDefaultTagIDs.remove(tag.id)
        } else {
            hiddenDefaultTagIDs.insert(tag.id)
            if selectedTagFilter?.id == tag.id {
                selectedTagFilter = nil
            }
        }
        saveHiddenDefaultTags()
    }

    func deleteCustomTag(_ tag: TagItem) {
        guard !isDefaultTag(tag) else { return }
        availableTags.removeAll { $0.id == tag.id }
        saveCustomTags()
        if selectedTagFilter?.id == tag.id {
            selectedTagFilter = nil
        }
        var didModifyAnyRecording = false
        for rec in recordings where rec.tags.contains(where: { $0.id == tag.id }) {
            rec.tags = rec.tags.filter { $0.id != tag.id }
            didModifyAnyRecording = true
        }
        if didModifyAnyRecording {
            saveChanges()
        }
    }

    // MARK: - Post-Procesamiento en Segundo Plano (No Bloqueante)

    func enqueueBackgroundPostProcessing(for recording: VoiceRecording, payload: BackgroundPostProcessingPayload) {
        pendingBackgroundJobs.append((recording, payload))
        activeBackgroundJobsCount = pendingBackgroundJobs.count + (isBackgroundProcessingActive ? 1 : 0)

        guard backgroundQueueWorkerTask == nil else { return }

        backgroundQueueWorkerTask = Task { [weak self] in
            guard let self = self else { return }
            while !self.pendingBackgroundJobs.isEmpty {
                let job = self.pendingBackgroundJobs.removeFirst()
                self.isBackgroundProcessingActive = true
                self.backgroundProcessingTitle = job.recording.title
                self.backgroundProcessingProgress = 0.08
                self.backgroundProcessingStatus = L10n.bgPreparing
                self.activeBackgroundJobsCount = self.pendingBackgroundJobs.count + 1

                await self.executeBackgroundJob(recording: job.recording, payload: job.payload)
            }
            self.isBackgroundProcessingActive = false
            self.backgroundProcessingProgress = 1.0
            self.backgroundProcessingStatus = ""
            self.activeBackgroundJobsCount = 0
            self.backgroundQueueWorkerTask = nil
        }
    }

    private func executeBackgroundJob(recording: VoiceRecording, payload: BackgroundPostProcessingPayload) async {
        let bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "PixelVoiceProPostProcess_\(recording.id.uuidString.prefix(6))")
        defer {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
        }

        let diarizer = payload.diarizationService
        let analyzer = payload.acousticAnalyzer
        let transcriber = payload.transcriptionService
        let fileURL = payload.audioFileURL
        let duration = payload.totalDuration
        let existingWords = payload.capturedWords
        let skipOfflineSoundAnalysis = payload.hadLiveTranscriptionEntireSession

        let result: (
            segments: [TranscriptSegment],
            engine: String,
            speakers: [SpeakerProfile],
            events: [AcousticEvent],
            silences: [SilenceInterval],
            sha256: String,
            fileSize: Int64
        ) = await Task.detached(priority: .utility) {
            await MainActor.run { [weak self] in
                self?.backgroundProcessingProgress = 0.12
                self?.backgroundProcessingStatus = L10n.bgAnalyzingSpeakers
            }
            diarizer.analyzeAudioFileOfflineIfNeeded(url: fileURL)

            await MainActor.run { [weak self] in
                self?.backgroundProcessingProgress = 0.18
                self?.backgroundProcessingStatus = L10n.bgDetectingEvents
            }
            if !skipOfflineSoundAnalysis {
                await analyzer.analyzeCompleteAudioFileIfNeeded(at: fileURL)
            }

            let events = analyzer.detectedEvents
            let silences = analyzer.silenceIntervals
            let speakers = diarizer.detectedSpeakers

            let processed = await transcriber.postProcessRecording(
                audioFileURL: fileURL,
                totalDuration: duration,
                existingWords: existingWords,
                diarizer: diarizer,
                acousticEvents: events,
                onProgress: { [weak self] progress, status in
                    self?.backgroundProcessingProgress = max(0.20, min(0.94, progress))
                    self?.backgroundProcessingStatus = status
                }
            )

            await MainActor.run { [weak self] in
                self?.backgroundProcessingProgress = 0.96
                self?.backgroundProcessingStatus = L10n.bgVerifyingSHA
            }
            let fileSize = AudioRecorderService.queryFileSizeBytes(at: fileURL)
            let sha256 = AudioRecorderService.computeSHA256Streaming(at: fileURL)

            return (
                processed.segments,
                processed.engineDescription,
                speakers,
                events,
                silences,
                sha256,
                fileSize
            )
        }.value

        // Verificar que la grabación no fue eliminada mientras se procesaba en segundo plano
        if recordings.contains(where: { $0.id == recording.id }) {
            recording.speakers = result.speakers
            recording.segments = result.segments
            recording.acousticEvents = result.events
            recording.silenceIntervals = result.silences
            recording.sha256Hash = result.sha256
            recording.fileSizeBytes = result.fileSize
            recording.transcriptionEngineUsed = result.engine
            recording.isProcessingBackground = false
            recording.recalculateSpeakerStatistics()
            saveChanges()
        }
    }

    // MARK: - Filtrado y Agrupación Cronológica Precisa al Segundo

    var filteredRecordings: [VoiceRecording] {
        recordings.filter { rec in
            if filterFavoritesOnly && !rec.isFavorite {
                return false
            }
            if let tagFilter = selectedTagFilter {
                if !rec.tags.contains(where: { $0.id == tagFilter.id }) {
                    return false
                }
            }
            if let periodFilter = filterDayPeriod {
                if rec.dayPeriod != periodFilter {
                    return false
                }
            }
            let trimmedQuery = globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedQuery.isEmpty {
                return !rec.evaluateGlobalSearchMatches(query: trimmedQuery).isEmpty
            }
            return true
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Agrupa las grabaciones por fecha exacta (`DD/MM/YYYY`) y las ordena de la más reciente a la más antigua.
    var chronologicalDayGroups: [ChronologicalDayGroup] {
        let list = filteredRecordings
        var groupedDict: [String: [VoiceRecording]] = [:]

        for rec in list {
            let key = ExactDateFormatter.exactDayKey(from: rec.createdAt)
            groupedDict[key, default: []].append(rec)
        }

        let groups: [ChronologicalDayGroup] = groupedDict.compactMap { key, items in
            let sortedItems = items.sorted { $0.createdAt > $1.createdAt }
            guard let newestDate = sortedItems.first?.createdAt else { return nil }
            let header = ExactDateFormatter.chronologicalGroupHeader(from: newestDate)
            return ChronologicalDayGroup(
                id: key,
                headerTitle: header,
                date: newestDate,
                recordings: sortedItems
            )
        }

        return groups.sorted { $0.date > $1.date }
    }

    /// Devuelve el listado filtrado y agrupado por día para una carpeta específica del Home de Voice Notes.
    func chronologicalDayGroups(for folder: FolderDestination, dayPeriod: DayPeriod? = nil) -> [ChronologicalDayGroup] {
        let filtered = recordings.filter { rec in
            switch folder {
            case .all:
                break
            case .favorites:
                guard rec.isFavorite else { return false }
            case .tag(let tag):
                guard rec.tags.contains(where: { $0.id == tag.id }) else { return false }
            }
            if let period = dayPeriod, rec.dayPeriod != period {
                return false
            }
            return true
        }
        .sorted { $0.createdAt > $1.createdAt }

        var groupedDict: [String: [VoiceRecording]] = [:]
        for rec in filtered {
            let key = ExactDateFormatter.exactDayKey(from: rec.createdAt)
            groupedDict[key, default: []].append(rec)
        }

        let groups: [ChronologicalDayGroup] = groupedDict.compactMap { key, items in
            let sortedItems = items.sorted { $0.createdAt > $1.createdAt }
            guard let newestDate = sortedItems.first?.createdAt else { return nil }
            let header = ExactDateFormatter.chronologicalGroupHeader(from: newestDate)
            return ChronologicalDayGroup(
                id: key,
                headerTitle: header,
                date: newestDate,
                recordings: sortedItems
            )
        }
        return groups.sorted { $0.date > $1.date }
    }

    func recordingCount(for folder: FolderDestination) -> Int {
        switch folder {
        case .all:
            return recordings.count
        case .favorites:
            return recordings.filter(\.isFavorite).count
        case .tag(let tag):
            return recordings.filter { rec in rec.tags.contains(where: { $0.id == tag.id }) }.count
        }
    }

    /// Coincidencias profundas en vivo para el Buscador Global sobre todas las notas.
    var globalDeepSearchMatches: [GlobalSearchMatch] {
        let trimmed = globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return recordings
            .sorted { $0.createdAt > $1.createdAt }
            .flatMap { $0.evaluateGlobalSearchMatches(query: trimmed) }
    }

    /// Tarjetas de notas que coinciden con el texto global de búsqueda.
    var globalSearchMatchingRecordings: [VoiceRecording] {
        let trimmed = globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return recordings
            .filter { !$0.evaluateGlobalSearchMatches(query: trimmed).isEmpty }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func openFolder(_ folder: FolderDestination) {
        navigationPath.append(folder)
    }

    func startRecordingSession(initialTags: [TagItem] = []) {
        pendingRecordingInitialTags = initialTags
        isShowingRecordingBooth = true
    }

    /// Abre una grabación directamente en el segundo exacto seleccionado desde un resultado del Buscador Global.
    func openRecordingFromSearchMatch(_ match: GlobalSearchMatch) {
        let target = RecordingNavigationTarget(
            recordingId: match.recordingId,
            initialSeekTimestamp: match.timestamp,
            highlightKeyword: globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        navigationPath.append(target)
    }

    func openRecording(_ recording: VoiceRecording) {
        let target = RecordingNavigationTarget(
            recordingId: recording.id,
            initialSeekTimestamp: nil,
            highlightKeyword: nil
        )
        navigationPath.append(target)
    }

    func recording(for id: UUID) -> VoiceRecording? {
        recordings.first { $0.id == id }
    }

    var totalStorageBytesUsed: Int64 {
        recordings.reduce(0) { $0 + $1.fileSizeBytes }
    }

    var formattedTotalStorageUsed: String {
        ExactDateFormatter.formattedFileSize(bytes: totalStorageBytesUsed)
    }

    // MARK: - Persistencia de Etiquetas y Semilla Inicial

    private func seedInitialSampleRecordings() {
        guard let context = modelContext else { return }
        let samples = RecordingStorageService.buildSampleRecordings()
        for sample in samples {
            context.insert(sample)
        }
        try? context.save()
        fetchRecordings()
    }

    private func loadCustomTags() {
        guard let data = UserDefaults.standard.data(forKey: customTagsStorageKey),
              let saved = try? JSONDecoder().decode([TagItem].self, from: data) else {
            availableTags = TagItem.predefinedTags
            return
        }
        var merged = TagItem.predefinedTags
        for item in saved where !merged.contains(where: { $0.id == item.id || $0.name.lowercased() == item.name.lowercased() }) {
            merged.append(item)
        }
        availableTags = merged
    }

    private func loadHiddenDefaultTags() {
        let stored = UserDefaults.standard.stringArray(forKey: hiddenDefaultTagsStorageKey) ?? []
        hiddenDefaultTagIDs = Set(stored.filter { defaultTagIDs.contains($0) })
    }

    private func saveHiddenDefaultTags() {
        UserDefaults.standard.set(Array(hiddenDefaultTagIDs), forKey: hiddenDefaultTagsStorageKey)
    }

    private func saveCustomTags() {
        if let data = try? JSONEncoder().encode(availableTags) {
            UserDefaults.standard.set(data, forKey: customTagsStorageKey)
        }
    }
}
