import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The app's home screen: a list of stored `.scad` projects. Tapping a row opens
/// it in the editor; the toolbar creates a new project or imports one from the
/// Files app; rows swipe to export (to Files, via the share sheet) or delete.
///
/// Rendered as the root of the app's `NavigationStack`, so it supplies no
/// navigation container of its own.
struct ProjectsListView: View {
    @ObservedObject var store: ProjectStore
    let onOpen: (ScadProject) -> Void

    @State private var importing = false
    @State private var showingNew = false
    @State private var newProjectName = ""

    var body: some View {
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

    private func row(_ project: ScadProject) -> some View {
        HStack(spacing: 12) {
            thumbnail(project)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .foregroundStyle(.primary)
                Text(project.modifiedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    /// The rendered preview captured when the project was last closed, or a
    /// placeholder cube for projects that haven't been opened yet.
    @ViewBuilder
    private func thumbnail(_ project: ScadProject) -> some View {
        let side: CGFloat = 44
        Group {
            if let url = project.thumbnailURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "cube")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.12))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
