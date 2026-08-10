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
    /// A rendered preview image for the projects list, if one has been captured
    /// (written when the project is closed). Nil falls back to a placeholder icon.
    let thumbnailURL: URL?

    var id: URL { url }
}
