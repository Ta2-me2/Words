import AppKit
import Observation
import SwiftUI

/// The boxes of one phrase: who they are, which one is being typed into, and
/// how to move the typing from one to the next.
///
/// A box has to be able to hand the keyboard to its neighbour *inside* the
/// keystroke that asked for it. SwiftUI's own focus cannot: `@FocusState` is
/// applied on the next pass through the view tree, and a space typed quickly
/// is followed by its letter before that pass happens — which is how
/// "Das Haus ist sehr gross" once came out as "Das | Hausi | sts | ehrg |
/// ross". `makeFirstResponder` is synchronous, so by the time the next key
/// event is dispatched the next box is already the one being typed into.
@Observable
@MainActor
final class WordBoxes {

    /// The box being typed into, for drawing the one that is.
    private(set) var active: Int?

    @ObservationIgnored private var fields: [Int: NSTextField] = [:]

    var count: Int { fields.count }

    func register(_ field: NSTextField, at index: Int) {
        fields[index] = field
    }

    /// Forgets a box, but only if it is still the one that was registered: a
    /// row rebuilt for the next phrase registers the new box before the old
    /// one is taken apart.
    func forget(_ index: Int, if field: NSTextField) {
        guard fields[index] === field else { return }
        fields[index] = nil
        if active == index { active = nil }
    }

    func began(_ index: Int) { active = index }

    /// Hands the keyboard back to the window: once an answer has been given,
    /// Return belongs to the buttons again.
    func release() {
        guard let window = fields.values.first(where: { $0.window != nil })?.window else { return }
        window.makeFirstResponder(nil)
    }

    func ended(_ index: Int) {
        if active == index { active = nil }
    }

    /// Moves the typing to another box, now rather than later. Returns whether
    /// there was a box there to move to.
    @discardableResult
    func focus(_ index: Int, caretAtEnd: Bool = false) -> Bool {
        guard let field = fields[index], let window = field.window else { return false }
        guard window.makeFirstResponder(field) else { return false }
        if let editor = field.currentEditor() {
            let end = (field.stringValue as NSString).length
            editor.selectedRange = NSRange(location: caretAtEnd ? end : 0, length: 0)
        }
        return true
    }
}

/// One word's box.
///
/// An AppKit field rather than a `TextField`, for the one reason above. What it
/// looks like is still SwiftUI's: the field itself is borderless and draws no
/// background, and the box around it is drawn by the view that places it.
struct WordBoxField: NSViewRepresentable {
    @Binding var text: String
    let index: Int
    /// How many boxes the phrase has, so that the last of them knows it is the
    /// last.
    let count: Int
    let boxes: WordBoxes

    /// More than one word arriving at once: a space typed between two words,
    /// or a whole phrase pasted in. Given the words and the box they start in.
    let spill: ([String], Int) -> Void

    /// Return pressed: the answer is given.
    let submit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = .systemFont(ofSize: 19, weight: .medium)
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.allowsEditingTextAttributes = false
        field.importsGraphics = false
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        boxes.register(field, at: index)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        boxes.register(field, at: index)
        if field.stringValue != text {
            field.stringValue = text
            // A box filled from outside — the phrase shown, the next sitting
            // started — puts the cursor after what it was given rather than
            // leaving it where the last word happened to end.
            if let editor = field.currentEditor() {
                let end = (text as NSString).length
                editor.selectedRange = NSRange(location: end, length: 0)
            }
        }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.parent.boxes.forget(coordinator.parent.index, if: field)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: WordBoxField

        init(_ parent: WordBoxField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.boxes.began(parent.index)
            // A dictation is the one place in the app where the Mac must not
            // help: a word half-typed in another language is exactly what
            // autocorrect exists to replace, and replacing it would mark the
            // learner wrong for something they did not type.
            guard let editor = (notification.object as? NSTextField)?.currentEditor() as? NSTextView else { return }
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isContinuousSpellCheckingEnabled = false
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.boxes.ended(parent.index)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let value = field.stringValue

            // A space is not a letter of any word; it is the move to the next
            // box. Everything after it belongs there — which is also how a
            // phrase pasted into the first box lands a word in each.
            //
            // Except in the last box, which has nowhere to move on to: there a
            // space stays where it was typed, and the words after it are
            // marked as said after the phrase, which is what they are.
            if parent.index < parent.count - 1,
               value.contains(where: { $0 == " " || $0 == "\t" || $0.isNewline }) {
                let words = DictationText.words(of: value)
                guard !words.isEmpty else {
                    field.stringValue = ""
                    parent.text = ""
                    return
                }
                field.stringValue = words[0]
                parent.spill(words, parent.index)
                // Only once the words are in: moving first would leave this
                // box holding the whole phrase for a moment.
                let next = parent.index + words.count
                if !parent.boxes.focus(next, caretAtEnd: true) {
                    parent.boxes.focus(parent.index + words.count - 1, caretAtEnd: true)
                }
                return
            }

            parent.text = value
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let caret = textView.selectedRange()
            let length = (textView.string as NSString).length

            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                return parent.boxes.focus(parent.index + 1, caretAtEnd: true)

            case #selector(NSResponder.insertBacktab(_:)):
                return parent.boxes.focus(parent.index - 1, caretAtEnd: true)

            case #selector(NSResponder.insertNewline(_:)):
                parent.submit()
                return true

            case #selector(NSResponder.deleteBackward(_:)):
                // At the very start of a box, Backspace is how the box before
                // it is reached — the row reads as one line of text, so it
                // should behave like one.
                guard caret.location == 0, caret.length == 0 else { return false }
                return parent.boxes.focus(parent.index - 1, caretAtEnd: true)

            case #selector(NSResponder.moveLeft(_:)):
                guard caret.location == 0, caret.length == 0 else { return false }
                return parent.boxes.focus(parent.index - 1, caretAtEnd: true)

            case #selector(NSResponder.moveRight(_:)):
                guard caret.location == length, caret.length == 0 else { return false }
                return parent.boxes.focus(parent.index + 1)

            default:
                return false
            }
        }
    }
}
