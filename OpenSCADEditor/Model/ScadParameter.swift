import Foundation

/// A concrete value a customizer parameter can hold.
enum ScadValue: Equatable {
    case number(Double)
    case bool(Bool)
    case string(String)

    /// The OpenSCAD source literal for this value (e.g. `10`, `true`, `"box"`).
    var literal: String {
        switch self {
        case .number(let n):
            // Print integers without a trailing ".0" to keep the source tidy.
            if n.rounded() == n && abs(n) < 1e15 {
                return String(Int(n))
            }
            return String(n)
        case .bool(let b):
            return b ? "true" : "false"
        case .string(let s):
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
    }
}

/// How a parameter should be presented and edited.
enum ScadControl: Equatable {
    /// Numeric slider with an inclusive range and step.
    case slider(min: Double, max: Double, step: Double)
    /// Free-form numeric entry (no range annotation).
    case number
    /// Boolean checkbox / toggle.
    case toggle
    /// Free-form text entry.
    case text
    /// Dropdown of numeric options with display labels.
    case numberChoice(options: [Double], labels: [String])
    /// Dropdown of string options with display labels.
    case stringChoice(options: [String], labels: [String])
}

/// One editable OpenSCAD customizer parameter, plus the metadata needed to
/// rewrite its line back into the source verbatim (indentation + trailing comment).
struct ScadParameter: Identifiable, Equatable {
    /// Stable across reparses (group + name is unique within a customizer file),
    /// so SwiftUI keeps row identity and slider drags stay smooth even though
    /// every edit reparses the source.
    var id: String { "\(group)::\(name)" }
    let name: String
    var value: ScadValue
    let control: ScadControl
    let group: String

    /// Zero-based line index in the original source this parameter was parsed from.
    let lineIndex: Int
    /// Leading whitespace on that line, preserved on rewrite.
    let indent: String
    /// Trailing comment (including the leading `//` or `/* */`), preserved on rewrite.
    let trailingComment: String

    /// The full rewritten source line for the current `value`.
    var rewrittenLine: String {
        let comment = trailingComment.isEmpty ? "" : " \(trailingComment)"
        return "\(indent)\(name) = \(value.literal);\(comment)"
    }
}

/// A named collection of parameters shown together under one section header.
struct ScadParameterGroup: Identifiable, Equatable {
    var id: String { name }
    let name: String
    var parameters: [ScadParameter]
}
