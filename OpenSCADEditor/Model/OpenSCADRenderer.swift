import Foundation
import WebKit

/// Serves the bundled web engine files (`index.html`, `openscad.js`,
/// `openscad.wasm`, `openscad.wasm.js`) over a custom URL scheme so the WebView
/// can `fetch()` them with correct MIME types — in particular `application/wasm`,
/// which `file://` cannot provide.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "oscad"

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        let filename = url.lastPathComponent
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        guard let fileURL = Bundle.main.url(forResource: base, withExtension: ext),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(for: ext),
                "Content-Length": String(data.count),
                "Access-Control-Allow-Origin": "*"
            ]
        )!

        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }
}

/// Drives the headless OpenSCAD WebAssembly engine hosted in an off-screen
/// `WKWebView`, compiling `.scad` source into binary STL data.
@MainActor
final class OpenSCADRenderer: NSObject, ObservableObject {

    enum Readiness: Equatable {
        case loading
        case ready
        case failed(String)
    }

    struct Output {
        let stl: Data?
        let log: String
        let error: String?
    }

    @Published private(set) var readiness: Readiness = .loading

    private let webView: WKWebView
    private var readyWaiters: [CheckedContinuation<Bool, Never>] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: BundleSchemeHandler.scheme)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        configuration.userContentController.add(MessageProxy(renderer: self), name: "status")
        webView.isInspectable = true

        let start = URL(string: "\(BundleSchemeHandler.scheme)://engine/index.html")!
        webView.load(URLRequest(url: start))
    }

    /// Compile `.scad` source into STL bytes. Waits for the engine to be ready.
    func render(source: String) async -> Output {
        guard await waitUntilReady() else {
            return Output(stl: nil, log: "", error: readinessError)
        }

        do {
            let raw = try await webView.callAsyncJavaScript(
                "return await window.renderScad(source);",
                arguments: ["source": source],
                contentWorld: .page
            )
            return Self.parse(raw)
        } catch {
            return Output(stl: nil, log: "", error: error.localizedDescription)
        }
    }

    // MARK: - Readiness

    private var readinessError: String {
        if case .failed(let message) = readiness { return message }
        return "engine not ready"
    }

    private func waitUntilReady() async -> Bool {
        switch readiness {
        case .ready: return true
        case .failed: return false
        case .loading:
            return await withCheckedContinuation { readyWaiters.append($0) }
        }
    }

    fileprivate func handleStatus(_ body: Any) {
        guard let dict = body as? [String: Any], let event = dict["event"] as? String else { return }
        switch event {
        case "ready":
            readiness = .ready
            resumeWaiters(true)
        case "error":
            readiness = .failed(dict["message"] as? String ?? "engine init failed")
            resumeWaiters(false)
        default:
            break
        }
    }

    private func resumeWaiters(_ value: Bool) {
        let waiters = readyWaiters
        readyWaiters.removeAll()
        waiters.forEach { $0.resume(returning: value) }
    }

    // MARK: - Result parsing

    private static func parse(_ raw: Any?) -> Output {
        guard let dict = raw as? [String: Any] else {
            return Output(stl: nil, log: "", error: "unexpected engine result")
        }
        let log = dict["log"] as? String ?? ""
        if dict["ok"] as? Bool == true,
           let base64 = dict["stl"] as? String,
           let data = Data(base64Encoded: base64) {
            return Output(stl: data, log: log, error: nil)
        }
        return Output(stl: nil, log: log, error: dict["error"] as? String ?? "render failed")
    }
}

/// Weak bridge so the `WKUserContentController` doesn't retain the renderer.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var renderer: OpenSCADRenderer?

    init(renderer: OpenSCADRenderer) {
        self.renderer = renderer
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        Task { @MainActor in renderer?.handleStatus(body) }
    }
}
