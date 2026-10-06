import AppKit
import SwiftUI

/// Every word in the language, or in one deck of it.
///
/// A table rather than a list of cards: a vocabulary is columns of comparable
/// facts, and sorting by when a word is next due is the fastest way to see what
/// the week looks like.
struct LibraryView: View {
    let profile: LanguageProfile
    let deck: Deck?

    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AppClock.self) private var clock
    private let speaker = Speaker.shared

    @State private var selection: Set<UUID> = []

    /// The word whose board is open. A sheet of the Library's own rather than
    /// a route through the window: drawing is a thing you do to a row.
    @State private var drawingFor: Entry?

    @State private var sort = WordSort()

    var body: some View {
        @Bindable var router = router

        content
            .navigationTitle(deck?.displayName ?? AppSection.library.title)
            .navigationSubtitle(subtitle)
            .searchable(text: $router.searchText, placement: .toolbar, prompt: "Search words")
            .toolbar {
                ToolbarItem(id: "library.study") {
                    Menu {
                        StudyMenuContent(profile: profile, deck: deck, store: store, router: router, clock: clock)
                    } label: {
                        Label("Study", systemImage: "play.fill")
                    } primaryAction: {
                        router.startStudy(deckID: deck?.id)
                    }
                    .help(deck == nil ? "Review this language" : "Review this deck")
                    .disabled(counts.total == 0 && practiceCount == 0)
                }

                ToolbarItem(id: "library.deck") {
                    Button("New Deck", systemImage: "rectangle.stack.badge.plus") { router.newDeck() }
                        .help("Make a deck in this language")
                }

                ToolbarItem(id: "library.add") {
                    Button("Add Words", systemImage: "plus") { router.newWord() }
                        .help("Add words")
                }
            }
            .onChange(of: profile.id) { reset() }
            .onChange(of: deck?.id) { reset() }
    }

    private func reset() {
        router.searchText = ""
        selection = []
    }

    private var counts: StudyCounts {
        store.library.counts(for: profile.id, deckID: deck?.id, asOf: clock.now)
    }

    /// Whether there is anything to go over again, which is the other reason
    /// the Study button might be worth pressing.
    private var practiceCount: Int {
        store.library.practiceQueue(for: profile.id, deckID: deck?.id, asOf: clock.now).count
    }

    /// The line under the title carries the two facts a word list owes its
    /// owner: how much there is, and how much of it is waiting.
    private var subtitle: String {
        let counts = counts
        var parts = ["\(counts.words) \(counts.words == 1 ? "word" : "words")"]
        if counts.total > 0 { parts.append("\(counts.total) ready") }
        // A subdeck's title is only its own name; the deck it sits in is said
        // underneath, so "A1" is never read without knowing which.
        if let parent = store.library.deck(id: deck?.parentID) {
            parts.insert("in \(parent.displayName)", at: 0)
        }
        return parts.joined(separator: " · ")
    }

    /// Whether this language has a voice at all, which decides what the Audio
    /// column can promise.
    private var hasVoice: Bool {
        Speaker.voice(for: profile) != nil
    }

    private var rows: [WordRow] {
        // "Germany › A1" rather than "A1": in a table showing all of Germany,
        // which subdeck a word is in is the whole point of the column.
        let decks = Dictionary(uniqueKeysWithValues: store.library.decks(in: profile.id).map { ($0.id, store.library.path(of: $0)) })
        // Asked once for the whole table: whether the language has a voice is a
        // fact about the language, not about the word.
        let hasVoice = hasVoice

        let filtered = store.library
            .entries(in: profile.id, deckID: deck?.id)
            .filter { $0.matches(router.searchText) }
            .map {
                WordRow(
                    entry: $0,
                    profile: profile,
                    now: clock.now,
                    deckName: $0.deckID.flatMap { decks[$0] },
                    hasVoice: hasVoice
                )
            }
        return WordRow.sorted(filtered, by: sort)
    }

    @ViewBuilder
    private var content: some View {
        let rows = rows

        if rows.isEmpty {
            if router.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LibraryEmptyState(
                    title: deck == nil ? "No Words Yet" : "Nothing in This Deck",
                    message: deck == nil
                        ? "Add a word in \(LanguageCatalog.name(for: profile.learningCode)) and what it means in \(LanguageCatalog.name(for: profile.nativeCode))."
                        : "Add words here, or move some in from the rest of the language.",
                    symbol: deck == nil ? "text.append" : "rectangle.stack",
                    actionTitle: "Add Words"
                ) {
                    router.newWord()
                }
            } else {
                // It does not stretch on its own, and without this whatever
                // sits above it is dragged into the middle of the window.
                ContentUnavailableView.search(text: router.searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            table(rows)
        }
    }

    private func table(_ rows: [WordRow]) -> some View {
        WordTable(
            rows: rows,
            selection: $selection,
            sort: $sort,
            speakingID: speaker.speakingEntryID,
            play: { speak($0) },
            // Double click, as in a list of files.
            open: { router.editWord($0) },
            delete: { delete($0) },
            menu: { menuItems(for: $0) }
        )
        .sheet(item: $drawingFor) { entry in
            AssociationSheet(
                term: entry.displayTerm(in: profile),
                meaning: entry.meaning,
                existing: entry.association.flatMap { store.associationData(for: $0) }
            ) { data, strokes in
                if strokes == 0 {
                    store.removeAssociation(from: entry.id)
                } else {
                    Task { await store.attachAssociation(data, strokeCount: strokes, to: entry.id) }
                }
            }
        }
    }

    /// What a right click offers, for the words it is about.
    private func menuItems(for ids: Set<UUID>) -> [NSMenuItem] {
        guard !ids.isEmpty else {
            return [
                NSMenuItem.running("Add Words…") { router.newWord() },
                NSMenuItem.running("New Deck…") { router.newDeck() },
            ]
        }

        var items: [NSMenuItem] = []

        if ids.count == 1, let id = ids.first {
            items.append(NSMenuItem.running("Edit Word…") { router.editWord(id) })
            items.append(.separator())

            if let entry = store.library.entry(id: id) {
                if entry.audio != nil {
                    items.append(NSMenuItem.running("Play Recording") { speaker.speak(entry, in: profile, store: store) })
                    items.append(NSMenuItem.running("Remove Recording") { store.removeAudio(from: id) })
                } else if hasVoice {
                    items.append(NSMenuItem.running("Hear It") { speaker.speak(entry, in: profile, store: store) })
                }

                if entry.picture != nil {
                    // A word with a photograph has its picture already; the
                    // editor is where it is changed.
                    items.append(NSMenuItem.running("Remove Photo") { store.removePicture(from: id) })
                } else {
                    items.append(NSMenuItem.running(entry.hasAssociation ? "Edit Association…" : "Draw an Association…") {
                        drawingFor = entry
                    })
                    if entry.hasAssociation {
                        items.append(NSMenuItem.running("Remove Association") { store.removeAssociation(from: id) })
                    }
                }

                items.append(.separator())
            }
        }

        let decks = NSMenu()
        decks.addItem(NSMenuItem.running("None") { store.move(entries: ids, toDeck: nil) })
        let shelves = store.library.decks(in: profile.id)
        if !shelves.isEmpty { decks.addItem(.separator()) }
        for deck in shelves {
            decks.addItem(NSMenuItem.running(store.library.path(of: deck)) { store.move(entries: ids, toDeck: deck.id) })
        }
        decks.addItem(.separator())
        decks.addItem(NSMenuItem.running("New Deck…") { router.newDeck() })
        let move = NSMenuItem(title: "Move to Deck", action: nil, keyEquivalent: "")
        move.submenu = decks
        items.append(move)

        items.append(.separator())

        // A word whose record is misleading — an afternoon of testing the app,
        // or a card so badly written that no schedule saves it — can be met
        // again as if for the first time.
        items.append(NSMenuItem.running(ids.count == 1 ? "Start This Word Again" : "Start \(ids.count) Words Again") {
            store.forgetSchedule(ids: ids)
        })
        items.append(NSMenuItem.running(ids.count == 1 ? "Delete Word" : "Delete \(ids.count) Words") {
            delete(ids)
        })

        return items
    }

    private func speak(_ id: UUID) {
        guard let entry = store.library.entry(id: id) else { return }
        speaker.speak(entry, in: profile, store: store)
    }

    private func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        store.deleteEntries(ids: ids)
        selection.subtract(ids)
    }
}

/// Menu items that run a closure, for menus built in Swift rather than in a
/// storyboard.
extension NSMenuItem {
    static func running(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(ClosureRunner.runClosure(_:)), keyEquivalent: "")
        item.target = ClosureRunner.shared
        item.representedObject = ClosureRunner.Closure(run)
        return item
    }
}

private final class ClosureRunner: NSObject {
    static let shared = ClosureRunner()

    final class Closure {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    @objc func runClosure(_ sender: NSMenuItem) {
        (sender.representedObject as? Closure)?.run()
    }
}
