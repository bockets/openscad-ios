import SwiftUI
import UniformTypeIdentifiers

/// Full-screen list of stored `.scad` projects. Tapping a row opens it; the
/// toolbar creates a new project or imports one from the Files app; rows swipe to
/// export (to Files, via the share sheet) or delete.
struct ProjectsListView: View {
    @ObservedObject var store: ProjectStore
    /// The currently-open project's file, so its row can show a checkmark.
    let currentURL: URL?
    let onOpen: (ScadProject) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var showingNew = false
    @State private var newProjectName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.projects) { project in
                    row(project)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(project) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(project)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            ShareLink(item: project.url) {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                }
            }
            // Plain (edge-to-edge) rows rather than the inset-grouped card, so
            // swipe-to-reveal keeps square, full-bleed action buttons — the
            // rounded card corners otherwise clip into 90° edges mid-swipe.
            .listStyle(.plain)
            .overlay {
                if store.projects.isEmpty {
                    ContentUnavailableView("No Projects", systemImage: "cube",
                                           description: Text("Create one or import a .scad file."))
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingNew = true
                        } label: {
                            Label("New Project", systemImage: "doc.badge.plus")
                        }
                        Button {
                            importing = true
                        } label: {
                            Label("Import from Files", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: Self.importTypes,
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    urls.forEach { _ = store.importFile(at: $0) }
                }
            }
            .alert("New Project", isPresented: $showingNew) {
                TextField("Name", text: $newProjectName)
                Button("Create") { createNew() }
                Button("Cancel", role: .cancel) { newProjectName = "" }
            }
        }
    }

    private func row(_ project: ScadProject) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "cube")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .foregroundStyle(.primary)
                Text(project.modifiedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if project.url == currentURL {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }

    private func createNew() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        newProjectName = ""
        if let project = store.create(name: name.isEmpty ? "Untitled" : name, source: Self.newTemplate) {
            onOpen(project)
        }
    }

    // MARK: - Constants

    /// Content types offered in the Files importer. `.scad` isn't a system type, so
    /// synthesize it from the extension and fall back to text/data types.
    private static var importTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .sourceCode, .data]
        if let scad = UTType(filenameExtension: "scad") {
            types.insert(scad, at: 0)
        }
        return types
    }

    private static let newTemplate = """
    // New Project

    /* [Size] */
    size = 20; // [5:50]

    cube(size, center = true);
    """
}
