import SwiftUI
import AppKit

@main
struct AIUsageLocalApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("AI Usage Local", systemImage: "chart.bar.xaxis") {
            RootView()
                .environment(appState)
                .task {
                    await appState.startIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)

        WindowGroup("AI Usage Local", id: "detail") {
            ProviderDetailView()
                .environment(appState)
                .task {
                    await appState.startIfNeeded()
                }
                .frame(minWidth: 640, minHeight: 520)
        }
        .windowStyle(.automatic)

        Settings {
            SettingsView()
                .environment(appState)
                .frame(width: 420, height: 260)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await appState.refreshOnBecomeActive()
            }
        }
    }
}
