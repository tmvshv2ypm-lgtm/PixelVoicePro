import SwiftUI
import SwiftData

/// Contenedor raíz que vincula el `ModelContext` de SwiftData con el `AppViewModel` y el `AudioRecorderService`.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var appViewModel = AppViewModel()
    @StateObject private var recorderService = AudioRecorderService()
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        DashboardView(
            viewModel: appViewModel,
            recorderService: recorderService
        )
        .tint(themeManager.primaryAccent)
        .onAppear {
            appViewModel.attachModelContext(modelContext)
        }
    }
}
