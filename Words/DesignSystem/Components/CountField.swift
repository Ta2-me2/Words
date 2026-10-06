import SwiftUI

/// A whole number, typed in.
///
/// Not a stepper: nobody wants to click fifteen times to get from twenty to
/// thirty-five, and the number a learner has in mind is rarely a multiple of
/// five. The field holds text and cleans it as it is written, so the value is
/// already right when a button is pressed — a formatted field only commits when
/// it loses focus, and a sheet can be saved before that happens.
///
/// It writes no state of its own while it is on screen: the text is seeded once
/// and every later change goes through the binding. Anything else — a value
/// copied in when the field appears, a change watched from outside — rebuilds
/// the field under the pointer, and a field rebuilt while it holds the keyboard
/// takes the form's scroll position with it.
struct CountField: View {

    private let value: Binding<Int?>
    private let range: ClosedRange<Int>
    private let placeholder: String

    /// What an empty field means: nothing for a number that may be left out,
    /// the bottom of the range for one that must always be there.
    private let emptyValue: Int?

    @State private var text: String

    /// A number that must always be there.
    init(value: Binding<Int>, in range: ClosedRange<Int>) {
        self.value = Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = $0 ?? range.lowerBound }
        )
        self.range = range
        self.placeholder = String(range.lowerBound)
        self.emptyValue = range.lowerBound
        _text = State(initialValue: String(value.wrappedValue))
    }

    /// A number that may be left out. Empty means the placeholder is the
    /// value — "No limit", say.
    init(value: Binding<Int?>, in range: ClosedRange<Int>, placeholder: String) {
        self.value = value
        self.range = range
        self.placeholder = placeholder
        self.emptyValue = nil
        _text = State(initialValue: value.wrappedValue.map(String.init) ?? "")
    }

    var body: some View {
        TextField("", text: field, prompt: Text(placeholder))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 76)
    }

    /// Cleaned on the way in rather than afterwards. Writing the text again
    /// from inside its own change would rebuild the field mid-edit; one
    /// assignment, whatever was typed, keeps that from happening.
    private var field: Binding<String> {
        Binding(
            get: { text },
            set: { proposed in
                var digits = String(proposed.filter { $0.isASCII && $0.isNumber }.prefix(5))
                while digits.count > 1, digits.hasPrefix("0") { digits.removeFirst() }

                guard let number = Int(digits) else {
                    // Nothing that counts as a number: the field is empty, and
                    // what that means is the caller's to say.
                    text = ""
                    value.wrappedValue = emptyValue
                    return
                }

                let clamped = min(max(number, range.lowerBound), range.upperBound)
                text = String(clamped)
                value.wrappedValue = clamped
            }
        )
    }
}
