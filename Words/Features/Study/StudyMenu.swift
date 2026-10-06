import SwiftUI

/// The ways into a sitting, gathered in one menu so that Home and the Library
/// offer exactly the same ones.
///
/// The main button always does the ordinary thing — today's cards, in the scope
/// you are looking at. Everything else is behind the arrow: another deck, or
/// practice that changes nothing.
struct StudyMenuContent: View {
    let profile: LanguageProfile
    let deck: Deck?

    /// Passed in rather than read from the environment: menu content is built
    /// in a hosting context of its own, and an environment object that does not
    /// reach it would be a crash instead of a missing menu.
    let store: LibraryStore
    let router: Router
    let clock: AppClock

    var body: some View {
        // Always in the menu, so it is where the learner remembers it being;
        // only usable once the day's cards are done. Before that, "more" would
        // be a way of skipping the words that are actually due.
        Section {
            Button("I Want More…", systemImage: "plus.circle") {
                router.studyMore(deckID: deck?.id)
            }
            .disabled(!canAskForMore)
        }

        if deck == nil, !decks.isEmpty {
            Section("Review a Deck") {
                ForEach(decks) { deck in
                    Button(label(for: deck)) { router.startStudy(deckID: deck.id) }
                }
            }
        }

        // Flat, not nested. Every way of practising is one press away: a menu
        // inside a menu makes the learner hunt for something they already know
        // the name of.
        Section(deck.map { "Practice \(store.library.path(of: $0))" } ?? "Practice") {
            Button("Today's Cards Again", systemImage: "arrow.counterclockwise") {
                router.startStudy(deckID: deck?.id, mode: .practiceToday)
            }
            .disabled(practiceCount == 0)
        }

        Section("Endless Practice") {
            ForEach(StudyQueue.PracticePool.allCases) { pool in
                Button(pool.title, systemImage: pool.symbol) {
                    router.startStudy(deckID: deck?.id, mode: .endless(pool))
                }
            }
        }
    }

    private var canAskForMore: Bool {
        store.library.canStudyMore(for: profile.id, deckID: deck?.id, asOf: clock.now)
    }

    private var decks: [Deck] {
        store.library.decks(in: profile.id)
    }

    private var practiceCount: Int {
        store.library.practiceQueue(for: profile.id, deckID: deck?.id, asOf: clock.now).count
    }

    /// "Serials · 12 ready", or just the name when there is nothing waiting —
    /// and "Germany › A1" for a subdeck, listed straight after its deck.
    private func label(for deck: Deck) -> String {
        let name = store.library.path(of: deck)
        let counts = store.library.counts(for: profile.id, deckID: deck.id, asOf: clock.now)
        guard counts.total > 0 else { return name }
        return "\(name) · \(counts.total) ready"
    }
}

/// Which way round the language's cards are asked, remembered on the language.
///
/// Written straight to the language rather than through a binding to a copy
/// of it: the profile handed in may be a moment old, and a copy saved back
/// would undo whatever changed in that moment.
struct DirectionPicker: View {
    let profile: LanguageProfile
    let store: LibraryStore

    var body: some View {
        Picker("Cards", selection: Binding(
            get: { store.library.profile(id: profile.id)?.studyDirection ?? profile.studyDirection },
            set: { choice in
                guard var current = store.library.profile(id: profile.id), current.studyDirection != choice else { return }
                current.studyDirection = choice
                store.save(current)
            }
        )) {
            ForEach(StudyDirection.allCases) { direction in
                Text(direction.title).tag(direction)
            }
        }
    }
}
