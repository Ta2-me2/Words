<div align="center">
  <img src="https://github.com/user-attachments/assets/78ec7838-47d6-4738-bf62-41acaec34665" width="128" alt="Movies app icon" />
  

  # Words

  **A little practice. A growing vocabulary.**

  A native macOS app for learning words — with spaced repetition, your own decks, and an on-device AI companion.

  No account. No server. Your vocabulary stays on your Mac.

  [Download](https://github.com/Ta2-me2/Words/releases/latest) · [Build from source](#building) · [Report an issue](https://github.com/Ta2-me2/Words/issues)
</div>

---

## About

Words gives the vocabulary you collect a place to grow. Add a word, bring in a list, or import an Anki deck, then learn through daily reviews, examples, audio, and visual associations.

Reviews use **FSRS** — the Free Spaced Repetition Scheduler — to plan when each card comes back. Alongside your cards, a local AI companion helps explain unfamiliar words and grammar, while **WordFall** turns your own vocabulary into a game.

> Built with SwiftUI for Apple silicon Macs.

---

## Features

### Home

Your daily learning at a glance. See the reviews and new words waiting for you, choose a study direction, and start a session. A streak tracker and activity calendar help you follow your routine, with an overview of all your languages below.

- Set daily limits for new words and reviews, with separate limits for individual decks.
- Choose the days you want to study and use streak freezes when life gets busy.
- Ready for another round? **I want more** adds to today's allowance without changing your usual limits.

<p align="center">
  <img src="https://github.com/user-attachments/assets/5182f107-cb8c-4061-a8ba-e0e022b2a271" width="92%" alt="Words Home with daily reviews, a streak tracker, and an activity calendar" />
</p>

### Add Words

Build your vocabulary one word at a time, paste a whole list, or bring in an **Anki `.apkg` deck**. Only the word and its meaning are required; add pronunciation notes, gender, an example sentence, its translation, and a personal note whenever they help.

- Type an article with a word, such as *die Mutter*, and Words fills in the gender.
- Attach a photo or draw an association with PencilKit to make a word more memorable.
- Import Anki recordings and pictures alongside the words they belong to.
- Paste lists with flexible formatting, or copy the included prompt to have an AI prepare one for you.

<p align="center">
  <img src="https://github.com/user-attachments/assets/21ada77a-30f3-4648-b115-3cf7669ba7a2" width="92%" alt="Add Words with options for a single word, a list, or an Anki import" />
  <img src="https://github.com/user-attachments/assets/766af52a-772b-4811-94a4-c8fe999d0be5" width="92%" alt="Add Words with options for a single word, a list, or an Anki import" />
</p>

### Library

A home for every word you collect. Organize your vocabulary into **decks and subdecks**, give them their own icons, and search your library as it grows. See each word's meaning, deck, audio, visual association, learning stage, and next review date in one table.

<p align="center">
  <img src="https://github.com/user-attachments/assets/ad22e682-3402-433b-9fef-b7bd74028beb" width="92%" alt="Words Library showing vocabulary, decks, learning stages, and review dates" />
</p>

### Statistics

See how your vocabulary is developing: words you have not started, words you are learning, and words you know well. Follow your review activity, recall rate, and daily average, then look ahead at the reviews coming up.

<p align="center">
  <img src="https://github.com/user-attachments/assets/1c719087-79e3-44b8-89ea-4a4189f5e6b8" width="92%" alt="Statistics with vocabulary progress, review history, and upcoming reviews" />
</p>

### WordFall

Give your words a change of scenery. **WordFall** is a RealityKit vocabulary game built around your own decks. Choose a deck and study direction, find the right meaning as you play, and follow your points, levels, and accuracy.

<p align="center">
  <img src="https://github.com/user-attachments/assets/b17cb43c-c68e-4bca-b3fa-854a5f562714" width="92%" alt="WordFall vocabulary game with deck selection, levels, points, and accuracy" />
</p>

### Local AI Companion

The small sphere beside a card opens a conversation about the word you are learning. Ask for a hint, explore an example sentence, or get help with grammar in your preferred language. The companion receives the card's context, your language pair, and whether the answer has been revealed, so it can offer a hint while you are still trying to remember.

Choose a model in Settings:

- **Apple Intelligence** — uses the built-in model on a supported Mac, with no separate model download.
- **Gemma 3 4B** — an optional download of approximately 3 GB, running locally through MLX, with multilingual support and the ability to read a card's picture.

Conversations are processed on your Mac. Installing Gemma downloads the model from Hugging Face and requires accepting Google's [Gemma Terms of Use](https://ai.google.dev/gemma/terms).

<p align="center">
  <img src="https://github.com/user-attachments/assets/e1b6dbef-ba46-4dca-a831-bf81b66615c2" width="92%" alt="Local AI companion offering hints and explanations about the current card" />
</p>

### Review & Practice

Learn in either direction — **word → meaning**, **meaning → word**, or a mix of both. Reveal the answer, listen to the word and its example, then rate your recall with **Again**, **Hard**, **Good**, or **Easy**. FSRS uses your response to schedule the next review.

For extra repetition, switch to **practice without changing your review schedule**, using today's cards or an endless session. Keyboard shortcuts keep reviews moving: **Space** reveals the meaning, **1–4** rates your answer, and **P** plays the word.

<p align="center">
  <img src="https://github.com/user-attachments/assets/b71c230a-90df-4678-9dfe-49fcbc4951d6" width="92%" alt="Review card with a meaning, example sentence, audio, and four recall ratings" />
</p>

### Languages & Voices

Keep separate language pairs and choose the language you want meanings in. Give each language a name and flag, choose an available macOS voice, adjust its speed, and decide whether words and examples play automatically when an answer appears.

Use your own recordings or write a pronunciation note when a system voice is unavailable. Additional macOS voices can be installed from the language settings.

<p align="center">
  <img src="https://github.com/user-attachments/assets/24015acf-0e78-4a22-92ae-75d454d2bf74" width="92%" alt="Language settings with a language pair, flag, voice, playback speed, and automatic audio options" />
</p>

---

## Your Data

Your library is stored locally as a JSON file with folders for media, game progress, and any companion model you install:

```text
~/Library/Application Support/Words/
├── Library.json    Languages, decks, words, and review history
├── Media/          Recordings, photographs, and drawings
├── Games/          Game progress
└── Models/         Downloaded companion model
```

No account or hosted backend is required. Your vocabulary and companion conversations stay on your Mac; optional model and voice downloads require an internet connection.

---

## Requirements

- **macOS 26 or later** for the app.
- **macOS 27** for the local AI companion.
- A Mac with **Apple silicon**.
- **Xcode 27 with Swift 6.4** to build from source.

## Building

```bash
git clone https://github.com/Ta2-me2/Words.git
cd Words
open Words.xcodeproj
```

Build and run from Xcode. The first build resolves the Swift packages and asks you to trust MLX's build plugins — choose **Trust & Enable**.

<details>
<summary><strong>Command-line build & troubleshooting</strong></summary>

Build from Terminal:

```bash
xcodebuild -project Words.xcodeproj -scheme Words -configuration Debug \
  -derivedDataPath build -skipPackagePluginValidation -skipMacroValidation build
```

MLX compiles Metal kernels. If the build stops at `cannot execute tool 'metal'`, install the toolchain:

```bash
xcodebuild -downloadComponent MetalToolchain
```

The app is signed ad hoc and is not sandboxed. No Apple Developer account is needed to build or run it locally.

</details>

### Checks

```bash
Tests/run.sh
```

The checks cover scheduling, review queues, daily limits, decks, imports, streaks, persistence, and the context passed to the companion. They run as a command-line binary without opening the app.

For the project structure and implementation details, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Built With

SwiftUI · FSRS · RealityKit · PencilKit · Apple Intelligence · [MLX](https://github.com/ml-explore/mlx-swift-lm)

---

<div align="center">
  Made with care by <a href="https://github.com/Ta2-me2">Ta2</a>

  MIT License — see <a href="LICENSE">LICENSE</a>.
</div>
