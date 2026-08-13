import Foundation

// A deliberate SwiftLint violation to confirm the PR check blocks bad code.
enum LintCanary {
    static func load() -> Data {
        let url = URL(string: "https://example.com")!
        return try! Data(contentsOf: url)
    }
}
