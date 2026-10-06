import AppKit
import SwiftUI

/// The well an icon is chosen in: a square showing the current icon, and a
/// popover with the choice behind it.
///
/// Two kinds of choice, side by side, because they answer two different wishes.
/// A symbol belongs to the app and to the Mac — it tints with the sidebar and
/// never looks out of place. An emoji belongs to the learner — 🇩🇪 for a
/// country, 🍳 for a kitchen — and no set of symbols could list them all, which
/// is why the emoji side also takes anything typed or picked from the Mac's own
/// Emoji & Symbols window.
struct DeckIconPicker: View {
    @Binding var icon: DeckIcon

    /// The language the deck is in, whose flags are the first emoji offered.
    let languageCode: String

    var size: CGFloat = 40

    @State private var isPicking = false

    var body: some View {
        Button {
            isPicking = true
        } label: {
            DeckIconView(icon: icon)
                .font(.system(size: size * 0.5))
                .foregroundStyle(Palette.selection)
                .frame(width: size, height: size)
                .background(Palette.subtleFill, in: .rect(cornerRadius: size * 0.24, style: .continuous))
                .contentShape(.rect(cornerRadius: size * 0.24, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Choose an icon")
        .accessibilityLabel("Icon")
        .popover(isPresented: $isPicking, arrowEdge: .bottom) {
            DeckIconChoices(icon: $icon, languageCode: languageCode) { isPicking = false }
        }
    }
}

/// What is behind the well.
private struct DeckIconChoices: View {
    @Binding var icon: DeckIcon
    let languageCode: String
    let close: () -> Void

    private enum Kind: String, CaseIterable, Identifiable {
        case symbols = "Symbols"
        case emoji = "Emoji"
        var id: String { rawValue }
    }

    @State private var kind: Kind
    @State private var typed = ""
    @FocusState private var isTyping: Bool

    init(icon: Binding<DeckIcon>, languageCode: String, close: @escaping () -> Void) {
        _icon = icon
        self.languageCode = languageCode
        self.close = close
        // It opens on whichever side the current icon came from.
        if case .emoji = icon.wrappedValue {
            _kind = State(initialValue: .emoji)
        } else {
            _kind = State(initialValue: .symbols)
        }
    }

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 4), count: 9)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Kind", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    switch kind {
                    case .symbols:
                        ForEach(Self.symbols, id: \.self) { name in
                            cell(.symbol(name))
                        }
                    case .emoji:
                        ForEach(emoji, id: \.self) { emoji in
                            cell(.emoji(emoji))
                        }
                    }
                }
                .padding(2)
            }
            .frame(height: 176)

            if kind == .emoji {
                HStack(spacing: 8) {
                    TextField("Emoji", text: $typed, prompt: Text("Or type one"))
                        .textFieldStyle(.roundedBorder)
                        .focused($isTyping)
                        .frame(width: 110)
                        .onChange(of: typed) {
                            guard let chosen = DeckIcon.emoji(in: typed) else { return }
                            icon = chosen
                            typed = ""
                        }

                    Button("Emoji & Symbols…") {
                        // The Mac's own window types into whatever has the
                        // keyboard, so the field is given it first.
                        isTyping = true
                        NSApp.orderFrontCharacterPalette(nil)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 9 * 30 + 8 * 4 + 28)
    }

    private func cell(_ choice: DeckIcon) -> some View {
        let isSelected = choice == icon
        return Button {
            icon = choice
            close()
        } label: {
            DeckIconView(icon: choice)
                .font(.system(size: 15))
                .frame(width: 30, height: 30)
                .foregroundStyle(isSelected ? Palette.selection : Palette.primaryText)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                        .fill(isSelected ? Palette.selection.opacity(0.16) : .clear)
                )
                .contentShape(.rect(cornerRadius: Metrics.smallRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The language's own flags first: a deck named after a country is the
    /// likeliest reason to reach for an emoji at all.
    private var emoji: [String] {
        let flags = LanguageCatalog.flags(for: languageCode)
        return flags + Self.emoji.filter { !flags.contains($0) }
    }

    /// Things a vocabulary is divided into: study, home, food, town, travel,
    /// nature, people and body, work, leisure. Checked against the system when
    /// they were chosen — a name that is not a symbol draws nothing.
    static let symbols = [
        "rectangle.stack", "books.vertical", "book.closed", "text.book.closed", "character.book.closed",
        "graduationcap", "pencil.and.scribble", "text.bubble", "bubble.left.and.bubble.right",
        "quote.bubble", "abc", "globe.europe.africa", "map", "flag", "lightbulb", "brain",
        "house", "building.2", "fork.knife", "cup.and.saucer", "cart", "bag", "tshirt", "gift",
        "briefcase", "desktopcomputer", "phone", "envelope", "calendar", "clock",
        "car", "tram", "airplane", "bicycle", "suitcase", "mountain.2", "tree", "leaf",
        "sun.max", "cloud.rain", "snowflake", "drop", "flame", "pawprint",
        "heart", "person.2", "figure.walk", "figure.run", "dumbbell", "sportscourt",
        "stethoscope", "cross.case", "pills",
        "music.note", "film", "theatermasks", "gamecontroller", "paintpalette", "camera",
        "hammer", "wrench.and.screwdriver", "puzzlepiece", "star", "sparkles", "bolt",
        "number", "list.bullet", "checkmark.seal",
    ]

    static let emoji = [
        "📚", "📖", "✏️", "🎓", "🧠", "💡", "🗣️", "💬", "🔤",
        "🏠", "🍎", "🍽️", "☕", "🛒", "👕", "🎁", "💼", "💻",
        "📱", "✉️", "📅", "⏰", "🚗", "🚆", "✈️", "🚲", "🧳",
        "🏔️", "🌳", "🌿", "☀️", "🌧️", "❄️", "🔥", "🐶", "❤️",
        "👥", "🏃", "🏋️", "⚽", "🩺", "💊", "🎵", "🎬", "🎭",
        "🎮", "🎨", "📷", "🔧", "🧩", "⭐", "✨", "🔢", "✅",
    ]
}
