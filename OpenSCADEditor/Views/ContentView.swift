import SwiftUI
import SceneKit

struct ContentView: View {
    @StateObject private var document = ScadDocument(
        name: SampleLibrary.default.name,
        source: SampleLibrary.default.source
    )
    @StateObject private var coordinator = RenderCoordinator()
    @StateObject private var store = ProjectStore()
    @State private var showingProjects = false
    @State private var showingLog = false
    @State private var editorMode: EditorMode = .customize
    @State private var isEditingSource = false
    /// `.compact` vertical size means a landscape phone — lay the panes out
    /// side by side instead of stacked, or a fixed-height preview would crush
    /// the controls in the short viewport.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private enum EditorMode: Hashable {
        case customize
        case source
    }

    var body: some View {
        NavigationStack {
            layout
            .animation(.easeInOut(duration: 0.25), value: previewCollapsed)
            .navigationTitle(document.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        openProjects()
                    } label: {
                        Label("Projects", systemImage: "folder")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let url = coordinator.exportURL {
                        ShareLink(item: url) {
                            Label("Export STL", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingProjects) {
                ProjectsListView(
                    store: store,
                    currentURL: document.currentURL,
                    onOpen: { openProject($0) }
                )
            }
            .sheet(isPresented: $showingLog) {
                LogSheet(log: coordinator.log)
            }
            .task { await bootstrapProjects() }
            .onAppear { coordinator.request(source: document.source, name: document.name) }
            .onChange(of: document.source) { _, source in
                coordinator.request(source: source, name: document.name)
            }
        }
    }

    // MARK: - Layout

    private var isLandscape: Bool { verticalSizeClass == .compact }

    /// Portrait: preview stacked above the editor. Landscape: preview beside the
    /// editor so the short viewport doesn't crush the controls.
    @ViewBuilder
    private var layout: some View {
        if isLandscape {
            HStack(spacing: 0) {
                if !previewCollapsed {
                    preview
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.5 }
                    Divider()
                }
                editor
            }
        } else {
            VStack(spacing: 0) {
                if !previewCollapsed {
                    preview
                        .frame(height: 300)
                    Divider()
                }
                editor
            }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            modePicker
            Divider()
            bottomPane
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Projects

    /// Open the projects list, auto-saving the current model first if it's been edited.
    private func openProjects() {
        autosaveCurrent()
        showingProjects = true
    }

    /// Open a stored project, persisting any edits to the current one first.
    private func openProject(_ project: ScadProject) {
        autosaveCurrent()
        document.open(project, source: store.source(of: project))
        showingProjects = false
    }

    /// Write the current source back to its backing file when there are unsaved edits.
    private func autosaveCurrent() {
        guard document.isDirty, let url = document.currentURL else { return }
        if store.save(source: document.source, to: url) {
            document.markSaved()
        }
    }

    /// Resolve storage, seed the examples on first launch, and bind the launch
    /// document to its backing file so edits from the very first session persist.
    private func bootstrapProjects() async {
        await store.bootstrap()
        guard document.currentURL == nil else { return }
        let launch = store.projects.first { $0.name == document.name } ?? store.projects.first
        if let launch {
            document.open(launch, source: store.source(of: launch))
        }
    }

    private var modePicker: some View {
        Picker("Editor mode", selection: $editorMode) {
            Text("Customize").tag(EditorMode.customize)
            Text("Source").tag(EditorMode.source)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// When the source editor is focused, hide the preview so the editor gets the
    /// space above the keyboard instead of being squeezed to a couple of lines.
    private var previewCollapsed: Bool {
        editorMode == .source && isEditingSource
    }

    @ViewBuilder
    private var bottomPane: some View {
        switch editorMode {
        case .customize:
            ParameterControlsView(document: document)
        case .source:
            SourceEditorView(text: $document.source, onFocusChange: { focused in
                isEditingSource = focused
            })
        }
    }

    private var preview: some View {
        ScenePreviewView(node: coordinator.node)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [Color(white: 0.16), Color(white: 0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .top) { statusBar }
    }

    @ViewBuilder
    private var statusBar: some View {
        switch coordinator.status {
        case .idle:
            EmptyView()
        case .rendering:
            Label("Rendering…", systemImage: "gearshape.2")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
        case .success:
            EmptyView()
        case .failure(let message):
            Button {
                showingLog = true
            } label: {
                Label(firstLine(message), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.red.opacity(0.85), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, 8)
            }
        }
    }

    private func firstLine(_ text: String) -> String {
        text.split(separator: "\n").first.map(String.init) ?? "Render error"
    }
}

/// Shows the raw OpenSCAD compiler log / error output.
private struct LogSheet: View {
    let log: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(log.isEmpty ? "No output." : log)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("OpenSCAD Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
