import Foundation

/// A stored `.scad` project on disk, in either the iCloud Documents container or
/// the local Documents directory. The file is the source of truth; this is a
/// lightweight snapshot for the projects list.
struct ScadProject: Identifiable, Equatable, Hashable {
    /// The backing file. Also serves as stable identity across list refreshes.
    let url: URL
    /// Display name — the file's base name (e.g. "Parametric Box").
    let name: String
    /// Last modification time, used to sort most-recent first.
    let modifiedAt: Date

    var id: URL { url }
}
