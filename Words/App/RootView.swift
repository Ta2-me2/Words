import SwiftUI

/// The window: where you are on the left, what you are looking at on the right,
/// and everything that is presented over it.
struct RootView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AppClock.self) private var clock

    var body: some View {
        @Bindable var router = router

        ZStack {
            switch opening {
            case .deciding:
                // The library has not been read yet, so it is not known which
                // of the two this is. Showing the app's own frame here is what
                // made a first launch flash a sidebar and an empty home for a
                // few frames before the introduction arrived; showing the
                // introduction's own background instead means the first frame
                // anybody sees is already the right one either way.
                IntroBackdrop()
                    .transition(.opacity)

            case .intro:
                // The first thing anybody sees, and the thing anybody sees
                // again if they ever empty the library: there is no library
                // without a language in it, so an empty one is always either
                // a beginning or a fresh start.
                IntroView(onFinished: begin)
                    .transition(.opacity)

            case .app:
                NavigationSplitView {
                    Sidebar()
                } detail: {
                    detail
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: opening)
        .task {
            await store.load()
            router.restoreSelection(in: store.library)
            // Only once the library has really been read: a library that failed
            // to open has no languages in it, and every game's progress would
            // look orphaned.
            if store.loadState == .ready {
                GameStorage.pruneOrphans(keeping: Set(store.library.profiles.map(\.id)))
            }
            clock.start()
            Speaker.warmUp()

        }
        .sheet(item: $router.sheet) { route in
            sheet(for: route)
        }
    }

    /// What the window is showing.
    private enum Opening {
        /// The library is still being read, so it is not yet known.
        case deciding
        case intro
        case app
    }

    /// Whether to open with the introduction rather than with the app.
    ///
    /// No flag written anywhere, because the library already answers it: a
    /// library with no language in it has either never been used or has just
    /// been emptied, and both want the same screen. It also means finishing
    /// the introduction is what dismisses it — the language it creates is the
    /// thing that makes the question false.
    ///
    /// Only once the file has really been read. A library that failed to open
    /// has no languages in it either, and inviting somebody to start again on
    /// top of their own words is the one unforgivable thing this screen could
    /// do.
    private var opening: Opening {
        switch store.loadState {
        case .loading:
            .deciding
        case .failed:
            // A library that failed to open has no languages in it either, and
            // inviting somebody to start again on top of their own words is
            // the one unforgivable thing this screen could do. The failure
            // belongs to the app, which can say what went wrong and offer to
            // try again.
            .app
        case .ready:
            store.library.profiles.isEmpty ? .intro : .app
        }
    }

    /// What the introduction decided, made real.
    private func begin(_ choice: IntroChoice) {
        let code: String
        switch choice {
        case .known(let known):
            code = known
        case .invented(let name, let flag):
            code = store.addCustomLanguage(name: name, flag: flag).id
        }

        let profile = store.addProfile(
            name: LanguageCatalog.name(for: code),
            learningCode: code,
            nativeCode: Self.meanings(besides: code),
            flag: choice.flag
        )
        router.profileID = profile.id
        router.show(.home)
    }

    /// The language to write meanings in: the Mac's own, unless that is the
    /// one being learned.
    private static func meanings(besides learning: String) -> String {
        let system = LanguageCatalog.systemCode
        guard system == learning else { return system }
        return learning == "en" ? "es" : "en"
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

        case .export:
            ExportView()

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
