import SwiftUI
import UIKit

/// A full-source `.scad` editor: a `UITextView` bound to the document's `source`,
/// with OpenSCAD syntax highlighting. Typing re-derives the parameters and
/// re-renders through the same pipeline the parameter controls use.
///
/// Backed by UIKit because SwiftUI's `TextEditor` can't apply per-token colors.
/// Colors and chrome use semantic/dynamic colors, so the editor follows the
/// device's light/dark appearance.
struct SourceEditorView: UIViewRepresentable {
    @Binding var text: String
    /// Reports first-responder changes so the container can give the editor more
    /// room (collapsing the preview) while the keyboard is up.
    var onFocusChange: (Bool) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no
        textView.backgroundColor = .secondarySystemBackground
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.alwaysBounceVertical = true
        textView.typingAttributes = SyntaxHighlighter.baseAttributes

        let storage = NSMutableAttributedString(string: text)
        SyntaxHighlighter.apply(to: storage)
        textView.attributedText = storage

        textView.inputAccessoryView = context.coordinator.makeToolbar()
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        // Only rewrite when the source changed underneath us (e.g. a parameter
        // edit made in Customize mode), never mid-keystroke.
        if textView.text != text {
            let selected = textView.selectedRange
            SyntaxHighlighter.rehighlight(textView.textStorage, replacingWith: text)
            textView.selectedRange = clamp(selected, to: textView.textStorage.length)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(range.location, length)
        return NSRange(location: location, length: min(range.length, length - location))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SourceEditorView
        weak var textView: UITextView?

        init(_ parent: SourceEditorView) { self.parent = parent }

        func makeToolbar() -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            toolbar.items = [
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissKeyboard))
            ]
            return toolbar
        }

        @objc private func dismissKeyboard() {
            textView?.resignFirstResponder()
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text

            let selected = textView.selectedRange
            SyntaxHighlighter.apply(to: textView.textStorage)
            textView.selectedRange = selected
        }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocusChange(true) }
        func textViewDidEndEditing(_ textView: UITextView) { parent.onFocusChange(false) }
    }
}

/// Lightweight OpenSCAD syntax highlighter. Runs a few regex passes over the text
/// and applies foreground colors to `NSTextStorage`. Highlighting is a display
/// concern (distinct from the semantic parameter parser), so regex is the right
/// tool here; precedence is enforced by pass order — comments win over strings,
/// which win over numbers and identifiers.
enum SyntaxHighlighter {
    static let font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: UIColor.label]
    }

    /// Replace the storage's characters and re-highlight in one pass.
    static func rehighlight(_ storage: NSTextStorage, replacingWith text: String) {
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        apply(to: storage)
    }

    /// Re-color the whole document in place (attributes only — never characters).
    static func apply(to storage: NSMutableAttributedString) {
        let text = storage.string
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)

        identifier.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let range = match?.range else { return }
            let word = ns.substring(with: range)
            if keywords.contains(word) {
                storage.addAttribute(.foregroundColor, value: Theme.keyword, range: range)
            } else if builtins.contains(word) {
                storage.addAttribute(.foregroundColor, value: Theme.builtin, range: range)
            }
        }
        color(number, in: text, range: full, with: Theme.number, on: storage)
        color(stringLiteral, in: text, range: full, with: Theme.string, on: storage)
        color(blockComment, in: text, range: full, with: Theme.comment, on: storage)
        color(lineComment, in: text, range: full, with: Theme.comment, on: storage)

        storage.endEditing()
    }

    private static func color(
        _ regex: NSRegularExpression,
        in text: String,
        range: NSRange,
        with color: UIColor,
        on storage: NSMutableAttributedString
    ) {
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let range = match?.range else { return }
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }
    }

    // MARK: - Token vocabulary

    private static let keywords: Set<String> = [
        "module", "function", "if", "else", "for", "let", "each",
        "true", "false", "undef", "include", "use", "echo", "assert"
    ]

    private static let builtins: Set<String> = [
        "cube", "sphere", "cylinder", "polyhedron", "square", "circle", "polygon",
        "text", "linear_extrude", "rotate_extrude", "translate", "rotate", "scale",
        "resize", "mirror", "multmatrix", "color", "offset", "hull", "minkowski",
        "union", "difference", "intersection", "render", "children", "projection",
        "surface", "import", "sin", "cos", "tan", "asin", "acos", "atan", "atan2",
        "abs", "ceil", "floor", "round", "ln", "log", "pow", "sqrt", "exp", "min",
        "max", "norm", "cross", "concat", "lookup", "str", "chr", "ord", "len",
        "search", "version", "rands", "sign"
    ]

    // MARK: - Patterns

    private static let identifier = regex("[A-Za-z_][A-Za-z0-9_]*")
    private static let number = regex("(?<![A-Za-z0-9_.])\\d+(?:\\.\\d+)?")
    private static let stringLiteral = regex("\"(?:\\\\.|[^\"\\\\\\n])*\"")
    private static let lineComment = regex("//[^\\n]*")
    private static let blockComment = regex("/\\*.*?\\*/", options: [.dotMatchesLineSeparators])

    private static func regex(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        // Patterns are compile-time constants; a bad one is a programmer error.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    // MARK: - Colors (GitHub-style, adapting to light/dark)

    private enum Theme {
        static let keyword = dynamic(light: 0xCF222E, dark: 0xFF7B72)
        static let builtin = dynamic(light: 0x8250DF, dark: 0xD2A8FF)
        static let number = dynamic(light: 0x0550AE, dark: 0x79C0FF)
        static let string = dynamic(light: 0x0A3069, dark: 0xA5D6FF)
        static let comment = dynamic(light: 0x6E7781, dark: 0x8B949E)

        static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
            UIColor { traits in
                UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
            }
        }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
