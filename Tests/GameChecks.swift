import Foundation

/// Which words a game is given, and where what it learns is kept.
func checkGames() {
    section("What a game is played with")

    var library = Library()
    let german = LanguageProfile(name: "German", learningCode: "de", nativeCode: "ru")
    let french = LanguageProfile(name: "French", learningCode: "fr", nativeCode: "ru")
    library.upsert(german)
    library.upsert(french)

    let travel = Deck(profileID: german.id, name: "Travel", dailyNewLimit: nil)
    let tiny = Deck(profileID: german.id, name: "Tiny", dailyNewLimit: nil)
    library.upsert(travel)
    library.upsert(tiny)

    func add(_ written: String, _ meaning: String, to deck: Deck? = nil, in profile: LanguageProfile = german) -> Entry {
        let (bare, gender) = LanguageGenders.split(term: written, language: profile.learningCode)
        let entry = Entry(profileID: profile.id, deckID: deck?.id, term: bare, meaning: meaning, gender: gender)
        library.upsert(entry)
        return entry
    }

    let window = add("das Fenster", "окно", to: travel)
    _ = add("der Zug", "поезд", to: travel)
    _ = add("das Hotel", "отель", to: travel)
    _ = add("die Reise", "путешествие", to: travel)
    _ = add("gehen", "идти", to: tiny)
    _ = add("sehen", "видеть", to: tiny)
    _ = add("gut", "хороший")
    _ = add("le train", "поезд", in: french)

    let collections = GameVocabulary.collections(for: german, in: library)

    check("the whole language comes first", collections.first?.id == GameVocabulary.allWordsID)
    check("under a name, because the app never gives it one", collections.first?.name == "All Words")
    check("with every word in the language", collections.first?.words.count == 7)
    check("and none from another language",
          !(collections.first?.words.contains { $0.word == "le train" } ?? true))

    check("a deck big enough to play is offered", collections.contains { $0.deckID == travel.id })
    check("with only its own words", collections.first { $0.deckID == travel.id }?.words.count == 4)
    check("a deck of two words is not: there is nothing to put beside the answer",
          !collections.contains { $0.deckID == tiny.id })
    check("and the screen can say why", GameVocabulary.tooSmall(for: german, in: library).map(\.id) == [tiny.id])

    let played = collections.first { $0.deckID == travel.id }?.words.first { $0.id == window.id.uuidString }
    check("a word is shown the way it is read, article and all", played?.word == "das Fenster")
    check("and answered with its meaning", played?.translation == "окно")
    check("identified by the word itself, so the game's statistics survive an edit",
          played?.id == window.id.uuidString)
    check("and a deck by the deck, so its levels do too",
          collections.first { $0.deckID == travel.id }?.id == travel.id.uuidString)
    check("asking twice gives the same answer",
          GameVocabulary.collections(for: german, in: library).map(\.id) == collections.map(\.id))

    var small = Library()
    let italian = LanguageProfile(name: "Italian", learningCode: "it", nativeCode: "ru")
    small.upsert(italian)
    small.upsert(Entry(profileID: italian.id, term: "ciao", meaning: "привет"))
    small.upsert(Entry(profileID: italian.id, term: "grazie", meaning: "спасибо"))
    check("a language of two words has nothing to play",
          GameVocabulary.collections(for: italian, in: small).isEmpty)

    section("Where a game keeps its progress")

    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "words-games-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let kept = UUID(), gone = UUID()
    let keptFile = GameStorage.progressURL(game: "Wortfall", profileID: kept, root: root)
    check("one file per language, named after it, inside the library's folder",
          keptFile.path.hasSuffix("/Games/Wortfall/\(kept.uuidString).json") && keptFile.path.hasPrefix(root.path))

    let folder = GameStorage.folder(game: "Wortfall", root: root)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in ["\(kept.uuidString).json", "\(gone.uuidString).json", "notes.json", "\(gone.uuidString).txt"] {
        FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: Data("{}".utf8))
    }

    let orphans = GameStorage.orphans(game: "Wortfall", keeping: [kept], root: root)
    check("a language that no longer exists leaves an orphan behind",
          orphans.map(\.lastPathComponent) == ["\(gone.uuidString).json"])
    check("and nothing that is not a language's file is ever touched",
          !orphans.contains { $0.lastPathComponent == "notes.json" || $0.pathExtension == "txt" })

    GameStorage.removeProgress(game: "Wortfall", profileID: kept, root: root)
    check("deleting a language's progress removes exactly its file",
          !FileManager.default.fileExists(atPath: keptFile.path)
              && FileManager.default.fileExists(atPath: folder.appending(path: "notes.json").path))
}
