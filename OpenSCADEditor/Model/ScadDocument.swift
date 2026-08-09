import Foundation

/// The working `.scad` document. The raw `source` text is the single source of
/// truth; the parsed customizer `groups` are a derived view that re-syncs on
/// every edit. Editing a parameter splices its value back into `source`, and
/// editing `source` directly (the full editor) re-derives the parameters.
@MainActor
final class ScadDocument: ObservableObject {
    @Published var name: String
    @Published var source: String {
        didSet { groups = ScadParser.parse(source) }
    }
    @Published private(set) var groups: [ScadParameterGroup]

    /// The file backing this document, if any. Auto-save writes here.
    private(set) var currentURL: URL?
    /// The source last persisted to `currentURL`; edits diverge from this until saved.
    private var savedSource: String

    /// True when the in-memory source differs from what's on disk.
    var isDirty: Bool { source != savedSource }

    init(name: String, source: String, url: URL? = nil) {
        self.name = name
        self.source = source
        self.groups = ScadParser.parse(source)
        self.currentURL = url
        self.savedSource = source
    }

    /// Load a stored project, replacing the current document and rebinding the
    /// backing file so subsequent edits auto-save to it.
    func open(_ project: ScadProject, source: String) {
        self.name = project.name
        self.source = source
        self.currentURL = project.url
        self.savedSource = source
    }

    /// Mark the current source as persisted (called after a successful save).
    func markSaved() {
        savedSource = source
    }

    /// Update a single parameter's value by rewriting its line in `source`.
    /// The `didSet` reparse then re-derives `groups` from the new text.
    func update(_ parameter: ScadParameter, to value: ScadValue) {
        guard let current = groups.flatMap(\.parameters).first(where: { $0.id == parameter.id }) else { return }

        var updated = current
        updated.value = value

        var lines = source.components(separatedBy: "\n")
        guard lines.indices.contains(updated.lineIndex) else { return }
        lines[updated.lineIndex] = updated.rewrittenLine
        source = lines.joined(separator: "\n")
    }

    /// Every parameter across all groups, flattened.
    var allParameters: [ScadParameter] {
        groups.flatMap(\.parameters)
    }
}
