import SwiftUI
import AppKit

@main
struct AiUsageApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState: AppState
    private let menuBarImageRenderer = QuotaMenuBarImageRenderer()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        _appState = State(initialValue: Self.makeInitialAppState())
    }

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(appState)
                .task {
                    await appState.startIfNeeded()
                }
        } label: {
            Image(nsImage: menuBarImageRenderer.image(for: appState.menuBarSummary.glyph))
                .renderingMode(.template)
                .interpolation(.none)
                .accessibilityLabel("AiUsage 分组额度")
        }
        .menuBarExtraStyle(.window)

        WindowGroup("AiUsage", id: "detail") {
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
                .frame(width: 460, height: 520)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await appState.refreshOnBecomeActive()
            }
        }
    }

    @MainActor
    private static func makeInitialAppState() -> AppState {
        do {
            return try AppContainer.live().makeAppState()
        } catch {
            return AppState(bootstrapError: error)
        }
    }
}
