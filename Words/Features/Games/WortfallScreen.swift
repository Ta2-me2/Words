import SwiftUI
import WortfallCore
import WortfallKit

/// WordFall, played with this language's words, in the window's main area.
///
/// Named after the package it wraps: the game was renamed WordFall in 2.2.2,
/// but its modules and types kept the name `Wortfall`, and so does this.
///
/// The game brings its own menu, levels and statistics — and, since 2.2.2, its
/// own loading screen while a level is built. What the app supplies
/// is the vocabulary — the whole language and every deck big enough to play —
/// and a place to keep what the game learns, one file per language.
struct WortfallScreen: View {
    let profile: LanguageProfile
    let close: () -> Void

    @Environment(LibraryStore.self) private var store

    @State private var progress: WortfallProgress?
    @State private var failure: String?
    @State private var deckID: String?

    var body: some View {
        Group {
            if let progress {
                WortfallLibraryView(
                    libraryID: profile.id.uuidString,
                    decks: decks,
                    selectedDeckID: $deckID,
                    progress: progress
                )
            } else if let failure {
                ContentUnavailableView {
                    Label("\(GameKind.wordFall.title) Couldn’t Open", systemImage: "exclamationmark.triangle")
                } description: {
                    // The file is kept exactly as it is: the game refuses to
                    // replace progress it cannot read, and so does the app.
                    Text(failure)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(GameKind.wordFall.title)
        .navigationSubtitle(profile.languagePair)
        .toolbar {
            ToolbarItem(id: "games.back", placement: .navigation) {
                Button(action: close) {
                    Label("Games", systemImage: "chevron.backward")
                }
                .help("Back to Games")
            }
        }
        .task { await load() }
        .onChange(of: deckID) { WortfallHost.shared.selectedDeck[profile.id] = deckID }
        .onDisappear {
            let id = profile.id
            Task { await WortfallHost.shared.flush(id) }
        }
    }

    /// The language's collections, in the shape the game asks for.
    private var decks: [WortfallDeck] {
        GameVocabulary.collections(for: profile, in: store.library).map { collection in
            WortfallDeck(
                id: collection.id,
                name: collection.name,
                cards: collection.words.map {
                    VocabularyCard(id: $0.id, word: $0.word, translation: $0.translation)
                }
            )
        }
    }

    private func load() async {
        failure = nil

        // Open on the collection last played, or on the whole language when
        // that one has gone or has grown too small.
        let available = decks.map(\.id)
        let remembered = WortfallHost.shared.selectedDeck[profile.id]
        deckID = remembered.flatMap { available.contains($0) ? $0 : nil } ?? available.first

        do {
            progress = try await WortfallHost.shared.progress(for: profile.id)
        } catch {
            failure = error.localizedDescription
        }
    }
}
