import SwiftUI
import SceneKit

/// The editor for a single project: live 3D preview above a customizer / source
/// editor. Pushed onto the navigation stack from the projects list, so the back
/// button returns there; edits auto-save to the backing file on the way out.
struct EditorView: View {
    let project: ScadProject
    @ObservedObject var store: ProjectStore

    @StateObject private var document: ScadDocument
    @StateObject private var coordinator = RenderCoordinator()
    @State private var showingLog = false
    @State private var editorMode: EditorMode = .customize
    @State private var isEditingSource = false
    /// `.compact` vertical size means a landscape phone — lay the panes out
    /// side by side instead of stacked, or a fixed-height preview would crush
    /// the controls in the short viewport.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(project: ScadProject, store: ProjectStore) {
        self.project = project
        self.store = store
        _document = StateObject(wrappedValue: ScadDocument(
            name: project.name,
            source: store.source(of: project),
            url: project.url
        ))
    }

    private enum EditorMode: Hashable {
        case customize
        case source
    }

    var body: some View {
        layout
            .animation(.easeInOut(duration: 0.25), value: previewHeight)
            .navigationTitle(document.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let url = coordinator.exportURL {
                        ShareLink(item: url) {
                            Label("Export STL", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingLog) {
                LogSheet(log: coordinator.log)
            }
            .onAppear { coordinator.request(source: document.source, name: document.name) }
            .onDisappear { autosave() }
            .onChange(of: document.source) { _, source in
                coordinator.request(source: source, name: document.name)
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
                preview
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.5 }
                Divider()
                editor
            }
        } else {
            VStack(spacing: 0) {
                preview
                    .frame(height: previewHeight)
                Divider()
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

    /// Write the current source back to its backing file when there are unsaved edits.
    private func autosave() {
        guard document.isDirty, let url = document.currentURL else { return }
        if store.save(source: document.source, to: url) {
            document.markSaved()
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

    /// Portrait preview height: shrink it while editing source (keyboard up) so
    /// the editor gets more room above the keyboard, but keep it visible so live
    /// changes still show.
    private var previewHeight: CGFloat {
        editorMode == .source && isEditingSource ? 140 : 300
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
