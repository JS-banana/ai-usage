import SwiftUI
import AppKit

struct MiMoCredentialFields: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "mimo-login")
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.key")
                    Text("登录小米账号")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("将在小米官方页面完成登录，App 只保存查询额度所需的登录态到系统 Keychain。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
