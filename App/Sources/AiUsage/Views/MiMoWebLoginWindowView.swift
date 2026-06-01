import SwiftUI

struct MiMoWebLoginWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isSavingSession = false
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("登录小米账号")
                        .font(.headline)
                    Text("在官方页面完成登录后，AiUsage 会自动保存额度查询所需的登录态。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSavingSession {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(12)

            if let loginError {
                Label(loginError, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            Divider()

            MiMoWebLoginView(
                onToken: { token in
                    Task { await persistWebLogin(token: token) }
                },
                onError: { error in
                    loginError = error.localizedDescription
                }
            )
        }
        .frame(minWidth: 920, idealWidth: 920, minHeight: 720, idealHeight: 720)
    }

    private func persistWebLogin(token: MiMoServiceToken) async {
        guard isSavingSession == false else { return }
        isSavingSession = true
        loginError = nil

        let coordinator = MiMoLoginCoordinator()
        do {
            try await coordinator.storeWebSession(token: token)
            await appState.refresh()
            appState.markMiMoLoginCompleted()
            dismissWindow(id: "mimo-login")
        } catch {
            loginError = error.localizedDescription
        }

        isSavingSession = false
    }
}
