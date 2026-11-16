import SwiftUI
import SwiftData

/// Punto de entrada principal de la aplicación "PixelVoice Pro" compatible con iOS 17+ / iOS 27.
@main
struct PixelVoiceProApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            VoiceRecording.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("No se pudo inicializar el ModelContainer de SwiftData: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
