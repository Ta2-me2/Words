import SwiftUI

/// The shelf of games — and the game itself, when one is being played.
///
/// A game is played where every other screen is: in the window's main area,
/// beside the sidebar. Hide the sidebar or make the window bigger and the game
/// grows with it. It is part of the app, not a second app on top of it.
struct GamesView: View {
    let profile: LanguageProfile

    @Environment(LibraryStore.self) private var store

    @State private var playing: GameKind?

    var body: some View {
        if let playing {
            switch playing {
            case .wordFall:
                WortfallScreen(profile: profile) { self.playing = nil }
            }
        } else {
            shelf
        }
    }

    private var shelf: some View {
        let collections = GameVocabulary.collections(for: profile, in: store.library)
        // Named by where they sit, so "A1" says which A1.
        let tooSmall = GameVocabulary.tooSmall(for: profile, in: store.library).map { store.library.path(of: $0) }

        return ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(GameKind.allCases) { game in
                    GameTile(game: game, collections: collections, tooSmall: tooSmall) {
                        playing = game
                    }
                }
            }
            .frame(maxWidth: Metrics.pageWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .pageInsets()
        }
        .navigationTitle(AppSection.games.title)
        .navigationSubtitle(profile.languagePair)
    }
}

/// One game on the shelf: what it is, what it would be played with, and the
/// button that starts it.
private struct GameTile: View {
    let game: GameKind
    let collections: [GameCollection]
    let tooSmall: [String]
    let play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Image(game.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(game.title)
                        .font(.title3.weight(.semibold))
                    Text(game.summary)
                        .font(.callout)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            HStack(alignment: .center, spacing: 8) {
                Text(status)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)

                Spacer(minLength: 8)

                Button("Play", action: play)
                    .buttonStyle(.borderedProminent)
                    .disabled(collections.isEmpty)
            }

            if !tooSmall.isEmpty {
                Text(tooSmallNote)
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Metrics.cardPadding)
        .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.separator)
        }
    }

    /// "42 words · 3 decks", or what is missing before it can be played.
    private var status: String {
        guard let everything = collections.first(where: { $0.deckID == nil }) else {
            return "Needs at least \(GameVocabulary.minimumWords) words"
        }
        let decks = collections.count - 1
        let words = "\(everything.words.count) words"
        return decks == 0 ? words : "\(words) · \(decks) \(decks == 1 ? "deck" : "decks")"
    }

    private var tooSmallNote: String {
        let reason = "a deck needs at least \(GameVocabulary.minimumWords) words to be played."
        if tooSmall.count == 1, let name = tooSmall.first {
            return "“\(name)” isn’t offered: \(reason)"
        }
        return "\(tooSmall.count) decks aren’t offered: \(reason)"
    }
}
