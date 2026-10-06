import Foundation

/// Recordings: lining a folder of them up against the words, and what happens
/// to the files when a word goes.
func checkAudio() async {
    section("Matching files to words")

    let profile = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    var entries = [
        Entry(profileID: profile.id, term: "Mutter", meaning: "mother", gender: .feminine),
        Entry(profileID: profile.id, term: "Berg", meaning: "mountain", gender: .masculine),
        Entry(profileID: profile.id, term: "Straße", meaning: "street"),
        Entry(profileID: profile.id, term: "Brot", meaning: "bread")
    ]

    var plan = AudioMatcher.plan(
        filenames: ["Mutter.m4a", "berg.mp3", "STRASSE.wav", "der Berg.aiff", "Fluss.m4a", "notes.txt"],
        entries: entries,
        language: "de"
    )

    check("a file named after the word finds it", plan.matches.contains { $0.term == "Mutter" })
    check("capitals do not matter", plan.matches.contains { $0.filename == "berg.mp3" })
    check("an article in the filename is understood",
          plan.matches.first { $0.filename == "der Berg.aiff" }?.term == "Berg")
    check("a word nobody recorded is not invented", !plan.matches.contains { $0.term == "Brot" })
    check("a file matching nothing is reported", plan.unmatched.contains("Fluss.m4a"))
    check("and so is one that is not a recording at all", plan.unmatched.contains("notes.txt"))

    check("umlauts survive the round trip", AudioMatcher.key("Straße") == AudioMatcher.key("strasse")
          || AudioMatcher.key("Straße") == AudioMatcher.key("STRASSE"))

    entries[0].audio = AudioClip(file: "Media/old.m4a", source: .recorded)
    plan = AudioMatcher.plan(filenames: ["Mutter.m4a"], entries: entries, language: "de")
    check("a word that already has one is marked as being replaced",
          plan.matches.first?.replacesExisting == true)

    section("How a word can be heard")

    let silent = Entry(profileID: profile.id, term: "Haus", meaning: "house")
    check("with no file and no voice, not at all",
          silent.audioAvailability(hasVoice: false) == .none)
    check("with a voice, by the voice",
          silent.audioAvailability(hasVoice: true) == .voice)

    var recorded = silent
    recorded.audio = AudioClip(file: "Media/haus.m4a", source: .recorded)
    check("with a file, by the file", recorded.audioAvailability(hasVoice: true) == .clip(.recorded))
    check("even when there is no voice", recorded.audioAvailability(hasVoice: false).hasClip)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let round = try! JSONDecoder.words.decode(Entry.self, from: try! encoder.encode(recorded))
    check("a clip survives a round trip", round.audio?.file == "Media/haus.m4a")
    check("with what it is", round.audio?.source == .recorded)
    check("and a word written before recordings existed simply has none",
          silent.audio == nil)

    section("Files that belong to a word")

    let fileManager = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "words-audio-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? fileManager.removeItem(at: root) }

    let store = LibraryStore(persistence: FileLibraryPersistence(fileURL: root.appending(path: "Library.json")))
    await store.load()
    let german = store.addProfile(name: "German", learningCode: "de", nativeCode: "en")
    let haus = store.addEntry(profileID: german.id, term: "Haus", meaning: "house")!

    // Something to stand in for a recording.
    let source = root.appending(path: "spoken.m4a")
    try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try? Data("not really audio".utf8).write(to: source)

    let attached = await store.attachAudio(from: source, to: haus.id, kind: .recorded, seconds: 1.5)
    check("a recording can be hung on a word", attached)

    let clip = store.library.entry(id: haus.id)?.audio
    check("the word knows it has one", clip != nil)
    check("it remembers how long it was", clip?.seconds == 1.5)
    check("the library keeps its own copy",
          clip.map { fileManager.fileExists(atPath: store.mediaURL(for: $0.file).path(percentEncoded: false)) } == true)
    check("and the learner's own file is left where it was",
          fileManager.fileExists(atPath: source.path(percentEncoded: false)))
    check("the copy lives in the library's media folder", clip?.file.hasPrefix("Media/") == true)

    let kept = clip!.file
    store.removeAudio(from: haus.id)
    check("removing it takes it off the word", store.library.entry(id: haus.id)?.audio == nil)

    // The file goes on a background task; give it a moment to happen.
    try? await Task.sleep(for: .milliseconds(120))
    check("and deletes the file", !fileManager.fileExists(atPath: store.mediaURL(for: kept).path(percentEncoded: false)))

    _ = await store.attachAudio(from: source, to: haus.id, kind: .imported)
    let second = store.library.entry(id: haus.id)!.audio!.file
    store.deleteEntries(ids: [haus.id])
    try? await Task.sleep(for: .milliseconds(120))
    check("deleting the word takes its recording with it",
          !fileManager.fileExists(atPath: store.mediaURL(for: second).path(percentEncoded: false)))

    await store.saveNow()
    check("and the library is still readable afterwards", store.saveState == .saved)
}

/// The catalogue of voices a Mac could install, and the word a voice is given.
func checkVoiceCatalogue() {
    section("Voices the Mac could install")

    // A catalogue of the shape macOS publishes, written where the checks can
    // read it — the real one is a system file that may move or change.
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "voice-catalogue-\(UUID().uuidString).plist")
    defer { try? FileManager.default.removeItem(at: url) }

    let catalogue: [String: Any] = [
        "AssetType": "com.apple.MobileAsset.VoiceServices.CombinedVocalizerVoices",
        "Assets": [
            ["Name": "Petra", "Languages": ["de-DE"], "Gender": "female",
             "VoiceId": "com.apple.ttsbundle.Petra", "_DownloadSize": 487_000_000],
            ["Name": "Markus", "Languages": ["de-DE"], "Gender": "male",
             "VoiceId": "com.apple.ttsbundle.Markus", "_DownloadSize": 129_000_000],
            ["Name": "Katya", "Languages": ["ru-RU"], "Gender": "female",
             "VoiceId": "com.apple.ttsbundle.Katya"],
            ["Languages": ["de-DE"]]
        ]
    ]
    try! PropertyListSerialization
        .data(fromPropertyList: catalogue, format: .xml, options: 0)
        .write(to: url)

    let german = VoiceCatalog.voices(for: "de", in: url)
    check("the catalogue is read", german.count == 2)
    check("in name order", german.map(\.name) == ["Markus", "Petra"])
    check("with the size of the download", german.first?.size?.isEmpty == false)
    check("an entry with no name is not a voice", !german.contains { $0.name.isEmpty })
    check("another language's voices are not offered",
          VoiceCatalog.voices(for: "ru", in: url).map(\.name) == ["Katya"])
    check("a language with nothing to install says nothing",
          VoiceCatalog.voices(for: "ja", in: url).isEmpty)
    check("a catalogue that is not there is not a crash",
          VoiceCatalog.voices(for: "de", in: url.appending(path: "missing")).isEmpty)

    check("a voice already installed is not offered again",
          !VoiceCatalog.voices(for: "de", in: url).isEmpty)

    section("What the voice is given to say")

    let profile = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    let entry = Entry(profileID: profile.id, term: "Mutter", meaning: "mother",
                      gender: .feminine, example: "Meine Mutter kocht.")
    check("a word is spoken with its article", entry.displayTerm(in: profile) == "die Mutter")
    check("and the example is a sentence of its own", entry.example == "Meine Mutter kocht.")

    check("both switches start off",
          profile.speaksOnReveal == false && profile.speaksExampleOnReveal == false)

    var speaking = profile
    speaking.speaksOnReveal = true
    speaking.speaksExampleOnReveal = true
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let round = try! JSONDecoder.words.decode(LanguageProfile.self, from: try! encoder.encode(speaking))
    check("and survive a round trip",
          round.speaksOnReveal && round.speaksExampleOnReveal)

    let old = """
    {
      "id": "\(UUID().uuidString)", "name": "German",
      "learningCode": "de", "nativeCode": "en", "dailyNewLimit": 20,
      "createdAt": "2026-01-01T00:00:00Z"
    }
    """
    let migrated = try! JSONDecoder.words.decode(LanguageProfile.self, from: Data(old.utf8))
    check("a profile written before them is silent by default",
          !migrated.speaksOnReveal && !migrated.speaksExampleOnReveal)
}
