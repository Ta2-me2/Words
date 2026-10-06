import SwiftUI

/// The window: where you are on the left, what you are looking at on the right,
/// and everything that is presented over it.
struct RootView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AppClock.self) private var clock

    var body: some View {
        @Bindable var router = router

        NavigationSplitView {
            Sidebar()
        } detail: {
            detail
        }
        .task {
            await store.load()
            router.restoreSelection(in: store.library)
            // Only once the library has really been read: a library that failed
            // to open has no languages in it, and every game's progress would
            // look orphaned.
            if store.loadState == .ready {
                WortfallHost.shared.pruneOrphans(keeping: Set(store.library.profiles.map(\.id)))
            }
            clock.start()
            Speaker.warmUp()

        }
        .sheet(item: $router.sheet) { route in
            sheet(for: route)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.loadState {
        case .loading:
            LibraryLoadingState()

        case .failed(let message):
            LibraryFailureState(message: message) {
                Task { await store.load() }
            }

        case .ready:
            if let profile = store.library.profile(id: router.profileID) {
                section(for: profile)
            } else {
                LibraryEmptyState(
                    title: "No Languages",
                    message: "Add the language you are learning, and the language you want its words explained in.",
                    symbol: "character.book.closed",
                    actionTitle: "Add Language"
                ) {
                    router.newLanguage()
                }
            }
        }
    }

    @ViewBuilder
    private func section(for profile: LanguageProfile) -> some View {
        switch router.section {
        case .home:
            HomeView(profile: profile)

        case .add:
            AddWordsView(profile: profile)
                // The screen keeps its own draft, and a draft belongs to one
                // language.
                .id(profile.id)

        case .library:
            LibraryView(profile: profile, deck: store.library.deck(id: router.deckID))

        case .statistics:
            StatisticsView(profile: profile)

        case .games:
            GamesView(profile: profile)
                // A game and its progress belong to one language; switching
                // language must not carry a run, or its callbacks, across.
                .id(profile.id)
        }
    }

    @ViewBuilder
    private func sheet(for route: SheetRoute) -> some View {
        switch route {
        case .newLanguage:
            LanguageEditor(mode: .add)

        case .editLanguage(let id):
            if let profile = store.library.profile(id: id) {
                LanguageEditor(mode: .edit(profile))
            }

        case .editWord(let entryID):
            if let entry = store.library.entry(id: entryID),
               let profile = store.library.profile(id: entry.profileID) {
                WordEditor(entry: entry, profile: profile)
            }

        case .matchAudio(let profileID):
            if let profile = store.library.profile(id: profileID) {
                AudioMatchSheet(profile: profile)
            }

        case .newDeck(let profileID, let parentID):
            DeckEditor(mode: .add(profileID: profileID, parentID: parentID))

        case .editDeck(let deckID):
            if let deck = store.library.deck(id: deckID) {
                DeckEditor(mode: .edit(deck))
            }

        case .study(let profileID, let deckID, let mode):
            if let profile = store.library.profile(id: profileID) {
                StudySessionView(profile: profile, deck: store.library.deck(id: deckID), mode: mode)
            }

        case .studyMore(let profileID, let deckID):
            if let profile = store.library.profile(id: profileID) {
                StudyMoreSheet(profile: profile, deck: store.library.deck(id: deckID))
            }
        }
    }
}
