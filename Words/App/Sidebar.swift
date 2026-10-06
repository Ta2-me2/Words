import SwiftUI

/// The standard macOS sidebar: which language, then where in it.
///
/// The switcher sits above the navigation rather than in it, because a language
/// is not a place you go — it is the thing every place is about.
struct Sidebar: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AppClock.self) private var clock

    @State private var decksExpanded = true

    /// Decks whose subdecks are folded away. Folded is the exception, so a
    /// subdeck made a moment ago is on screen without anybody opening anything.
    @State private var collapsedDecks: Set<UUID> = []

    @State private var pendingDeckDeletion: Deck?

    var body: some View {
        List(selection: selection) {
            Section {
                ProfileSwitcher()
                    .padding(.vertical, 2)
            }

            Section {
                row(.home, badge: todayCount)
                row(.add)
                library
                row(.statistics)
                row(.games)
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            // Beside the sidebar toggle, where the window's own controls live
            // rather than the library's.
            ToolbarItem(id: "sidebar.appearance", placement: .navigation) {
                AppearanceMenu()
            }
        }
        .navigationSplitViewColumnWidth(
            min: Metrics.sidebarMin,
            ideal: Metrics.sidebarIdeal,
            max: Metrics.sidebarMax
        )
        .alert(
            "Delete “\(pendingDeckDeletion?.displayName ?? "")”?",
            isPresented: .init(
                get: { pendingDeckDeletion != nil },
                set: { if !$0 { pendingDeckDeletion = nil } }
            ),
            presenting: pendingDeckDeletion
        ) { deck in
            let words = store.library.wordCount(inDeck: deck.id)
            if words == 0 {
                Button(deck.isSubdeck ? "Delete Subdeck" : "Delete Deck", role: .destructive) {
                    delete(deck, includingWords: false)
                }
            } else {
                // Two different things a learner can mean, and the app cannot
                // tell which from the gesture. A deck made by hand is a shelf;
                // a deck that came in as a package is the words. Asking is
                // cheaper than a hundred and sixty words left behind unfiled —
                // or a hundred and sixty words gone that were meant to stay.
                Button("Delete \(deck.isSubdeck ? "Subdeck" : "Deck") and \(wordNoun(words))", role: .destructive) {
                    delete(deck, includingWords: true)
                }
                Button(keepingTitle(for: deck)) {
                    delete(deck, includingWords: false)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { deck in
            Text(deletionMessage(for: deck))
        }
    }

    /// A sidebar that can be deselected shows an empty window; the last
    /// selection stands until another one is made.
    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { router.sidebar },
            set: { if let value = $0 { router.sidebar = value } }
        )
    }

    private var todayCount: Int {
        guard let profileID = router.profileID else { return 0 }
        return store.library.counts(for: profileID, asOf: clock.now).total
    }

    private func row(_ section: AppSection, badge: Int = 0) -> some View {
        Label(section.title, systemImage: section.symbol)
            .badge(badge)
            .tag(SidebarItem.section(section))
    }

    /// The Library, with the language's decks under it, and each deck's
    /// subdecks under that. Selecting a deck is selecting the Library with a
    /// shelf already picked out; selecting a deck with subdecks picks out all
    /// of them.
    @ViewBuilder
    private var library: some View {
        let decks = router.profileID.map { store.library.topLevelDecks(in: $0) } ?? []

        if decks.isEmpty {
            row(.library)
                .contextMenu { Button("New Deck…") { router.newDeck() } }
        } else {
            DisclosureGroup(isExpanded: $decksExpanded) {
                ForEach(decks) { deck in
                    let subdecks = store.library.subdecks(of: deck.id)

                    if subdecks.isEmpty {
                        deckRow(deck)
                    } else {
                        DisclosureGroup(isExpanded: expansion(of: deck)) {
                            ForEach(subdecks) { subdeck in
                                deckRow(subdeck)
                            }
                        } label: {
                            deckRow(deck)
                        }
                    }
                }
            } label: {
                row(.library)
                    .contextMenu { Button("New Deck…") { router.newDeck() } }
            }
        }
    }

    private func deckRow(_ deck: Deck) -> some View {
        DeckLabel(title: deck.displayName, icon: deck.displayIcon)
            .badge(deckCount(deck))
            .tag(SidebarItem.deck(deck.id))
            .contextMenu {
                // Only a deck at the top can hold others, so only it is offered
                // the way to make one.
                if !deck.isSubdeck {
                    Button("New Subdeck…") { router.newDeck(inside: deck.id) }
                    Divider()
                }
                Button(deck.isSubdeck ? "Edit Subdeck…" : "Edit Deck…") { router.editDeck(deck.id) }
                Divider()
                Button(deck.isSubdeck ? "Delete Subdeck…" : "Delete Deck…", role: .destructive) {
                    pendingDeckDeletion = deck
                }
            }
    }

    private func expansion(of deck: Deck) -> Binding<Bool> {
        Binding(
            get: { !collapsedDecks.contains(deck.id) },
            set: { isExpanded in
                if isExpanded { collapsedDecks.remove(deck.id) } else { collapsedDecks.insert(deck.id) }
            }
        )
    }

    private func deckCount(_ deck: Deck) -> Int {
        guard let profileID = router.profileID else { return 0 }
        return store.library.counts(for: profileID, deckID: deck.id, asOf: clock.now).total
    }

    /// What deleting a deck will do, said before it is done: which decks go
    /// with it, what the words carry, and where they can end up.
    private func deletionMessage(for deck: Deck) -> String {
        let words = store.library.wordCount(inDeck: deck.id)
        let subdecks = deck.isSubdeck ? 0 : store.library.subdecks(of: deck.id).count
        let taking = subdecks == 0 ? "" : "Its \(subdecks) \(subdecks == 1 ? "subdeck goes" : "subdecks go") with it. "

        guard words > 0 else {
            if deck.isSubdeck { return "The subdeck is empty." }
            return taking + (subdecks == 0 ? "The deck is empty." : "There are no words in them.")
        }

        let owned = mediaSummary(forDeck: deck.id)
        let holding = "It holds \(wordNoun(words).lowercased())\(owned.isEmpty ? "" : ", with \(owned)")."
        return taking + holding + " Deleted words cannot be brought back; your review history is kept either way."
    }

    /// "Keep Words in “Germany”", or "Keep Words Without a Deck".
    private func keepingTitle(for deck: Deck) -> String {
        if let parent = store.library.deck(id: deck.parentID) {
            return "Keep Words in “\(parent.displayName)”"
        }
        return "Keep Words Without a Deck"
    }

    private func wordNoun(_ count: Int) -> String {
        "\(count) \(count == 1 ? "Word" : "Words")"
    }

    /// What goes with the words besides the words: said because a deck that
    /// came from Anki is mostly recordings and photos by size, and those are
    /// the part nobody can make again by typing.
    private func mediaSummary(forDeck deckID: UUID) -> String {
        let ids = store.library.entryIDs(inDeck: deckID)
        let words = store.library.entries.filter { ids.contains($0.id) }
        let recordings = words.count { $0.audio != nil || $0.exampleAudio != nil }
        let pictures = words.count { $0.picture != nil || $0.hasAssociation }

        var parts: [String] = []
        if recordings > 0 { parts.append("\(recordings) \(recordings == 1 ? "recording" : "recordings")") }
        if pictures > 0 { parts.append("\(pictures) \(pictures == 1 ? "picture" : "pictures")") }
        return parts.joined(separator: " and ")
    }

    private func delete(_ deck: Deck, includingWords: Bool) {
        // A window showing a deck that no longer exists shows nothing; it goes
        // to where the words went instead.
        if let shown = router.deckID, store.library.deckIDs(within: deck.id).contains(shown) {
            // A subdeck's parent survives either choice.
            if let parentID = deck.parentID { router.show(deck: parentID) } else { router.show(.library) }
        }
        store.deleteDeck(id: deck.id, includingWords: includingWords)
    }
}

/// The language switcher: a flag, a name, and every other language behind it.
///
/// Small on purpose. It has to say which language is being studied without
/// being opened, and then get out of the way.
struct ProfileSwitcher: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router

    @State private var isHovering = false

    var body: some View {
        @Bindable var router = router

        Menu {
            if !store.library.profiles.isEmpty {
                Picker("Language", selection: $router.profileID) {
                    ForEach(store.library.profiles) { profile in
                        Text("\(profile.flag)  \(profile.displayName)")
                            .tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Divider()

                if let current {
                    Button("Edit \(current.displayName)…") { router.editLanguage(current.id) }
                }
            }

            Button("Add Language…") { router.newLanguage() }
        } label: {
            HStack(spacing: 9) {
                Text(current?.flag ?? "🏳️")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 1) {
                    Text(current?.displayName ?? "No Language")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(current?.languagePair ?? "Add one to begin")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(.rect(cornerRadius: Metrics.smallRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                    .fill(Palette.selection.opacity(isHovering ? 0.08 : 0))
            }
        }
        // `.button` rather than `.borderlessButton`: the borderless style draws
        // only the first element of a label and would leave the name and the
        // pair of languages off the screen.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .help("Switch language")
    }

    private var current: LanguageProfile? {
        store.library.profile(id: router.profileID)
    }
}
