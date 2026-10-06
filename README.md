# Words

A macOS app for learning vocabulary. Native SwiftUI, no account, no server: the
library is one JSON file and a folder of media on your own disk, and the model
that answers questions about a card runs on the same Mac.

Words schedules with **FSRS** — the Free Spaced Repetition Scheduler, the one
Anki ships — so two words learned on the same afternoon can end up months apart.
What it adds around that is the part that usually sends people back to a
spreadsheet: decks that are real shelves, an Anki importer that reads the messes
real shared decks arrive in, recordings and pictures that belong to the word,
and a tutor beside the card that can be asked anything in any language.

## What it does

**Learning**

- FSRS scheduling, written out rather than imported — stability, difficulty and
  the forgetting curve, with every rule checked.
- A daily allowance for new words and reviews, a limit per deck, and "I want
  more" for once the day is done — which changes today and nothing else.
- Cards asked either way round, or mixed: word → meaning, meaning → word.
- Practice that reschedules nothing, over today's cards or endlessly.
- A streak that understands a life: freezes, and a week that only asks for the
  days you set.

**The words themselves**

- Decks and subdecks, with their own limits and their own icons.
- Gender kept as a gender, not as an article — type "die Mutter" and the article
  is filed for you.
- A transcription under the word, written however you write sounds down. Meant
  for the languages no voice will ever read aloud: Georgian is in the list, and
  macOS has no voice for it.
- Recordings of your own, or the system voice where the Mac has one. Nothing is
  generated and stored — a voice can change, and a library of files made by last
  month's voice would be a library quietly out of date.
- Photographs, and associations you draw yourself with PencilKit.

**Getting words in**

- **From Anki** — reads `.apkg` packages, old formats included, guesses which
  field is the word, which the meaning, which the article, and lines recordings
  and pictures up with the notes they belong to.
- **From a list** — paste `word;meaning;gender;[transcription];example;
  translation;note`. It forgives what a person's file actually contains: blank
  lines, Markdown bullets, tabs, a dash where a semicolon should be. There is a
  prompt to hand an AI so the list it writes pastes straight in.
- **One word at a time**, with everything optional except the word and what it
  means.

**The companion**

A small sphere of moving colour beside every card opens a conversation about
*that* card — the word, the sentence, the grammar — in whatever language you
ask in. It is told the card, your language pair, how the word is going, and
whether you have turned it over yet, so it will not give an answer away while
you are still trying to recall it.

Two models to choose from in Settings:

- **Apple Intelligence**, built into macOS, nothing to download. It does not
  speak Russian yet.
- **Gemma 3 4B**, installed from Settings in one click — 3 GB from Hugging Face,
  run through [MLX](https://github.com/ml-explore/mlx-swift-lm) entirely on your
  Mac. It speaks some 140 languages and reads a card's picture. By installing it
  you accept Google's [Gemma Terms of Use](https://ai.google.dev/gemma/terms).

Nothing you ask either model leaves the machine.

**And a game** — WordFall, a RealityKit vocabulary game, fed from your own decks.

## Install

Download `Words-1.0.0.dmg` from
[Releases](https://github.com/Ta2-me2/Words/releases/latest), open it, and drag
Words to Applications.

The first launch needs one extra step. The app is signed, but not with a paid
Apple Developer certificate, so macOS will say it cannot verify the developer
and refuse to open it:

1. Open **System Settings ▸ Privacy & Security**.
2. Scroll down to the line saying Words was blocked, and click **Open Anyway**.
3. Confirm. macOS remembers the decision; every later launch is ordinary.

If you would rather not take anyone's word for what you are running, build it
yourself — it is four commands below, and nothing in it needs an account.

## Requirements

- macOS 26 or later, Apple silicon. The local companion needs macOS 27.
- To build: Xcode 27 (Swift 6.4).

## Building

```bash
git clone https://github.com/Ta2-me2/Words.git
cd Words
open Words.xcodeproj
```

Build and run from Xcode. The first build resolves the Swift packages and will
ask once to trust MLX's build plugins — choose **Trust & Enable**.

From the command line the same flags have to be given up front:

```bash
xcodebuild -project Words.xcodeproj -scheme Words -configuration Debug \
  -derivedDataPath build -skipPackagePluginValidation -skipMacroValidation build
```

MLX compiles Metal kernels, so the toolchain has to be there. If the build stops
at `cannot execute tool 'metal'`:

```bash
xcodebuild -downloadComponent MetalToolchain
```

The app is signed ad-hoc and is not sandboxed; no developer account is needed to
build or run it.

To build the disk image a release page carries:

```bash
Scripts/make-dmg.sh
```

## Checks

```bash
Tests/run.sh
```

927 checks over the scheduler, the queue, the day's allowance, decks and
subdecks, the import formats, the Anki reader, the streak, the store and what the
companion is told — compiled as a command-line binary, so they run in a couple of
seconds and need no window.

## Where your words live

```
~/Library/Application Support/Words/
  Library.json     every language, deck, word and review
  Media/           recordings, photographs, drawings
  Games/           what the game remembers
  Models/          a companion model, if you installed one
```

Nothing else is written anywhere, and nothing is sent anywhere.

## How it is built

[`ARCHITECTURE.md`](ARCHITECTURE.md) is the long answer: the layers and which way
they depend, why the scheduler is written out instead of imported, what was
learned from asking the models questions, and which decisions were made twice.

```
Words/
  App/            the window, the menu bar, the sidebar, the language switcher
  DesignSystem/   palette, metrics, surfaces, empty states, activity calendar
  Model/          languages, decks, words, cards, gender, import, audio, history
  Services/       speaking a word aloud, and recording one
  Scheduling/     when a card is next wanted
  Persistence/    the library on disk, and the store the interface talks to
  Anki/           reading Anki packages, and guessing where their fields go
  Features/       Home, Words, Library, Statistics, Study, Games, Settings
Tests/            checks for everything above that has no window in it
Packages/
  WordFallSDK/    the game
  WordsCompanion/ installing and running a language model on this Mac
```

## Licence

MIT — see [LICENSE](LICENSE). The packages under `Packages/` are part of this
project and covered by the same licence. The models and libraries it downloads
are not: Gemma is Google's, under its own terms, and MLX, swift-huggingface and
swift-transformers are each under their own.
