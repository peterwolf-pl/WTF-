import SwiftUI
import SwiftData

@main
struct WTFApp: App {
    @State private var modelContainer: ModelContainer

    init() {
        // TODO: Requires iOS 17+
        modelContainer = try! ModelContainer(for: WorkSession.self, TaskTemplate.self)
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                TimerView()
                    .tabItem {
                        Label("Timer", systemImage: "timer")
                    }
                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "chart.bar")
                    }
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
            .modelContainer(modelContainer)
        }
    }
}

