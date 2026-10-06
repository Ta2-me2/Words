import SwiftUI

/// A deck's icon, at the size of whatever text is around it.
///
/// A symbol takes the tint of the place it is drawn in — the accent in a
/// sidebar, white on a selected row — exactly as a system icon would. An emoji
/// is drawn as itself, because its colours are the reason it was chosen.
struct DeckIconView: View {
    let icon: DeckIcon

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
        case .emoji(let emoji):
            Text(emoji)
        }
    }
}

/// A deck's name with its icon, the way a sidebar row shows it.
struct DeckLabel: View {
    let title: String
    let icon: DeckIcon

    var body: some View {
        Label {
            Text(title)
        } icon: {
            // One width for every icon, so names line up whatever sits in
            // front of them: a mortarboard is wider than a stack of cards, and
            // a flag is wider than both.
            DeckIconView(icon: icon)
                .frame(width: 20)
        }
    }
}
