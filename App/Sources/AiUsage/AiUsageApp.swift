import SwiftUI
import AppKit

@main
struct AiUsageApp: App {
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
        } label: {
            Image(nsImage: menuBarImageRenderer.image(for: appState.menuBarSummary.glyph))
                .renderingMode(.template)
                .interpolation(.none)
                .id(appState.menuBarSummary.glyph)
                .accessibilityLabel("AiUsage 分组额度")
                .task {
                    await appState.startIfNeeded()
                    appState.startAutoRefresh()
                }
        }
        .menuBarExtraStyle(.window)

        WindowGroup("AiUsage", id: "detail") {
            ProviderDetailView()
                .environment(appState)
                .task {
                    Task { await appState.startIfNeeded() }
                }
                .frame(minWidth: 640, minHeight: 520)
        }
        .windowStyle(.automatic)

        Window("MiMo 登录", id: "mimo-login") {
            MiMoWebLoginWindowView()
                .environment(appState)
        }
        .windowStyle(.automatic)

        Settings {
            SettingsView()
                .environment(appState)
                .frame(width: 460, height: 520)
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
