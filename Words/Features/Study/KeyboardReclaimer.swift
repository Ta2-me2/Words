import AppKit
import SwiftUI

/// Gives the keyboard back to the window when a selected word is holding it.
///
/// A word on a card can be selected, to copy it. Selecting it makes the text
/// the window's first responder, and the text keeps that place after the
/// selection is gone — so Space, the digits and P went to a piece of text that
/// could do nothing with them, and never reached the buttons they belong to.
///
/// Before a plain key is handled, a first responder that is neither a control
/// nor somewhere to type is asked to step aside, and the key then goes where it
/// always went. A key with Command in it is left alone: ⌘C is the reason the
/// word was selected.
struct KeyboardReclaimer: NSViewRepresentable {

    func makeNSView(context: Context) -> Watcher { Watcher() }

    func updateNSView(_ nsView: Watcher, context: Context) {}

    final class Watcher: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.reclaim(for: event)
                return event
            }
        }

        private func reclaim(for event: NSEvent) {
            guard let window,
                  event.window === window,
                  event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
                  let responder = window.firstResponder as? NSView,
                  !(responder is NSControl),
                  !Self.isTypedInto(responder)
            else { return }
            window.makeFirstResponder(nil)
        }

        private static func isTypedInto(_ view: NSView) -> Bool {
            if let text = view as? NSTextView { return text.isEditable }
            if let field = view as? NSTextField { return field.isEditable }
            return false
        }
    }
}
