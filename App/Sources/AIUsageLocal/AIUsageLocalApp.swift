import Foundation
import SwiftUI
import AppKit
import Domain

@main
struct AIUsageLocalApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("AI Usage Local") {
            RootView()
                .environment(appState)
                .frame(minWidth: 1180, minHeight: 760)
                .task {
                    await appState.bootstrap()
                }
        }
        .windowStyle(.automatic)

        Settings {
            SettingsView()
                .environment(appState)
                .frame(width: 620, height: 440)
        }
    }
}
