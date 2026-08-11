import Foundation
import SceneKit

/// Bridges the document to the OpenSCAD engine: debounces edits, runs a single
/// render at a time, and publishes the resulting mesh + status for the UI.
@MainActor
final class RenderCoordinator: ObservableObject {

    enum Status: Equatable {
        case idle
        case rendering
        case success
        case failure(String)
    }

    @Published private(set) var node: SCNNode
    @Published private(set) var status: Status = .idle
    @Published private(set) var log: String = ""
    /// A file URL for the most recent successful render's STL, ready to share.
    @Published private(set) var exportURL: URL?

    let renderer = OpenSCADRenderer()

    private var pending: Task<Void, Never>?
    /// How long to coalesce rapid edits before rendering. Short enough that the
    /// live preview feels responsive while typing, long enough to skip a render
    /// on every keystroke.
    private let debounce: Duration = .milliseconds(150)

    init() {
        // Start empty — the preview stays blank (behind the "Rendering…" pill)
        // until the first real mesh lands, rather than flashing a placeholder box.
        node = SCNNode()
    }

    /// Request a render of `source`, cancelling any queued/in-flight request.
    /// `name` names the exported STL file.
    func request(source: String, name: String) {
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            guard !Task.isCancelled else { return }

            self.status = .rendering
            let output = await self.renderer.render(source: source)
            guard !Task.isCancelled else { return }

            self.log = output.log
            if let stl = output.stl, let mesh = MeshBuilder.node(fromSTL: stl) {
                self.node = mesh
                self.exportURL = Self.writeSTL(stl, name: name)
                self.status = .success
            } else {
                self.status = .failure(output.error ?? "Render failed")
            }
        }
    }

    /// Writes STL bytes to a temp file named after the document, overwriting any
    /// previous export. Returns nil if writing fails.
    private static func writeSTL(_ data: Data, name: String) -> URL? {
        let safe = name.isEmpty ? "model" : name
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).stl")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
