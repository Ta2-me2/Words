# Integrating WordFall 2.2

## Host-owned Decks

Use `WortfallLibraryView(libraryID:decks:selectedDeckID:progress:onAnswer:onLevelEnd:)` for the complete menu, gameplay and statistics experience. Pass `[WortfallDeck]`, mapping each host folder's stable ID, name and cards. No folders, combined deck or categories are inserted by the SDK. See the compiling API example in [README](../README.md).

`selectedDeckID` is an optional `Binding<String?>`: pass your host selection to open a particular Deck and observe changes made in the game. Without a binding, selection is internal and starts at the first supplied Deck. With a nil or missing ID, the player must select a valid Deck. Empty/invalid Decks cannot start. Deck names and vocabulary are host content and are not translated by the SDK.

Keep IDs stable and unique. Card IDs should be globally unique within a learner's library, even across Decks; prefix local IDs with a database namespace if necessary. Use `.id(learnerID)` when switching accounts so retained sessions and callbacks bind to the new learner. Updates to host Deck data apply on the next new run; a paused run retains a snapshot of its original cards. Deck/mode/level controls are locked until the player ends or finishes that run.

Each library/Deck/mode has independent level unlocks. The internal scope is the library's length-prefixed ID followed by `/deck/` and the host Deck ID. Word analytics aggregate across Decks by card ID. The host owns login, editing, scheduling and cloud synchronization; there are no global singleton services.

## Independent components

- `WortfallLibraryView`: complete in-scene menu, host Deck picker and progress recording.
- `WortfallGameView`: standalone game for custom host navigation; explicitly wire callbacks to progress.
- `WortfallDashboardView`: separately embeddable statistics, adapting to light/dark surroundings.
- `WortfallCore`: validated vocabulary, simulation, Codable events, analytics and storage protocol.
- `WortfallProgress`: observable model with serialized asynchronous saves and explicit flush.

## Study modes and validation

Create `VocabularyDeck(cards: hostDeck.cards, mode: .wordToTranslation)`, `.translationToWord` or `.mixed`. Both prompts and distractors use only those cards. Mixed mode shuffles pairs containing one question of each direction; retries never change direction. `Challenge.direction` and `AnswerRecord.mode` hold the actual direction. `AnswerRecord.studyMode` and `LevelResult.mode` hold the selected run mode, including mixed. Old answer records without studyMode decode as nil; treat nil as mode.

Validation rejects empty text, duplicate card IDs, fewer than three distinct answers and prompts without two unambiguous distractors. Mixed validates both directions before play. All accepted answers sharing a normalized prompt are excluded from distractors. Normalization ignores case, diacritics and surrounding whitespace; disambiguate homonyms in the displayed text when necessary. For presentation use `Challenge.prompt` and `options`; a mixed run has no single fixed prompt direction.

## Load persistent progress before showing the game

```swift
@MainActor
func openProgress(for learnerID: UUID) async throws -> WortfallProgress {
    let root = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let url = root
        .appendingPathComponent("MyApp/Wortfall", isDirectory: true)
        .appendingPathComponent("\(learnerID.uuidString).json")
    return try await WortfallProgress.open(storage: JSONProgressStorage(url: url))
}
```

Call this in a host `.task`, retain the returned object, and show loading/error states until it succeeds. See `Sources/WortfallDemo/WortfallDemo.swift` for a complete compiling example. `WortfallProgress()` creates an **in-memory** model, suitable for previews and host-managed persistence; it does not automatically save to disk.

The JSON actor encodes/writes off the main actor, uses atomic replacement and rejects stale revisions. Saves are ordered. `saveError` exposes failed writes, and `try await progress.flush()` retries the current state. Missing files start empty; corrupt or unsupported files throw and are not silently replaced. Preserve a failed file and handle recovery in the host.

Await `flush()` before completing logout, custom screen dismissal or application termination. The included demo waits for it during normal Quit. The library waits for it on its Exit action and offers a retry if it fails. Abrupt process termination or power loss before a queued write finishes can lose the latest unsaved event; the previous atomic snapshot remains intact.

## Connect your own persistence

```swift
actor HostProgressStorage: ProgressStorage {
    // Use a separate repository/document per learner.
    private let readData: @Sendable () async throws -> Data?
    private let writeData: @Sendable (Data) async throws -> Void
    private var savedRevision: UInt64 = 0

    init(read: @escaping @Sendable () async throws -> Data?,
         write: @escaping @Sendable (Data) async throws -> Void) {
        readData = read; writeData = write
    }

    func load() async throws -> ProgressSnapshot {
        guard let data = try await readData() else { return ProgressSnapshot() }
        let value = try JSONDecoder().decode(ProgressSnapshot.self, from: data)
        guard value.schemaVersion == 1 else {
            throw ProgressStorageError.unsupportedVersion(value.schemaVersion)
        }
        savedRevision = value.revision
        return value
    }

    func save(_ value: ProgressSnapshot) async throws {
        guard value.revision >= savedRevision else { return }
        try await writeData(JSONEncoder().encode(value))
        savedRevision = value.revision
    }
}
```

The progress model serializes calls to this store. If the repository is used by other writers, the host must implement transactional compare-and-swap/serialization too. Revision numbers order local snapshots, not distributed devices. Do not resolve cloud conflicts by simply adding aggregates: duplicate answers would be counted twice. Use event UUIDs in your host event store and rebuild/merge according to your own account sync policy. The SDK does not implement cross-device conflict resolution.

## Custom gameplay screen and callbacks

```swift
let deck = try VocabularyDeck(cards: cards, mode: .translationToWord)
let scope = "due-cards-session"
let startingLevel = progress.snapshot.unlockedLevel(
    scopeID: scope, mode: deck.mode
)

WortfallGameView(
    deck: deck,
    startingLevel: startingLevel,
    onAnswer: { answer in
        progress.record(answer)
        // Enqueue the raw Codable event in your repository if needed.
    },
    onLevelEnd: { result in
        progress.record(result)
    },
    scopeID: scope,
    onExit: {
        Task {
            do {
                try await progress.flush()
                // Dismiss your screen here.
            } catch {
                // Present a save failure and allow retry.
            }
        }
    }
)
```

Callbacks execute on the main actor. Do not perform synchronous disk access or large database transactions in them. `onAnswer` fires once for each attempted crossing, including mistakes and retries; `onLevelEnd` fires once for a win or loss, and includes all that run's answers. Next level and Retry create new run IDs. `onExit` pauses the game; when omitted no Exit button is shown. The view pauses on loss of app focus and disappearance.

`ProgressSnapshot.record` is idempotent by answer UUID and run UUID. It is safe to record answers individually and then record the final result; it will not count those answers twice. The ready-to-use library already does this, so use its callbacks for host-specific work rather than maintaining a second model accidentally.

## Dashboard and exports

```swift
WortfallDashboardView(progress: progress)
let data = try JSONEncoder().encode(progress.snapshot)
let wordStats = progress.snapshot.words[hostCardID]
let forwardStats = wordStats?.directions[StudyMode.wordToTranslation.rawValue]
```

A standalone dashboard accepts optional `scopeNames: [String: String]` for human-readable collection names. The library supplies these automatically. Data is portable JSON via Codable; the host can export/share it, build its own charts or use SwiftData entities instead. See [DataModel.md](DataModel.md) for definitions.

## Navigation, saves and migration

The result panel offers Main menu plus Next level (win) or Try again (loss). In the full library, Pause/Escape/Space/menu opens the compact menu with Continue game. Continue preserves the exact run, position, lives and current question; End run saves recorded answers and returns to new-run selection. Abandoning a run does not mark it won or lost.

New app launches restore statistics and unlocked levels but do not restore mid-slope state. Game HUD scores describe the current session; lifetime points include all correct-answer points across retries and unfinished runs.

The 2.2 library initializer replaces cards/categories with decks/selectedDeckID. Re-map host folders to WortfallDeck; there is no All words entry. The standalone game initializer is unchanged. Progress schema 1 is retained and 2.2 can load 2.0/2.1 profiles. New Deck scope IDs start new unlock paths; historical statistics remain. Profiles containing mixed mode should not be opened in older SDK releases that do not recognize that enum case.

For account deletion, stop the game and await flush before the host deletes its learner-specific storage; dispose of the old model before switching accounts. The demo saves to Application Support/Wortfall/progress-v1.json; the SDK writes nothing unless storage is supplied.
