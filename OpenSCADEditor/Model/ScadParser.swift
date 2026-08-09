import Foundation
import Parsing

/// Parses OpenSCAD "Customizer" parameters out of a `.scad` source string using
/// `swift-parsing` combinators (no regex).
///
/// It recognises the leading block of top-level assignments (everything before
/// the first `module`/`function` definition), the `/* [Group] */` section
/// headers, and the trailing `// [..]` annotations describing ranges/dropdowns.
///
/// Reference: https://en.wikibooks.org/wiki/OpenSCAD_User_Manual/Customizer
enum ScadParser {

    /// The default section name for parameters declared before any group header.
    static let defaultGroup = "Parameters"
    /// A group named "Hidden" suppresses its parameters from the customizer UI.
    static let hiddenGroup = "Hidden"

    static func parse(_ source: String) -> [ScadParameterGroup] {
        let lines = source.components(separatedBy: "\n")
        var parameters: [ScadParameter] = []
        var currentGroup = defaultGroup
        var groupOrder: [String] = []

        for (index, rawLine) in lines.enumerated() {
            let line = Substring(rawLine)

            // Customizer only reads the leading assignment block.
            if isModuleOrFunction(line) { break }

            if let group = try? Grammar.groupHeader.parse(line) {
                currentGroup = group.trimmingCharacters(in: .whitespaces)
                continue
            }

            if currentGroup == hiddenGroup { continue }

            guard let assignment = try? Grammar.assignment.parse(line),
                  let value = parseValue(assignment.rhs) else { continue }

            let control = makeControl(annotation: annotation(in: assignment.trailing), value: value)

            if !groupOrder.contains(currentGroup) { groupOrder.append(currentGroup) }
            parameters.append(
                ScadParameter(
                    name: assignment.name,
                    value: value,
                    control: control,
                    group: currentGroup,
                    lineIndex: index,
                    indent: assignment.indent,
                    trailingComment: assignment.trailing
                )
            )
        }

        return groupOrder.map { name in
            ScadParameterGroup(name: name, parameters: parameters.filter { $0.group == name })
        }
    }

    // MARK: - Value parsing

    /// Parses a right-hand side into a simple literal, or nil for expressions /
    /// vectors / anything not directly customizable.
    static func parseValue(_ raw: Substring) -> ScadValue? {
        var sub = Substring(raw.trimmingCharacters(in: .whitespaces))
        guard let value = try? Grammar.value.parse(&sub), sub.isEmpty else { return nil }
        return value
    }

    // MARK: - Annotation → control

    /// Extracts the text inside the first `[ ]` of a trailing comment, if present.
    static func annotation(in comment: String) -> String? {
        var sub = Substring(comment)
        return try? Grammar.bracket.parse(&sub)
    }

    static func makeControl(annotation: String?, value: ScadValue) -> ScadControl {
        guard let annotation, !annotation.trimmingCharacters(in: .whitespaces).isEmpty else {
            return naturalControl(value)
        }

        // A comma means an explicit list of options → dropdown.
        if annotation.contains(",") {
            return parseChoice(annotation, value: value)
        }

        // Otherwise it may be a range: min:max or min:step:max.
        var sub = Substring(annotation.trimmingCharacters(in: .whitespaces))
        if let range = try? Grammar.range.parse(&sub), sub.isEmpty {
            return .slider(min: range.min, max: range.max, step: range.step)
        }

        // A single-token bracket (e.g. maxlength `[12]`) → natural control.
        return naturalControl(value)
    }

    private static func parseChoice(_ annotation: String, value: ScadValue) -> ScadControl {
        var sub = Substring(annotation)
        guard let options = try? Grammar.optionList.parse(&sub), !options.isEmpty else {
            return naturalControl(value)
        }

        let labels = options.map { $0.label ?? stripQuotes($0.value) }
        let numbers = options.compactMap { Double($0.value) }

        if case .number = value, numbers.count == options.count {
            return .numberChoice(options: numbers, labels: labels)
        }
        return .stringChoice(options: options.map { stripQuotes($0.value) }, labels: labels)
    }

    private static func naturalControl(_ value: ScadValue) -> ScadControl {
        switch value {
        case .bool: return .toggle
        case .string: return .text
        case .number: return .number
        }
    }

    // MARK: - Small helpers

    private static func isModuleOrFunction(_ line: Substring) -> Bool {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        return trimmed.hasPrefix("module ") || trimmed.hasPrefix("module(")
            || trimmed.hasPrefix("function ") || trimmed.hasPrefix("function(")
    }

    private static func stripQuotes(_ s: String) -> String {
        guard s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 else { return s }
        return String(s.dropFirst().dropLast())
    }

    /// A slider with only `min:max` steps by 1 for integer bounds, otherwise in
    /// ~100 increments across the range.
    static func defaultStep(min: Double, max: Double) -> Double {
        let isInteger = min.rounded() == min && max.rounded() == max
        if isInteger { return 1 }
        let span = abs(max - min)
        return span > 0 ? span / 100 : 0.01
    }
}

// MARK: - Grammar

/// The `swift-parsing` grammar for the customizer subset. Each parser operates
/// on a single `Substring` line (or fragment) at a time.
private enum Grammar {

    struct Assignment {
        let indent: String
        let name: String
        let rhs: Substring
        let trailing: String
    }

    struct Option {
        let value: String
        let label: String?
    }

    struct Range {
        let min: Double
        let max: Double
        let step: Double
    }

    // A line that is only a `/* [Group Name] */` comment.
    static let groupHeader = Parse(input: Substring.self) {
        Whitespace()
        "/*"
        Whitespace()
        "["
        PrefixUpTo("]").map(String.init)
        "]"
        Whitespace()
        "*/"
        Whitespace()
    }

    // An identifier: one or more identifier characters.
    static let identifier = Prefix<Substring>(1...) {
        $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$"
    }.map(String.init)

    // (indent)(name) = (rhs) ; (optional trailing comment)
    static let assignment = Parse(input: Substring.self) {
        Prefix<Substring> { $0 == " " || $0 == "\t" }.map(String.init)
        identifier
        Whitespace()
        "="
        Whitespace()
        PrefixUpTo(";")
        ";"
        trailingComment
    }.map { indent, name, rhs, trailing in
        Assignment(indent: indent, name: name, rhs: rhs, trailing: trailing)
    }

    // Everything after the terminating `;` — an optional line/block comment.
    static let trailingComment = Parse(input: Substring.self) {
        Whitespace()
        Optionally {
            OneOf {
                Parse { "//"; Rest<Substring>() }.map { "//" + String($0) }
                Parse { "/*"; PrefixUpTo("*/").map(String.init); "*/" }.map { "/*" + $0 + "*/" }
            }
        }
        Whitespace()
    }.map { comment in comment ?? "" }

    // A simple literal value.
    static let value = OneOf {
        "true".map { ScadValue.bool(true) }
        "false".map { ScadValue.bool(false) }
        Parse {
            "\""
            Prefix { $0 != "\"" }.map(String.init)
            "\""
        }.map { ScadValue.string(unescape($0)) }
        Double.parser().map { ScadValue.number($0) }
    }

    // The text inside the first `[ ]` of a comment.
    static let bracket = Parse(input: Substring.self) {
        Skip { PrefixUpTo("[") }
        "["
        PrefixUpTo("]").map(String.init)
        "]"
    }

    // min:max  or  min:step:max
    static let range = Parse(input: Substring.self) {
        Double.parser()
        Whitespace()
        ":"
        Whitespace()
        Double.parser()
        Optionally {
            Whitespace()
            ":"
            Whitespace()
            Double.parser()
        }
    }.map { a, b, c in
        if let c {
            return Range(min: a, max: c, step: abs(b))
        }
        return Range(min: a, max: b, step: ScadParser.defaultStep(min: a, max: b))
    }

    // A single `value` or `value:Label` option. Type-erased to keep the
    // enclosing `Many` builder cheap for the type-checker.
    static let option: AnyParser<Substring, Option> = Parse(input: Substring.self) {
        Prefix { $0 != "," && $0 != ":" }.map(String.init)
        Optionally {
            Parse(input: Substring.self) {
                ":"
                Prefix { $0 != "," }.map(String.init)
            }
        }
    }
    .map { value, label in
        Option(
            value: value.trimmingCharacters(in: .whitespaces),
            label: label.map { $0.trimmingCharacters(in: .whitespaces) }
        )
    }
    .eraseToAnyParser()

    // A comma-separated list of options.
    static let optionList = Many { option } separator: { "," }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\\"", with: "\"")
         .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
