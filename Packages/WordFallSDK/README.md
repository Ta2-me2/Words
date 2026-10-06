# WordFall SDK 2.2.2

A native macOS vocabulary game built with RealityKit and SwiftUI. English UI, host-supplied words and translations, a compact dark menu over the actual game scene, and persistent learning statistics. macOS 14+, Xcode 16+; tested on Apple Silicon with Xcode 26.

## Connect Deck folders from your app

**The SDK has no built-in Deck choices, no categories and no “All words” entry.** Pass your own folders as `[WortfallDeck]`. Each entry contains its stable database ID, display name and exact list of cards. Both questions and distractors come only from the selected Deck.

```swift
import SwiftUI
import WortfallCore
import WortfallKit

struct GameScreen: View {
    @ObservedObject var progress: WortfallProgress
    let decks: [WortfallDeck] // Map these from your database.
    @Binding var selectedDeckID: String? // The same selection used by the host app.

    var body: some View {
        WortfallLibraryView(
            libraryID: "my-vocabulary-library",
            decks: decks,
            selectedDeckID: $selectedDeckID,
            progress: progress,
            onAnswer: { answer in
                // Stable host card ID; actual direction; first attempt versus retry.
                print(answer.cardID, answer.mode, answer.isCorrect, answer.attempt)
                // Queue database/cloud work outside the main actor.
            }
        )
    }
}

// Example mapping; use actual database IDs and values in your application.
let folders = [WortfallDeck(
    id: "folder-travel",
    name: "Travel",
    cards: [
        VocabularyCard(id: "word-1", word: "der Zug", translation: "поезд"),
        VocabularyCard(id: "word-2", word: "das Hotel", translation: "отель"),
        VocabularyCard(id: "word-3", word: "der Flughafen", translation: "аэропорт")
    ]
)]
```

The binding is optional. Without it, the game maintains its own selection and initially selects the first supplied Deck. With it, the host can open the game on a specific folder and observe the player's Deck selection. An empty array shows an empty selector and disables Start. There is no fallback to demo vocabulary for gameplay.

Do not regenerate IDs on every refresh. Deck IDs must be unique within the library, and card IDs must be unique across the learner's library for correct cross-Deck analytics. Word and Deck edits appear on the next new run. A paused run retains its original Deck and questions; Continue resumes that exact run. End run returns to editable selections.

## Import into Xcode

1. **File → Add Package Dependencies → Add Local**; choose this folder containing `Package.swift`.
2. Add **WortfallKit** and **WortfallCore** to your app target. Do not add the demo executable.
3. Load a learner's `WortfallProgress` and pass your Decks using the example above.
4. Keep the SwiftPM resource bundle included. No camera permissions, server or third-party packages are needed.

## Menus and controls

- Pause, Escape, Space or the top-right menu button opens the same compact menu with **Continue game**. Position, lives and the current question are preserved.
- The result panel provides **Main menu** and **Next level** after a win, or **Main menu** and **Try again** after a loss.
- The gear next to volume opens **Game Sounds** and **Reduce Motion Effects** settings.
- Steering: mouse, left/right arrows, or **1 / 2 / 3**.
- Gameplay buttons, left to right: **Pause · Volume · Menu (×)**.

Modes: Word → translation, Translation → word, and **Mixed directions**. Mixed uses both directions in shuffled pairs of questions; mistakes keep the current direction and options for the retry. Validation must succeed in both directions before a mixed run can start.

The main menu shows lifetime earned points, total successful level completions (including replays), and correct answers / all attempts as a percentage. Statistics also exposes first-try accuracy, per-word mistakes, timing and confusions.

## Demo and build

The shipped `Demo/WordFall.app` starts with **no preloaded Decks**. Its host shell can load your JSON using the macOS menu **Decks → Open decks…**. For a developer smoke test, explicitly open `Documentation/Examples/host-decks.json`; these sample entries are never added automatically.

```sh
swift test
./Scripts/build-app.sh release
open Build/WordFall.app
# Optional explicit host data:
open Build/WordFall.app --args --decks "$PWD/Documentation/Examples/host-decks.json"
./Scripts/package-sdk.sh
```

The demo is locally ad-hoc signed. Use your own Developer ID and notarization for distribution. Source, procedural assets, resources and the demo integration are included.

## Further documentation

- [Integration and persistence](Documentation/Integration.md)
- [Events and statistics definitions](Documentation/DataModel.md)
- [Validation and performance](Documentation/Performance.md)

2.2 replaces the old `cards/categories` library initializer with `decks/selectedDeckID`. Existing schema-1 progress is readable. New host Deck IDs have their own unlock paths; historical lifetime statistics remain. The standalone `WortfallGameView` API is unchanged. Saved progress restores levels and statistics; an interrupted app launch begins a level anew, while an in-app pause resumes the exact current run.

## 2.2.2 maintenance update

The display name is now **WordFall**, with the supplied IconWordFall artwork. The library and game apply color schemes locally using the SwiftUI environment, preserving the host window’s appearance. The settings popover keeps its own appearance preference. Package/module names (`WortfallKit`, `WortfallCore`), public types, bundle identifier and saved-progress location remain unchanged for existing integrations. No migration is required.

### Level preparation (2.2.2)

Starting a selected level, retrying and advancing to the next level display an English loading overlay. Its progress reflects completed preparation steps (words, 24 track sections, finish and lighting), rather than an estimated remaining time. Track construction yields to the UI between sections. Gameplay and steering are suspended during preparation; the run starts after the scene is ready. The overlay uses a local dark color scheme and requires no host integration changes.
