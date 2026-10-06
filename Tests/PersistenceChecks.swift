import Foundation

/// The library on disk: that it is created, that it survives being written and
/// read, and that a file the app cannot understand is never destroyed by it.
func checkPersistence() async {
    let fileManager = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "words-checks-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? fileManager.removeItem(at: root) }

    let fileURL = root.appending(path: "Library.json")
    let store = FileLibraryPersistence(fileURL: fileURL)

    section("The file")

    let created = try? await store.load()
    check("opening a library that is not there creates one", created != nil)
    check("the file is written straight away",
          fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)))
    check("and it starts empty", created?.profiles.isEmpty == true)

    var library = created ?? Library()
    let profile = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    library.upsert(profile)
    library.upsert(Entry(profileID: profile.id, term: "Haus", meaning: "house"))

    do {
        try await store.save(library)
        let reloaded = try await store.load()
        check("what was saved is what is read back", reloaded.entries.count == 1)
        check("with the same identity", reloaded.libraryID == library.libraryID)
        check("and the same word", reloaded.entries[0].term == "Haus")
    } catch {
        check("saving and loading works", false)
    }

    check("the file is readable by a person",
          (try? String(contentsOf: fileURL, encoding: .utf8))?.contains("\"term\" : \"Haus\"") == true)

    section("A file the app cannot read")

    try? Data("this is not a library".utf8).write(to: fileURL)
    var refused = false
    do {
        _ = try await store.load()
    } catch {
        refused = true
    }
    check("an unreadable library is reported, not replaced", refused)

    let aside = (try? fileManager.contentsOfDirectory(atPath: root.path(percentEncoded: false)))?
        .filter { $0.contains("unreadable") } ?? []
    check("the file itself is set aside intact", aside.count == 1)
    check("and its contents are untouched",
          (try? String(contentsOf: root.appending(path: aside[0]), encoding: .utf8)) == "this is not a library")
}
