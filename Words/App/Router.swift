import Foundation
import Observation

/// What is on screen: which language is being studied, which section is open,
/// and what is presented over it.
///
/// Sheets live here rather than in the screen that opens them, because the menu
/// bar opens the same ones from wherever the window happens to be.
@Observable
final class Router {

    /// The language everything on screen is about.
    var profileID: UUID? {
        didSet {
            guard oldValue != profileID else { return }
            UserDefaults.standard.set(profileID?.uuidString, forKey: Self.profileKey)
            // A deck belongs to one language; carrying its selection across
            // would show an empty list under another language's name.
            lastDeckID = nil
            if case .deck = sidebar { sidebar = .section(.library) }
        }
    }

    var sidebar: SidebarItem = .section(.home) {
        didSet {
            switch sidebar {
            case .section(let section):
                UserDefaults.standard.set(section.rawValue, forKey: Self.sectionKey)
            case .deck(let id):
                lastDeckID = id
            }
        }
    }

    /// The deck last looked at, which is the one new words are filed into.
    ///
    /// Going from a deck to the Add Words screen has to keep the deck, or
    /// filling a deck would mean picking it again for every word.
    private(set) var lastDeckID: UUID?

    var sheet: SheetRoute?

    /// The one search field in the window. It belongs to the Library.
    var searchText = ""

    /// Bumped when something outside the Add Words screen asks it for the
    /// cursor — the ⌘N that used to open a sheet now takes you there instead.
    private(set) var addWordsFocus = 0

    /// Which side of the Add Words screen is showing.
    ///
    /// Kept here rather than in the screen because the menu bar chooses it too,
    /// and a screen that has not been built yet cannot be told anything.
    var addMode: AddMode = .single

    private static let profileKey = "selectedProfile"
    private static let sectionKey = "selectedSection"

    init() {
        profileID = UserDefaults.standard.string(forKey: Self.profileKey).flatMap(UUID.init(uuidString:))
        let section = UserDefaults.standard.string(forKey: Self.sectionKey)
            .flatMap(AppSection.init(rawValue:)) ?? .home
        sidebar = .section(section)
    }

    // MARK: - Where we are

    var section: AppSection {
        switch sidebar {
        case .section(let section): section
        case .deck: .library
        }
    }

    /// The deck the Library is filtered by, or `nil` for the whole language.
    var deckID: UUID? {
        if case .deck(let id) = sidebar { return id }
        return nil
    }

    /// Picks up where the last session left off, or on the first language
    /// there is. A window that opens on nothing selected asks the user to do
    /// work the app could have done.
    func restoreSelection(in library: Library) {
        if let profileID, library.profile(id: profileID) != nil { return }
        profileID = library.profiles.first?.id
    }

    // MARK: - Intents

    func show(_ section: AppSection) {
        sidebar = .section(section)
    }

    func show(deck: UUID) {
        sidebar = .deck(deck)
    }

    func newLanguage() {
        sheet = .newLanguage
    }

    func editLanguage(_ id: UUID) {
        sheet = .editLanguage(id)
    }

    /// Adding a word is a screen, not a sheet: it is the thing a learner does
    /// most often, and it deserves room to grow.
    func newWord() {
        addMode = .single
        show(.add)
        addWordsFocus += 1
    }

    /// Lines a folder of recordings up against the vocabulary.
    func matchAudio() {
        guard let profileID else { return }
        sheet = .matchAudio(profileID: profileID)
    }

    /// Takes the Add Words screen to its list side.
    func importWords() {
        addMode = .list
        show(.add)
    }

    func editWord(_ id: UUID) {
        sheet = .editWord(entryID: id)
    }

    /// A new deck at the top of the language, or inside the deck given.
    func newDeck(inside parentID: UUID? = nil) {
        guard let profileID else { return }
        sheet = .newDeck(profileID: profileID, parentID: parentID)
    }

    func editDeck(_ id: UUID) {
        sheet = .editDeck(deckID: id)
    }

    /// Starts a sitting. From the Library with a deck selected it is that
    /// deck's sitting; everywhere else it is the whole language.
    func startStudy(deckID: UUID? = nil, mode: StudyMode = .scheduled) {
        guard let profileID else { return }
        sheet = .study(profileID: profileID, deckID: deckID ?? self.deckID, mode: mode)
    }

    /// Asks how much more to take on today, once today's cards are done.
    func studyMore(deckID: UUID? = nil) {
        guard let profileID else { return }
        sheet = .studyMore(profileID: profileID, deckID: deckID ?? self.deckID)
    }
}

/// The two ways of adding words.
nonisolated enum AddMode: String, CaseIterable, Identifiable, Sendable {
    case single
    case list
    case anki

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: "One Word"
        case .list: "A List"
        case .anki: "From Anki"
        }
    }
}

/// Everything the window can present over itself.
enum SheetRoute: Identifiable, Hashable {
    case newLanguage
    case editLanguage(UUID)
    case editWord(entryID: UUID)
    case newDeck(profileID: UUID, parentID: UUID?)
    case editDeck(deckID: UUID)
    case matchAudio(profileID: UUID)
    case study(profileID: UUID, deckID: UUID?, mode: StudyMode)
    case studyMore(profileID: UUID, deckID: UUID?)

    var id: String {
        switch self {
        case .newLanguage: "new-language"
        case .editLanguage(let id): "edit-language-\(id)"
        case .editWord(let id): "edit-word-\(id)"
        case .matchAudio(let id): "match-audio-\(id)"
        case .newDeck(let id, let parent): "new-deck-\(id)-\(parent?.uuidString ?? "top")"
        case .editDeck(let id): "edit-deck-\(id)"
        case .study(let profile, let deck, let mode):
            "study-\(profile)-\(deck?.uuidString ?? "all")-\(mode)"
        case .studyMore(let profile, let deck):
            "study-more-\(profile)-\(deck?.uuidString ?? "all")"
        }
    }
}
