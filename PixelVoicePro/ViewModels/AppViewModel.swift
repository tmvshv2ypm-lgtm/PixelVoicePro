import Foundation
import SwiftUI
import SwiftData

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

@MainActor
final class AppViewModel: ObservableObject {
    @Published var recordings: [VoiceRecording] = []
    @Published var globalSearchQuery: String = ""
    @Published var selectedTagFilter: TagItem?
    @Published var filterFavoritesOnly: Bool = false
    @Published var filterDayPeriod: DayPeriod?

    @Published var availableTags: [TagItem] = TagItem.predefinedTags
    @Published var isShowingRecordingBooth: Bool = false
    @Published var isShowingSettingsSheet: Bool = false
    @Published var activeNavigationTarget: RecordingNavigationTarget?

    /// Modal de renombrado y etiquetado rápido (en listado o recién terminada una grabación)
    @Published var recordingPendingQuickEdit: VoiceRecording?

    private var modelContext: ModelContext?
    private let customTagsStorageKey = "com.pixelvoicepro.custom.tags"
    private let didSeedSampleKey = "com.pixelvoicepro.didSeedInitialSamples.v2"

    init() {
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
            recordings = fetched.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func insertNewRecording(_ recording: VoiceRecording, presentQuickTitleEditor: Bool = true) {
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
        let newTag = TagItem(
            id: "tag_custom_\(UUID().uuidString.prefix(8))",
            name: cleaned.isEmpty ? "Personalizada" : cleaned,
            colorHex: colorHex,
            iconName: iconName
        )
        if !availableTags.contains(where: { $0.name.lowercased() == newTag.name.lowercased() }) {
            availableTags.append(newTag)
            saveCustomTags()
        }
        return newTag
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

    /// Coincidencias profundas en vivo para el Buscador Global (mostrando en qué nota y en qué minuto/segundo exacto se dijo la palabra).
    var globalDeepSearchMatches: [GlobalSearchMatch] {
        let trimmed = globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return filteredRecordings.flatMap { $0.evaluateGlobalSearchMatches(query: trimmed) }
    }

    /// Abre una grabación directamente en el segundo exacto seleccionado desde un resultado del Buscador Global.
    func openRecordingFromSearchMatch(_ match: GlobalSearchMatch) {
        activeNavigationTarget = RecordingNavigationTarget(
            recordingId: match.recordingId,
            initialSeekTimestamp: match.timestamp,
            highlightKeyword: globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func openRecording(_ recording: VoiceRecording) {
        activeNavigationTarget = RecordingNavigationTarget(
            recordingId: recording.id,
            initialSeekTimestamp: nil,
            highlightKeyword: nil
        )
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
        for item in saved where !merged.contains(where: { $0.id == item.id }) {
            merged.append(item)
        }
        availableTags = merged
    }

    private func saveCustomTags() {
        if let data = try? JSONEncoder().encode(availableTags) {
            UserDefaults.standard.set(data, forKey: customTagsStorageKey)
        }
    }
}
