import Foundation

/// File-backed storage for `.scad` projects.
///
/// Prefers the app's iCloud Documents (ubiquity) container so projects sync across
/// devices; falls back to the local Documents directory when iCloud isn't available
/// — no entitlement configured, signed out of iCloud, or the plain simulator. The
/// list, auto-save, and Files-app import/export all work either way; adding the
/// iCloud entitlement on a signed build is what turns on syncing.
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ScadProject] = []
    /// True when the container resolved to iCloud (drives the storage-status footer).
    @Published private(set) var isCloud = false

    private var container: URL?

    /// Resolve the container (off the main actor — the ubiquity lookup can block),
    /// seed the bundled examples on first launch, then load the list.
    func bootstrap() async {
        let (url, cloud) = await Self.resolveContainer()
        container = url
        isCloud = cloud
        seedExamplesIfNeeded(in: url)
        refresh()
    }

    /// Re-read the container and rebuild `projects`, most-recently-modified first.
    func refresh() {
        guard let container else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        projects = files
            .filter { $0.pathExtension.lowercased() == "scad" }
            .map { url in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let thumbnail = thumbnailURL(for: url)
                let hasThumbnail = thumbnail.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                return ScadProject(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    modifiedAt: modified,
                    thumbnailURL: hasThumbnail ? thumbnail : nil
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// The raw source of a stored project.
    func source(of project: ScadProject) -> String {
        (try? String(contentsOf: project.url, encoding: .utf8)) ?? ""
    }

    /// Persist source to an existing file (used by auto-save).
    @discardableResult
    func save(source: String, to url: URL) -> Bool {
        guard let data = source.data(using: .utf8) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            refresh()
            return true
        } catch {
            return false
        }
    }

    /// Create a new project file, disambiguating the name if it already exists.
    @discardableResult
    func create(name: String, source: String) -> ScadProject? {
        guard let container else { return nil }
        let url = uniqueURL(for: name, in: container)
        guard let data = source.data(using: .utf8),
              (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        refresh()
        return projects.first { $0.url == url }
    }

    func delete(_ project: ScadProject) {
        try? FileManager.default.removeItem(at: project.url)
        if let thumbnail = thumbnailURL(for: project.url) {
            try? FileManager.default.removeItem(at: thumbnail)
        }
        refresh()
    }

    /// Persist a rendered preview image for a project, keyed by its file name.
    /// Thumbnails live in a hidden `.thumbnails` subfolder so they never surface
    /// as projects (which are matched by the `.scad` extension) or in Files.
    func saveThumbnail(_ data: Data, for url: URL) {
        guard let dir = thumbnailsDirectory, let dest = thumbnailURL(for: url) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard (try? data.write(to: dest, options: .atomic)) != nil else { return }
        refresh()
    }

    private var thumbnailsDirectory: URL? {
        container?.appendingPathComponent(".thumbnails", isDirectory: true)
    }

    private func thumbnailURL(for url: URL) -> URL? {
        thumbnailsDirectory?
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("png")
    }

    /// Copy a Files-app–picked document into the container, reading it under its
    /// security scope. Returns the new project (or nil if it couldn't be read).
    @discardableResult
    func importFile(at pickedURL: URL) -> ScadProject? {
        let scoped = pickedURL.startAccessingSecurityScopedResource()
        defer { if scoped { pickedURL.stopAccessingSecurityScopedResource() } }

        guard let source = try? String(contentsOf: pickedURL, encoding: .utf8) else { return nil }
        return create(name: pickedURL.deletingPathExtension().lastPathComponent, source: source)
    }

    // MARK: - Helpers

    private func uniqueURL(for name: String, in container: URL) -> URL {
        let base = name.isEmpty ? "Untitled" : name
        var candidate = container.appendingPathComponent(base).appendingPathExtension("scad")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = container.appendingPathComponent("\(base) \(index)").appendingPathExtension("scad")
            index += 1
        }
        return candidate
    }

    /// Write the bundled examples into the container once, tracked by a hidden
    /// marker so re-launches (and re-seeding after the user deletes one) don't
    /// resurrect them.
    private func seedExamplesIfNeeded(in container: URL) {
        let marker = container.appendingPathComponent(".seeded")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }

        for sample in SampleLibrary.all {
            let url = container.appendingPathComponent(sample.name).appendingPathExtension("scad")
            if !FileManager.default.fileExists(atPath: url.path) {
                try? sample.source.data(using: .utf8)?.write(to: url, options: .atomic)
            }
            seedBundledThumbnail(named: sample.name, for: url)
        }
        FileManager.default.createFile(atPath: marker.path, contents: nil)
    }

    /// Seed a bundled pre-rendered thumbnail for a seeded sample, so its projects-list
    /// tile shows the model on first launch instead of the empty placeholder (the
    /// live render only produces one once the user opens it). Skips silently if the
    /// bundle ships no `<name>.png` or a thumbnail is already present.
    private func seedBundledThumbnail(named name: String, for scadURL: URL) {
        guard let bundled = Bundle.main.url(forResource: name, withExtension: "png"),
              let dir = thumbnailsDirectory,
              let dest = thumbnailURL(for: scadURL),
              !FileManager.default.fileExists(atPath: dest.path) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: bundled, to: dest)
    }

    /// Resolve the storage container off the main actor. The iCloud ubiquity lookup
    /// can block, so it runs on a detached task; the result is Sendable (URL + Bool).
    private static func resolveContainer() async -> (url: URL, isCloud: Bool) {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            if let ubiquity = fm.url(forUbiquityContainerIdentifier: nil) {
                let docs = ubiquity.appendingPathComponent("Documents")
                try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
                return (docs, true)
            }
            let local = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return (local, false)
        }.value
    }
}
