import SwiftUI
import WebKit

struct MiMoWebLoginView: NSViewRepresentable {
    var onToken: (MiMoServiceToken) -> Void
    var onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToken: onToken, onError: onError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.load(URLRequest(url: URL(string: "https://platform.xiaomimimo.com/console/plan-manage")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onToken: (MiMoServiceToken) -> Void
        private let onError: (Error) -> Void
        private var didFinish = false

        init(onToken: @escaping (MiMoServiceToken) -> Void, onError: @escaping (Error) -> Void) {
            self.onToken = onToken
            self.onError = onError
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            inspectCookies(in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onError(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onError(error)
        }

        private func inspectCookies(in webView: WKWebView) {
            guard didFinish == false else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, self.didFinish == false else { return }
                let mapped = cookies.map { MiMoWebCookie(name: $0.name, value: $0.value) }
                do {
                    let token = try MiMoWebSessionExtractor.extractToken(from: mapped)
                    self.didFinish = true
                    DispatchQueue.main.async {
                        self.onToken(token)
                    }
                } catch MiMoWebSessionExtractor.ExtractionError.missingCookies {
                    return
                } catch {
                    DispatchQueue.main.async {
                        self.onError(error)
                    }
                }
            }
        }
    }
}
