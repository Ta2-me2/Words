import SwiftUI

/// The small panel that says what a drawn shape stands for.
///
/// The app draws a fair amount now — a year of days, a bar of four stages,
/// three charts — and a shape cannot be read. macOS's own tooltip would do, but
/// it waits a second, appears under the pointer rather than beside the thing,
/// and cannot be given to one part of a drawing. This appears at once, above
/// what it describes, and disappears with the pointer.
struct HoverNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(Palette.primaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: .rect(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Palette.separator)
            }
            .fixedSize()
    }
}

/// Something worth saying, and where it belongs.
struct HoverPoint: Equatable {
    var text: String
    var at: CGPoint

    init(_ text: String, at: CGPoint) {
        self.text = text
        self.at = at
    }
}

/// Which side of the point the note sits on. Above for a thing with room over
/// it, below for a thing at the top of its card.
enum HoverNoteSide {
    case above
    case below
}

private struct HoverNoteOverlay: ViewModifier {
    let note: HoverPoint?
    let side: HoverNoteSide

    @State private var size = CGSize.zero
    @State private var container = CGFloat.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { container = $0 }
            .overlay(alignment: .topLeading) {
                if let note {
                    HoverNote(text: note.text)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                        // Centred on what it describes, and never off the side
                        // of the card it sits in.
                        .offset(
                            x: min(max(0, note.at.x - size.width / 2), max(0, container - size.width)),
                            y: side == .above ? note.at.y - size.height - 6 : note.at.y + 6
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.1), value: note?.text)
    }
}

extension View {

    /// Shows a note beside a point in this view's own coordinates, while there
    /// is something to say.
    func hoverNote(_ note: HoverPoint?, side: HoverNoteSide = .above) -> some View {
        modifier(HoverNoteOverlay(note: note, side: side))
    }
}
