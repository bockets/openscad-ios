import SwiftUI

/// Root view. The projects list is the home screen; opening a project pushes the
/// editor onto the stack.
struct ContentView: View {
    @StateObject private var store = ProjectStore()
    @State private var path: [ScadProject] = []

    var body: some View {
        NavigationStack(path: $path) {
            ProjectsListView(store: store, onOpen: { path.append($0) })
                .navigationDestination(for: ScadProject.self) { project in
                    EditorView(project: project, store: store)
                }
        }
        .task { await store.bootstrap() }
    }
}

#Preview {
    ContentView()
}
