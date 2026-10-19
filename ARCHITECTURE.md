# Words

A local macOS application for learning foreign vocabulary. One window, one file,
no account. The only thing it ever asks the network for is a companion model the
learner chose to install, downloaded once; the words, the schedule and every
question put to that model stay on the Mac.

Requires macOS 26. Built with Xcode 27 (Swift 6.4), SwiftUI, Swift 6 with complete
strict concurrency and `MainActor` default isolation.

## The loop

Create a language → add words → see what is ready today → review → grade how
well the word came back → get the next date. Everything in the app serves that
loop.

## The window

The sidebar is navigation, not selection. Which language is being studied is a
separate question, answered by the switcher above it — a flag, a name, and every
other language behind it. The five sections are:

- **Home** — what today and tomorrow ask for, which way round the cards are
  asked, the streak, a year of activity, the words that will not stick, and,
  once there is more than one language with a history, how they compare.
- **Add Words** — a screen rather than a sheet, because adding is the thing done
  most often. Four ways in: one word at a time, a whole list pasted, dropped or
  chosen from disk, an Anki deck, or a package another copy of Words wrote. The
  one-word side is an empty card rather than a form — every field stands where
  the finished card puts what goes in it, so somebody who has studied a card
  knows what they are making while they make it. The two package sides are the
  same screen with different nouns: choose the file, see what is inside it and
  how a card will come out, say where it goes, watch it arrive.
- **Library** — every word in the language, with the decks under it in the
  sidebar and each deck's subdecks under that. Selecting a deck filters the
  table and narrows the sitting; selecting a deck with subdecks takes them in
  too.
- **Statistics** — the long view: vocabulary by stage, reviews a day, the next
  fortnight's forecast, and how the answers went.
- **Games** — a shelf of games played with the language's own words. One today,
  WordFall; a game is played in the window's main area beside the sidebar, and
  grows with the window.

The app's own preferences — how it looks, and which companion answers beside a
card — are behind ⌘, and behind the button next to the sidebar toggle, which
are the same window. There was briefly a popover there with the one preference
that existed at the time; two doors onto the same room, one of which showed half
of it, is how a learner comes to believe the other half does not exist.

## Three things worth knowing

**Gender is a fact about the word, not an article.** A word carries `f`, `m`,
`n` or `c`; what the language *shows* for that gender belongs to the language,
so the same word in two languages is marked two different ways. There are two
kinds of mark and the difference is not cosmetic — it decides what the voice
reads. German puts a word in front of the noun and you say it: *die Mutter*,
both words. Russian puts nothing in front of anything; its gender is a note a
dictionary prints beside the entry — *жен.* — and reading that aloud would be
reading out a footnote. `GenderMark` is that distinction, and everything
downstream asks it rather than guessing from the language code: speech takes
only the marks that are spoken, the card shows both, in one place.

A language is given articles only when its articles tell its genders *apart*.
Romanian has free indefinite articles and is written with labels anyway,
because *un* is both its masculine and its neuter — a mark that cannot answer
the question it is asked is not a mark. The Scandinavian three print the
*indefinite* article, because their definite one is a suffix on the word
(*bil* → *bilen*) and a preposed *den* would be wrong. French and Italian ask
the word as well as the gender, since the article elides in front of it:
*l'eau*, *lo studente*. Nineteen of the thirty-one languages have rules;
twelve mark no gender at all, which is the honest answer for Turkish or
Japanese rather than a gap.

A learner never has to reach for the gender control: typing "die Mutter" files
the word as *Mutter*, feminine, and the words written that way before the field
existed were lifted the same way when the file was upgraded to format 2 —
and again at format 4, for the eighteen languages that had no rules the first
time round. A typed article is read as the *citation form* it is, which is what
the word field asks for; German *der* is also a feminine dative and Dutch *de*
is the plural of every noun, so somebody filing a declined form gets the gender
of the headword they did not type, and the picker beside the field is how they
put it right. The articles that prove nothing are stripped without a guess:
German *ein* is masculine and neuter both, Norwegian *en* is legal in front of
a feminine, French *l'* is either gender.

**The first screen is a conversation, not a form.** A library with no language
in it has either never been used or has just been emptied, and both want the
same screen — so there is no "has seen the introduction" flag anywhere; the
library already answers the question, and the language the introduction creates
is what makes the answer change. It is gated on the file having really been
read, because a library that failed to open also has no languages in it, and
inviting somebody to start again on top of their own words is the one
unforgivable thing that screen could do.

The companion is drawn rather than animated: `CloudShape` is a handful of
overlapping circles filled as one path, and `CompanionMood` is a table of poses
it is eased between. Its *life* — breathing, bobbing, blinking, the wander of
the eyes — is worked out from the clock, so there is no timer to leak and it is
in the same place whenever a view is rebuilt; its *pose* is eased by hand,
because a `TimelineView` redraws every frame and SwiftUI's own animation would
be overwritten before it had travelled anywhere. It never leaves the screen
while the introduction runs. That is the whole trick: a wizard that replaces
its contents step by step reads as a form being filled in, and a character that
stays put while the room changes around it reads as somebody talking to you.

It has no mouth, so it smiles with its eyes and says nothing out loud. Asking
it to speak with a system voice would be a human voice coming out of a drawn
face, which is the wrong kind of surprise.

Which language somebody means is read from a table of greetings rather than
guessed by a recogniser, because one short word is not enough for one:
*hallo* is German, Dutch, Danish and Norwegian, and a recogniser that picks one
of them picks wrong three times in four. Both scripts are held — *привет* and
*privet* — since somebody who decided this morning to learn Russian has no
Cyrillic keyboard. Where a form is shared the companion asks, and that is the
best moment in the whole sequence rather than a failure of it. What it cannot
place at all it says so about, and offers the list or a language of your own.

**A card holds two languages, so it is laid out in two directions.** Arabic and
Hebrew read right to left and their meanings, written in Russian or English, do
not. So the direction is applied to each run of text in one language — the word
with its mark, the example sentence — rather than to the screen: flipping the
whole card would put the translation's full stop on the wrong end and its
listen button on the wrong side. Which languages those are is asked of the
system rather than listed, like the names and for the same reason. What it
moves is the order of things in a row (the mark to the right of the noun, the
listen button to the left of the sentence) and the base direction a mixed line
is laid against, which is what decides where a sentence's full stop lands. The
gender control is the one place the direction is written out by hand: it is an
AppKit segmented control underneath and lays its segments out left to right
whatever the environment says, so its choices are reversed instead.

**Languages the learner added.** `CustomLanguage` is a name and a flag under a
private-use code, kept in the library document so it travels with an export.
It carries nothing else, because inventing the grammar of a language the app
has never seen is the one thing it must not do: a custom language behaves
exactly like the twelve shipped ones that mark no gender. Its name is asked
for from everywhere — a card's header, a profile's subtitle, the text handed
to the model — so the catalogue holds a registered mirror of what the library
has, written at the two points where the library changes. It cannot be deleted
while a profile is studying it, and because it has no code the system knows,
every installed voice is offered for it rather than none.

**Practice changes nothing.** Going over today's cards again, or an endless
shuffle of a deck, moves no schedule and starts no new word — but it is written
down, marked `isPractice`, and left out of every figure the app shows. Time
spent is time spent; it must simply never be mistaken for the work the scheduler
did.

An endless sitting draws its next card rather than queuing it: every word in
scope carries a weight, the next one is picked at random in proportion to it,
and the weight is what the last answer said about the word. A queue of fixed
length is a loop — answer the first dozen words and they come round for ever
while the rest of the library is never reached — which is exactly what
`EndlessDeck` exists to avoid. A word not yet shown this sitting outweighs one
already known, so the first pass covers new ground; a word answered Again is
worth nine of one answered Good and thirty of one answered Easy; and no weight
is ever nought, so nothing is unreachable. None of it survives the sitting.

**Asking the system anything costs something.** `speechVoices()` is a trip out
of the process — 45 to 105 ms — so the answer is cached, and the Library asks it
once for the whole table rather than once per row. The catalogue of voices that
could still be installed is read from the file macOS publishes for its own
settings, so the list is the system's rather than one written here that would go
stale. Neither can be downloaded by an application: that list leads to System
Settings.

**A word is heard, not stored twice.** A word with a recording of its own plays
that file; a word without one is read by the system voice chosen for its
language. Nothing is generated and kept: a voice can be changed at any moment,
and a library full of files made by last month's voice would be a library that
had quietly gone out of date. What the Library's Audio column shows is
therefore three states — a recording of one's own, the system voice, or nothing
at all because the Mac has no voice for that language.

**A speaker that cannot speak is not drawn.** Nothing in the app offers to say
a word it cannot say: no speaker beside the card, no "P to hear it" under it,
no icon in the Audio column, and no link to System Settings to go and install a
voice that was never published. Georgian is the case that proves it — macOS has
no voice for it and offers none, so a Georgian card carries no sound at all
until the learner records one. What such a word gets instead is a
**transcription**: free text under the word, on the prompt side and the answer
side both, written however its learner writes sounds down — IPA, the sounds
spelled in an alphabet they read, a rhyme. It travels with the word rather than
with the language because it is the word's, and it is never a clue: it sits
with the word wherever the word is, so a card asking for the word keeps it back
until the word is out.

**Stopping is not finishing.** A sitting with a plan is written down after
every answer, so closing the window leaves the queue, the order and the count
exactly where they were, and opening it again says "Resumed" rather than
starting over. A snapshot belongs to one day and to one scope; tomorrow it is
gone, and nothing is lost by that, because a card left unfinished is either
still due or still new and comes back on its own. An endless sitting is not
kept: it is a stream rather than a queue, with no place in it to return to.

**A learning step still falls inside the day it was set on.** A word answered at
four o'clock is wanted again at ten past, and until then it is unfinished work
rather than finished work — so the day's figures count it, and the queue offers
it. Counting only what is ready *this minute* is what let a review abandoned
half-way report the day as done. Reviews are unaffected: their dates are whole
days already.

**Every word gets its own interval, and the buttons say so in advance.** There
is no ladder of fixed intervals anywhere: two words learned in the same sitting
can end up months apart, because the schedule is read off what each card's own
history says about it. The four grade buttons carry the dates they will give,
worked out by the same code that will then give them — including the few
percent of spread that keeps a hundred words learned together from arriving
together for the rest of their lives, which is why that spread is drawn from a
number the card owns rather than from chance.

**How much forgetting is acceptable is the learner's to decide.** One slider per
language, from 80 % to 97 %, and it is the single number that decides how much
work a day holds. It belongs to the language rather than to the app because
appetite differs, and it is passed into the scheduler rather than stored in it,
because a goal is not an implementation detail.

**A picture is offered to the words that need one, and to no others.** Of the
last five answers on a card, three or more Again or Hard, and the app quietly
offers a board to draw on — after the meaning is on screen, never before, since
a learner who cannot remember the word has nothing to draw a picture of. One
moving window covers both cases worth catching (three bad answers in a row, and
a word lost again and again over a month) and, because it moves, it lets go on
its own: three good answers push the bad ones out and the offer stops appearing
without anybody dismissing it. Once a drawing exists, that same rule decides
whether it is shown as a hint *before* the answer.

**The daily allowance belongs to whatever is being studied.** A deck spends its
own, counted against its own limit, so working through one shelf does not use up
another's day. The language-wide figure can therefore read nought while a deck
still has words to start — which is the point of studying a deck at all. A
subdeck that sets no limit works to the deck it sits in before it works to the
language, and a deck studied as a whole counts every word started in any of its
subdecks against its own limit.

**Decks go two levels deep, and a deck contains its subdecks.** "Germany" holds
"A1" and "A2"; "A1" holds words and nothing else. Studying "Germany", counting
it, filtering the table by it or playing a game with it all take in its
subdecks, and a word can still be filed in "Germany" itself. A third level is
where a sidebar stops being a map, and every list of decks in the app would
have to learn to draw a tree — so everywhere but the sidebar a subdeck is named
by where it sits, "Germany › A1", and listed straight after its deck. Taking a
deck away never takes a word: a subdeck's words go up into its deck, and a deck
at the top takes its subdecks with it and leaves every word in the language.
The sheet that makes a deck shows the sidebar as it is about to look, and can
make the subdecks in the same breath, because a structure is easier to see
than to describe.

**A limit on reviews moves work; it does not remove it.** A language can cap
the cards it takes on from earlier days — none by default, because whatever a
limit holds back is simply still due tomorrow. It is counted from the cards
themselves (a word from an earlier day, answered today, once however often it
lapses) and across the whole language rather than per deck: new words are a
shelf's business, reviews are the cost of everything already learned. Work
already begun today — a word met this morning, one forgotten an hour ago —
always continues, so a limit never leaves a word half-learned. What is held
back is what can best afford to wait: the earliest-due cards go first.

**"I want more" changes today and nothing else.** Once the day's cards are
done, the learner can add new words and reviews to today without touching the
settings. The new words are a number added to every allowance for the day; the
reviews are a list of cards chosen at the moment of asking — first whatever the
review limit held back, then the words due soonest — and each leaves the list
by being answered. Bringing a word forward is a real review, asked for out
loud, and FSRS measures the gap that actually passed, so a word answered early
gains less from it. The extra is stamped with its day and ignored on any other,
which is how tomorrow stays an ordinary day.

## Layers

```
Words/
  App/            The window, the menu bar, the sidebar, the language switcher
  DesignSystem/   Palette, Metrics, surfaces, empty states, activity calendar
  Model/          Languages, decks, words, cards, gender, import, audio, history, insights
  Services/       Speaking a word aloud, and recording one
  Scheduling/     When a card is next wanted
  Persistence/    The library on disk, and the store the interface talks to
  Anki/           Reading Anki packages, and guessing where their fields go
  Exchange/       Zip, and the package Words writes for another copy of itself
  Features/       Intro, Home, Words (add + edit), Library (+ decks), Statistics, Study, Games (+ Dictation), Export
Tests/            Checks for everything above that has no window in it
Packages/
  WordFallSDK/    The game, as its developer ships it: a local Swift package
  WordsCompanion/ Installing and running a language model on this Mac (MLX)
```

The dependency direction is one way: `Features` and `App` know about
`Persistence`, `Persistence` knows about `Anki`, `Exchange`, `Model` and
`Scheduling`, and `Model` and `Scheduling` know about nothing but Foundation.
`Anki` and `Exchange` add only what macOS ships — SQLite and the Compression
framework. That is what lets the whole
learning loop be checked without launching the application.

### Model

`Library` is the entire document: `profiles`, `decks`, `entries`, `reviews`,
and the `sessions` that were stopped rather than finished. A
`LanguageProfile` is a language being learned, the language its meanings are
written in, and the flag it is recognised by. A `Deck` is a shelf inside one
language, with an optional parent and an icon — a system symbol, which tints
like every other sidebar row, or an emoji, drawn as itself. A word may sit on
one deck or on none. Deleting a deck asks which of two things was meant: a deck
made by hand is a shelf, and its words move up a level; a deck that arrived as a
package is the words, and they go with it — recordings, photos and drawings
included, review history kept. Files are only ever deleted once nothing left in
the library points at them, so two words sharing one recording can never cost
each other their sound. `DeckScope` is what studying a deck is drawn from — the deck,
its subdecks, and the limit it works to — worked out by the library, which is
the only thing that knows which decks sit inside which, and handed to the
queue, which then never has to ask. The tree is repaired whenever a file is
read: a link to a deck that is not there, to itself, to another language or
from a third level brings that deck to the top, and nothing is deleted.
Repairs made while decks are being written one at a time tolerate a parent that
has not arrived yet, so the result never depends on the order of two lines. An `Entry` is a
word, its meaning, a note, and the `Card`s asked about it — one `.recognition`
card today, with `.production`, audio, images and other exercises fitting the
same shape later. Deleting a word takes its cards with it; the review history is
never deleted, because it is a record of study that happened.

`EndlessDeck` is the order of an endless sitting, and the one place in the app
where chance decides anything. It is a value with an injectable generator, so
the checks below can assert what a distribution does rather than hoping.

`WordImport` reads a pasted or dropped list — `word;meaning;gender;
[transcription];example;translation;note`, everything after the meaning
optional. Two of those fields are recognised rather than positioned, which is
what lets the format grow without every list written against the old one
breaking: the gender by being `f`, `m` or `n`, so a third field that is not one
of those is an example; the transcription by the brackets it is written in —
`[ˈvasɐ]`, `/ˈvasɐ/` — which no example sentence is, so it needs no column of
its own and no empty one when it is missing. An empty column kept for a field
the language does not have (a gender, in a language with none) is dropped, so
that a note written last is read as the note. It forgives what a person's file
actually contains — blank lines, Markdown headings and bullets, tabs, a dash
where a semicolon should be — and reports
what it could not read instead of guessing. Nothing is added until the plan has
been shown: how many words, which are already in the language, which lines were
skipped.

`ListPrompt` writes the instructions A List offers to copy into an AI chat: the
format and nothing else, for the language's own names, genders and articles —
the request itself is the learner's to write underneath. It is written from the
parser's rules rather than beside them, and the checks read lines built the way
the prompt describes, so the two cannot drift apart unnoticed. A learner's edited
version is kept on the language; the standard one is never stored, so a learner
who never changed it gets the standard one as it improves. The code fences an
AI puts round a list are skipped by the import.

### Handing a deck to somebody

A library that can only be filled is half a library. `Exchange` is the other
half: `.wordspack`, a plain zip holding `words.json` and a `Media/` folder, with
a `README.txt` saying what it is for whoever opens it without the app. The JSON
is the library's own types — languages, decks, words, reviews — encoded as the
library encodes them, so nothing is lost in translation and nothing has to be
kept in step by hand. `format` is the promise: a package from a later version
says so and is refused, rather than read wrongly.

`ZipArchive` reads; `ZipWriter` writes, entry by entry so an archive is never
held in memory whole. Text is deflated and media is not: a JPEG deflates to
slightly more than it started as.

- **What goes.** `ExportPlan` turns a set of ticks into a package. A deck keeps
  the deck above it only when that one is coming too, so exporting "A1" hands
  over "A1" rather than an empty "Germany" with something hidden inside it.
  Each kind of file can be left behind on its own — the words stay and the
  links come off them — and so can the schedule, which is off by default:
  a deck that arrives already half-learned by somebody else is a deck with a
  wrong schedule. The voice identifier never travels; it is a fact about a Mac.
- **What arrives.** `PackageImport` works out the whole of an import before
  anything is written, and gives everything new identifiers. A package is
  somebody else's library, and keeping its identifiers would let an import
  overwrite a word already here — including its schedule, the one thing in the
  app that cannot be got back. New identifiers make an import a thing that only
  ever adds; words are matched by how they are spelled, so opening the same
  package twice adds nothing the second time, and a deck of a name already in
  that place is that deck rather than a second one.
- **Files before words.** The store writes the media first and the words after,
  so nothing ever points at a file that is not there; a file that cannot be
  written is dropped from the word that wanted it. A file missing from the
  library at export time is reported and left out rather than failing the
  export — a lost photograph is not a reason to lose a thousand words.
- **Where it is.** Export is its own section, showing every language at once
  rather than the one being studied: the deck somebody wants to hand over is
  often not the one they are in. Opening a package is a fourth side of Add
  Words, because that is where adding words already lives.

`Speaker` decides how a word is said — its own file or the language's voice, the
article included, and the example sentence after it if the language is set to
read it — so no screen has to know which. `Recorder` writes the learner's own voice to a
temporary file, and only a recording that is kept is copied into the library.
Both live in `Services`, both are given to the interface through the
environment, and neither knows anything about the vocabulary.

Files that belong to a word — a recording of the word, a recording of its
example, a photograph or a drawing — live in `Media/` beside the library rather
than inside a document that is meant to stay readable, and go when the word goes.
Their kind is read from their first bytes (`MediaKind`), not from their names:
decks in the wild carry pictures called `photo.jpg!d`.

A word has **one place for a picture**, filled one of two ways. A `Picture` is a
photograph and is part of the word: shown with it on every card, before the
answer and after. An `Association` is a drawing the learner made, and it is
offered rather than shown. The store keeps them apart — a photo put on a drawn
word replaces the drawing, and a word with a photo is not given a drawing — so
the card never has two images competing for one memory.

`Association` is a drawing hung on a word. What the model holds is a path, a
stroke count and a date; the drawing itself is a file in Apple's own format —
`PKDrawing`'s data representation, the type PencilKit reads and writes — named
after the word it belongs to. That is what makes it portable: an association is
a document in its own right, readable by anything that understands the format,
and a library exported as a folder carries its drawings unchanged with no
conversion step to write. `AssociationPrompt` holds the rule for when one is
worth offering, and is checked without a window like everything else here.

`Insights` turns that history into everything the Home and Statistics screens
show: the activity calendar, today's and tomorrow's plan, the words that keep
being forgotten, the forecast, the accuracy. Pure functions over the model, so
no view counts anything for itself and every number on screen can be checked
without a window.

`TrueRetention` answers the one question the rest of the app takes on trust:
whether the schedule keeps its promise. The learner asks for a share of words to
still be there when they come round — nine in ten by default — and this counts
the share that was. Anki shows the same figure under the name true retention,
and the word that matters in it is *true*: only a scheduled review of a card
that had been waiting on an interval is counted. A learning step answered three
minutes after the last one is not a memory being tested, practice is chosen
rather than asked for, and counting either would quietly turn a hard month into
a good one. The screen cuts it three ways — the last month against the goal, by
how long the word had waited, and over time with young cards and known ones
apart — because a figure that is fine on three days and poor on three months is
not a memory problem but a scheduling one, and the two want different answers.
It also measures the app's own rule rather than FSRS's: the words answered Easy
on sight, set aside for a month on that alone, counted separately so that the
rule can be judged.

`StudySnapshot` is a sitting that was left: the cards still in front of it, the
ones already done, the count it started with, and the day it belongs to. At most
one per language, deck and mode; writing a new one throws away everything that
is no longer today's.

`DailyExtra` is today's "I want more" for one language: a number of extra new
words and a list of cards brought into the day. At most one per language, never
older than today, and thrown away the moment a newer one is written.

`Library.recordReview` is the whole learning loop in one method: the scheduler
decides the new state, the card takes it, the history gets a line. It lives in
the model so it can be tested without a window.

### Scheduling

`ReviewScheduler` is a protocol with one method, and the split beneath it is the
point of the layer.

`FSRS` is the memory model and knows nothing else: no stages, no clock, no
calendar. Two numbers describe a card — **stability**, the days it can go before
recall falls to nine in ten, and **difficulty**, from 1 to 10 — and every answer
moves both. The formulas and the twenty-one default weights are FSRS-6 as
published by the open-spaced-repetition project and shipped with Anki. They are
written out rather than pulled from a package: this is one page of arithmetic,
it is stable across versions, and every line of it is checked. What is *not*
here is the optimiser that fits the weights to one person's history; the
published defaults are used until it exists, which is FSRS's own advice for the
first several hundred reviews, and only `FSRS.defaultWeights` has to change
after that.

`FSRSScheduler` knows about the day: learning steps of 3 and 15 minutes, one
relearning step of 10 minutes, a floor of one day after a lapse, whole-day
intervals landing at midnight, and a ceiling of a hundred years. It is
configured by a value, not by constants scattered through it.

Easy as the very first answer a word ever gets is "I Know This Word" on the
button, and the scheduler treats it as that rather than as a quick recall:
there is nothing yet for the word to have come quickly compared with. The
memory is declared instead of measured — the stability that puts the word a
month out at the learner's own retention, and the difficulty of an easy word —
so it lands past the three weeks that count as known well, and from then on it
is an ordinary card that can lapse like any other. Every later Easy is the
ordinary one. Only a sitting that counts offers it: practice changes nothing,
so its Easy stays Easy.

`ScheduleMigration` replays a card's whole history through the new arithmetic
when a library written by the old algorithm is opened. Nothing is guessed and no
due date moves — which is what the review history has been kept for since the
first day.

No screen computes a date, and no screen asks how an interval was reached.

`StudyQueue` decides what a sitting is made of — learning first, then reviews
oldest first, then as many new words as the day's allowance permits — which is a
separate question from when a card is ready, and is kept in a separate file.
New words come in the order they were added, or, if the language asks for it,
in a random order drawn from each card's own fixed number and the date: the
same words all day, so a sitting stopped and begun again goes on with them,
and a different handful tomorrow.

`StudyDirection` turns a language's cards around — the meaning shown, the word
recalled — or mixes the two, and is chosen beside Start Review. It is the same
card and the same schedule asked from the other side, not a second card: the
learner asked to practise the other way, not for twice the reviews. A mixed
sitting draws each card's side from the card and a number of the sitting's own,
so a word being learned keeps its side between steps. Sound never moves: it is
always the word and the example, and always after the answer, because the
meaning is what the learner already speaks.

`Streak` counts days in a row from the history of answers — any answer, practice
included, in any language: a streak is about coming back. The only part of it
that is stored is `Library.streakFreezes`, because a freeze is a decision rather
than something that happened. Two a week, for today only, and only when there is
a streak for it to keep; a frozen day keeps the run without adding to it, and a
frozen day that was studied after all counts as studied and gives its freeze
back.

### Persistence

One JSON file at `~/Library/Application Support/Words/Library.json`, written by
an actor through a temporary file and an atomic replace. A file that cannot be
decoded is moved aside intact, never overwritten. `LibraryStore` holds the one
in-memory copy, autosaves 800 ms after the last change, and saves immediately
when a session ends or the app quits.

### Anki

Anki decks have no fixed shape: each author decides what the fields are and how
a card is laid out, and three decks examined when this was written had three
unrelated structures. So the import does not pretend to know. It reads, guesses,
shows the guess as a real card, and lets the learner correct it.

- `ZipArchive` and `AnkiPackage` read a package and interpret nothing. Entries
  are stored or deflated, which the Compression framework decodes; the database
  is SQLite. When a package holds both `collection.anki21` and
  `collection.anki2`, the older one is a stub whose one note says "please update
  Anki", and it is ignored. The newest format compresses everything with zstd,
  which macOS has no decoder for: it is refused with the one sentence that fixes
  it — export again with "Support older Anki versions".
- `AnkiText` takes an Anki field apart: markup off, entities decoded, tables kept
  as lines, `[sound:]` and `<img>` pulled out as files, `N/A` recognised as empty.
- `AnkiMapping` holds which field goes where, **per note type** — a note type is
  what gives its notes one shape, so a card that comes out right means a deck
  that comes out right. Its first guess uses the field names, which language a
  field is named after, where it sits on Anki's card, and what is actually in
  it: a field that is the same in every note is an author's name, a field of
  digits is an id, and a single recording belongs to the word or the example
  depending on whether its size keeps pace with the length of the sentence.
  Several recordings go by their names first — "Audio_Wort" reads the word
  however heavy its files — then by which one keeps pace with the example. A
  field with nothing in it but "der", "die" and "das" (or `m`, `f`, `n`) is the
  article, however empty it is for the words that are not nouns, and a field of
  its own in the note, like "Plural" or "Verbformen", is labelled with its name.
  The
  guess is a guess; the preview exists because roughly one deck in ten will need
  a correction, and chasing the other one in ten is not the aim.
- `AnkiImport` pours notes through the mapping into a plan. A German noun
  written the way a dictionary writes it, "die Ansage, -n", becomes a word, a
  gender and a plural in the note; an article in a field of its own says the
  gender outright and wins over one typed into the word. A word is a duplicate only if its meaning is
  the same too: "der Anschluss" as a connection and as a train to catch are two
  words.
- Sound is all or nothing: the deck's recordings where it has them, or Words'
  voice for everything. A card that reads the word in one voice and the example
  in another sounds like two apps.

`CardFace` is the card, extracted from the study sheet so the import preview is
the card that will be studied rather than a sketch of it — including its
recordings, played straight out of the package. It shows either side first; the
word keeps layout priority over its article, because a selectable text in a row
is offered half the row and cut short before the article has taken its share.

The card is laid out by a small `Layout` of its own. Everything on it is measured
first, and the photo gets the height that is left, between a floor and a
ceiling: large before the answer, smaller once the meaning, the example and its
translation have arrived. A fixed-size photo pushed exactly those off the bottom
of the sheet. The note is the one thing allowed to run past the edge, where it
scrolls, because a card without its note is still a card and a card without its
example is not.

### Drawing

macOS has no `PKCanvasView` and no `PKToolPicker`; Apple ships those for iPad
only, and the header says so — everything else in PencilKit is here. So the
board, the tools and the gestures are this app's, and the ink is not: every mark
becomes a `PKStroke` in a `PKDrawing` and is drawn by PencilKit's own renderer,
which is why a pencil looks like a pencil. Shapes are strokes too — an arrow is
two, because one path cannot lift off the paper — so they erase, undo and export
exactly the way a hand-drawn line does. There is no text tool: a word already
has its meaning written under it, and an association made of words is not an
association.

Two things about that renderer are worth knowing. It lightens dark ink when it
draws into a dark appearance, which is right on a dark canvas and wrong here, so
drawings are always rendered in the light appearance — this paper is always
paper. And `PKDrawing` cannot be built in a process with no bundle identifier:
PencilKit writes to preferences on the way, and a command-line binary traps.
That is why the drawing lives in `Features` and nothing below it knows about
PencilKit at all — the checks below run as a command-line binary.

### The card assistant

Beside every card in a sitting is a small sphere of moving colour that opens a
conversation about that card, through the Foundation Models framework.
`CardAssistant` holds one conversation for one card and goes when the card does;
`AssistantText` writes everything the model is told, and the checks read it
without the model.

- **Which model.** Whichever the learner chose in Settings — Apple's, or one
  they installed (below). Private Cloud Compute — Apple's larger model with a
  longer memory, reasoning and pictures, at no cost to the app — is a managed
  entitlement Apple grants to developers in the App Store Small Business
  Program; the app uses it when it is signed with
  `com.apple.developer.private-cloud-compute` and the service is ready, and
  every request fails without it, so nothing else ever tries. The choice is one
  line in `CardAssistant.currentSession()`, because every model reached this way
  is a `LanguageModel`: the instructions, the card, the safeguards and the
  window above them do not know which one is answering.
- **What it is told.** The instructions (the app's own words only): the
  languages, the size of the library, words known well, the streak, whether the
  sitting counts, and how to answer. The card (in the prompt, because its text
  may come from somebody else's deck): the word with its article, the meaning,
  example, translation, note, deck, how the word is going, which way round the
  card is asked, whether it has been turned over — and its picture, attached,
  where the model can see pictures (macOS 27).
- **What was learned from asking it.** Measured on this Mac, the model on
  device answered grammar questions with confident mistakes when prompted
  loosely, so every rule that mattered moved next to the question. Told once
  not to give the answer away, it opened a hint with the meaning; the answer
  is now named and forbidden beside each question while the card is face down.
  Told to reply in the learner's language, it answered Russian in English; the
  app now names the language, found with `NLLanguageRecognizer` and leaning to
  the learner's own languages when a short Russian question reads as
  Ukrainian. Given a library search tool, it did not call it for Russian
  questions and invented the library's contents — so the tool is given only
  to the cloud model, words a question names are looked up by the app and
  stated as facts, and the app itself shows "In your library: …" under the
  question, whatever the answer says.
- **Keys.** While the assistant is open the card's own shortcuts are off: a
  "3" typed into a question must never grade the card.
- **Cost.** The sphere turns only under the pointer or while an answer is
  written; turning all the time it held an idle sitting at 7% of a processor.
- Russian is not among the languages Apple's models support (neither the one
  on the Mac nor the cloud one, in 27.0); it answers, but with more mistakes
  and without the guardrails a supported language gets. An error for an
  unsupported language is explained rather than shown raw. A model the learner
  installs is the way out of that: Gemma speaks Russian.

### A model of one's own

Words › Settings… (⌘,) has two tabs: General, and AI Companion — which model
answers beside the cards, and installing the ones that run here. Settings is its
own scene in `WordsApp`, so `SettingsLink` works from inside a sitting; the
choice is one string in `AppSettings.companionID`, `"apple"` or a model's id.

`Packages/WordsCompanion` keeps the machine-learning half at arm's length: the
app target sees a catalogue, a folder and a factory, and nothing of MLX. Inside
it, `CompanionModel` is what is offered — for now one, Gemma 3 4B, quantised to
four bits by mlx-community, 3.03 GB, which sees pictures — and `CompanionStore`
does the three things a model needs:

- **Getting it.** `HubClient.downloadSnapshot` fetches the weights from Hugging
  Face straight into `~/Library/Application Support/Words/Models`, a `HubCache`
  of the app's own rather than the one in the home folder, so removing it is
  removing a folder. Only `*.safetensors`, `*.json` and `*.jinja` are asked
  for; nothing else in the repository is wanted. A stopped download keeps what
  arrived and carries on from there, which is what makes three gigabytes over a
  hotel connection survivable. `CompanionInstaller` lives as long as the app,
  not as long as the window: closing Settings does not throw a download away.
- **Running it.** `CompanionStore.languageModel(for:)` returns an
  `MLXLanguageModel`, which *is* a `FoundationModels.LanguageModel` — the same
  `LanguageModelSession` as Apple's, so prompts, streaming, the picture and
  every safeguard above are untouched. It is loaded from the folder on disk
  rather than by name, so nothing reaches the network at answer time, and the
  registry's configuration is kept for its end-of-turn tokens, which Gemma
  needs to know when to stop.
- **Letting go of it.** Four bits times four billion is about 2.5 GB of unified
  memory, held for as long as the weights are loaded. The end of a sitting
  unloads them (`CompanionStore.unload()`); the next question loads them again,
  which is a few seconds once.

The licence is the learner's to accept, not the app's: installing asks, names
Google and the Gemma Terms of Use, and offers to open them first. Ollama is not
involved — a model installed for Ollama is in Ollama's own packaging, and asking
somebody to install a second application to use a feature of this one is the
thing being avoided.

### Example sentences

A word with an example on it is worth more than a word without one: it is what
the card shows under the meaning, and it is what the dictation game plays. Most
libraries have hundreds without. So the companion writes them, in the three
places where somebody is already looking at a word that has none.

- **One word being typed in.** A button beside the Example field in Add Words.
  The fields fill in and can be typed over — what the model wrote is a draft
  like anything else in that form, and it is saved with the word or thrown away
  with it.
- **A list being pasted.** The same button in each row of the preview, in the
  Example column. What comes back is kept beside the plan rather than in it,
  filed under the word: the list is read again from the text on every keystroke,
  and a sentence that took the model five seconds must not vanish because a
  letter was typed three lines below it. The two are put together once, at the
  moment of import.
- **Words already in the library.** A run over every word in the language, or in
  a deck, that has no example — from the Library's toolbar, from a right click
  on a selection, or from the dictation game. One at a time, oldest first,
  shown as they arrive. Nothing reaches the library until the learner has read
  it: a model writing grammar for somebody who cannot yet check it is exactly
  the case where a review step is not optional.

What all three share is `SentenceWriter` — the session, the options, the asking,
and how a failure is described in a line that fits beside a field.
`SentenceMaker` is the run over many words and asks through the same two calls;
`SentencePrompt` holds what the model is told and what counts as an answer.

The reading is the part worth writing down, because it is what has to survive a
model going wrong. Models answer tidily most of the time and then, every so
often, with a label, a bullet, quotation marks, an apology, or a paragraph
explaining the sentence they have just written. So the answer is searched rather
than parsed: the first line that is a sentence using the word — length checked,
word checked by its stem so an inflected form counts — is the sentence, and the
next line that is not that sentence again is the translation. Lines are tried in
two passes, those ending the way a sentence ends before the rest, because "Here
is an example with Haus, which means house:" mentions the word too and is not
the answer. A sentence and its translation on one line are split on the dash
between them. A translation that runs to an essay is dropped while the sentence
is kept; an answer with no sentence in it at all is refused, because a wrong
example is worse than none. The model is also held to 200 tokens and a low
temperature: an example sentence is wanted correct, not interesting, and a
runaway answer on a Mac costs the learner the wait.

### Dictation

The app's own game, and the one that practises the half of a language the rest
of it cannot: hearing it. A phrase is read aloud, its shape is on screen — how
many words, and what each begins with — and the learner types it back.

- **What it is played with.** Three things, each switched on or off: the words
  of the language one at a time, the example kept with a word, and sentences
  written straight into the game. The first two are built from the library
  every time the game opens rather than stored, so a word renamed or deleted
  changes the game at once; what is kept is the progress, under a key that
  survives the editing.
- **Where the companion fits.** Asked to, it writes an example for each word
  that has none — and writes it onto the word, as its example, not into the
  game. The work then counts twice: the sentence is played here, and it is on
  the card during an ordinary sitting. It is the same run the Library offers,
  described under [Example sentences](#example-sentences) below; the game opens
  it pointed at its own deck.
- **The screen.** Laid out like Home — what today asks for, what the game is
  played with, how it has been going, a year of days — and the sitting itself
  is a sheet, like a review. A box per word, with that word's shape under it,
  and the typing goes into the boxes themselves.
- **Why the boxes are AppKit.** A box has to hand the keyboard to its
  neighbour inside the keystroke that asked for it. SwiftUI's own focus cannot:
  `@FocusState` is applied on the next pass through the view tree, and a space
  typed quickly is followed by its letter before that pass happens — which is
  how "Das Haus ist sehr gross" came out as "Das | Hausi | sts | ehrg | ross",
  and why the boxes were once replaced by a single field. `WordBoxField` wraps
  an `NSTextField` whose delegate calls `makeFirstResponder` itself, which is
  synchronous: by the time the next key event is dispatched the next box is
  already the one being typed into. The same delegate makes the row read as one
  line of text — Backspace at the start of a box goes back to the one before,
  the arrow keys cross at the edges, Tab and ⇧Tab step, Return checks, and a
  phrase pasted into the first box lands a word in each. It also turns off the
  Mac's automatic spelling correction, which exists precisely to replace a
  half-typed foreign word and would mark the learner wrong for something they
  did not type.
- **Marking.** Word by word, and case and punctuation are not what is being
  practised, so they are not what is marked wrong. What was typed stays where
  it was typed, in the colour it earned, and the word it should have been
  appears under it in green: nothing moves, so the two are compared in place. A letter a keyboard will not
  make — `groß` typed `gross`, `Bär` typed `Bar` or `Baer` — is *almost*: shown,
  not failed. The grade nobody presses comes out of the answer: everything
  right first time is Easy, one word out is Hard, two is Again, and a phrase
  looked up is Again whatever was typed after it.
- **The day.** The same shape as the rest of the app — a few phrases never
  heard before, plus everything that has come round again — moved by the same
  FSRS. But it is the game's own schedule, in the game's own file: however well
  a phrase is typed here, no card's due date moves. A phrase that fell apart
  comes back four places later in the same sitting, and counts once.
- **Clearing up.** Deleting a language takes every game's file with it, and the
  orphans left by a game that was not running are swept on the next launch.
  Both work from the folders on disk rather than from a list in the code, so
  the next game added is covered without anybody remembering to add it.

### Drawn, not built

Two places draw instead of building views, for the same reason. A year of
activity is three hundred and seventy-one squares; three hundred and
seventy-one views — each measured, laid out, and given a tooltip whose text was
formatted whether anyone read it or not — cost a third of a second every time
Home opened. `ActivityCalendar` draws the year in one `Canvas` and answers the
pointer by working out which square it is over. `HoverNote` is what a drawn
shape says when the pointer is on it: the activity grid, the stage bar and all
three charts use the same small panel, because a shape with a number behind it
cannot be read.

A `Canvas` answers no hit test of its own, whatever content shape it is given,
so the tracking lives on the view around it and reads positions in the grid's
own coordinate space.

### Games

A game is a package somebody else writes, and the app treats it as one.
`Packages/WordFallSDK` is WordFall exactly as its developer ships it — a local
Swift package with its own sources, tests and documentation — linked into the
app target as `WortfallKit` and `WortfallCore`. Nothing inside it is edited
here; a new release is dropped in over the old one. (The game was called
Wortfall until 2.2.2; the rename changed its display name and icon, not its
modules, which is why the code that wraps it still says `Wortfall`.)

What the app supplies is the vocabulary and a place to keep what the game
learns:

- `GameVocabulary` decides which words go in: the whole language first, called
  "All Words" because a game's picker has to call it something, then every deck
  by name. A choice of three needs one right answer and two wrong ones, so a
  collection of fewer than three words is left out rather than offered and then
  refused. Words go in the way they are read — with their article — and are
  identified by the word itself, so the game's statistics survive an edit.
- `GameStorage` decides where: one file per game per language, at
  `Games/<game>/<language id>.json` inside the library's folder, so a
  vocabulary and everything that grew out of it travel and disappear together.
- `WortfallHost` owns one progress model per language. Deleting a language lets
  any queued write land first and then removes the file, so a save already on
  its way cannot bring it back; files left by languages that no longer exist
  are swept up when the library opens. Quitting waits for the game's last
  answers to be written, as the game asks.

A game changes no schedule and writes nothing into the review history. It is
practice by another name, and its own statistics are its own.

### Interface

`NavigationSplitView` with a real sidebar, a unified toolbar, one `.searchable`
in the window (it belongs to the Library), an AppKit table for the vocabulary, Swift
Charts for the statistics, `ContentUnavailableView` for every empty and failed
state, and a sheet for the review itself. Colours, fonts, materials and controls
are the system's; the only values the app owns are the spacings in `Metrics` and
the meaningful colours in `Palette` — the four the app started with, and the
streak's orange and a frozen day's cyan. The activity calendar shades days with
the accent colour at four strengths, relative to the learner's own busiest day.

The vocabulary is an `NSTableView` behind `WordTable`, not a SwiftUI `Table`.
A SwiftUI table gives each cell a hosting view of its own and measures each row
it shows. At 834 words, scrolling spent half its main-thread time
re-measuring rows that are all one line tall, and every row scrolled past kept
seven hosting views alive until the screen was left — at which point taking
them down took over two seconds, each one removing itself from observers the
window keeps in one list, so the next section opened late. Plain cells of one
fixed height, reused as they scroll away, cost the same at any size: scrolling
the whole table now keeps up with the wheel, and leaving it is a few
milliseconds. Sorting is `WordRow.sorted(_:by:)`, which the checks read; the
context menu is built in Swift as `NSMenuItem`s that run closures.

Before that, every icon in a row had become a plain image, not one that could
play a content transition: such a symbol is drawn through a RenderBox layer of
its own, and scrolling had waited on the render server for each row — invisible
in a profile of the main thread unless `wait_for_synchronize` is counted as
work rather than idle.

A word on a card can be selected to copy it, and the selected text then takes
the keyboard and keeps it after the selection is gone. `KeyboardReclaimer`
hands the keyboard back to the sitting's window before any plain key is
handled, so Space, the digits and P keep working; ⌘C is left alone.

The One Word / A List / From Anki control is a segmented control in the toolbar,
and its glass animation runs on the main thread for about a third of a second
after a click. Two things took those frames. The screen read the mode in the
same body that built the toolbar, so every click handed SwiftUI a new toolbar
and AppKit laid out the clicked control again mid-animation — the whole control
faded out and back. And each side of the screen was built from nothing on each
switch, which froze the lens for 130 ms before it jumped to its place. The mode
is now read only inside `AddModeSwitch` and the picker, and the three sides are
kept once made, with the hidden ones transparent, disabled and out of the
accessibility tree — so each keeps its own default button, focus and drops to
itself. Found by recording the control with `screencapture -v` and reading it
frame by frame against a build whose clicks changed nothing; the Animation
Hitches instrument did not report it.

A known one that is not the app's: with the window narrow enough that the
Library's area is under about 800 points, hiding and showing the sidebar makes
the toolbar's search field collapse into a button for a frame or two mid-
animation. It happens with nothing but the search field in the toolbar, so it is
`NSSearchToolbarItem` itself; a wider window does not do it.

## Checks

```
Tests/run.sh
```

Compiles the model, the scheduler, the queue, the insights, the import, the
session, the Anki reader and the store on their own and runs 1480 checks: the scheduling rules, the day's
allowance, the order of a sitting, decks and what a deleted one does to its
words, a deck's own allowance, subdecks — what a deck contains, whose limit a
subdeck works to, where words go when either is taken away, the two levels
nothing may get past and the file that tries, and which characters are an
emoji — flags and the profiles written before they
existed, every line of the import format and the messes it arrives in, a
transcription found by its brackets wherever it sits and a note that stays last
whatever was left empty before it, a dictated phrase split into words and
marked against what was typed — an accent dropped told apart from a word got
wrong — and the day it builds, what a tick in the export tree comes to and a
package written, read back byte for byte and opened into a library that already
has half of it, what the card
assistant is told and the library words a question names, the order of the
vocabulary table, an Anki article kept in a field of its own and recordings
told apart by their names, the
prompt handed to an AI and the lists written the way it says, new words in
random order that hold for a day, cards turned around and mixed, a word known
before it was ever studied, the streak and its freezes, what each of the
thirty-one languages does with gender — every mark, the shape an article takes
in front of a word, the articles that prove nothing, the invariants a new row
has to satisfy, a language somebody added and a library written before
Norwegian moved to the code its voices are under — which language a typed hello
means, the seventeen greetings more than one language writes the same way, and
the promise that every language can be reached by typing and not only by
pointing, the three kinds of sitting and the promise that
two of them change nothing, a daily limit on reviews and what it may never hold back, the extra a learner asks for once the day is done and the promise that it is gone tomorrow, a sitting stopped half-way and picked up again the
same day, the arithmetic of the memory model and everything it is not allowed to
do — a stability of nought, an interval that shrinks, a Hard longer than a Good,
a button that promises one date and gives another — reading a library written by
the algorithm this one replaced, when a word is struggling badly enough to be
offered a picture and when it has recovered enough to stop being offered one,
reading Anki packages in both older formats and refusing the newest one with a
reason, what is left of an Anki field once the markup is off, the guess about
where each field goes and correcting it, dictionary forms, homonyms that are not
duplicates, a picture called `cat.jpg!d`, a deck brought in with its recordings
and photographs, a photo and a drawing that may not share a word,
what an endless sitting shows next and how often — that the words being lost
come round several times more than the ones that are known, that no word is
shown twice running, and that the whole library is reached,
every statistic on the Home and Statistics screens, what counts as remembering
and what is left out of it — practice, a word being met, a learning step, a word
being got back, another language's answers — where the line between a young card
and a known one falls and how long a word waited before it was asked,
editing and deleting, the JSON round trip, a file that has been got at, and
closing and opening the app again.

A screen that only fills in after months of reviews can be looked at today:
`WORDS_DATA_FOLDER` points a build at another folder, so a library made up for
the occasion can be opened without going anywhere near the one somebody is
learning from.

## Not here yet

Translation, sync and achievements. Onboarding, the streak and export were on
this list and are not any more: the introduction creates the first language,
the streak is on the Home screen with its freezes, and Export writes a
`.wordspack` that another copy of Words opens — drawings included, copied
rather than converted, which is why they were stored the way they are.

From Anki: the newest package format (it needs a zstd decoder), a learner's own
progress (Anki's review log could be replayed through FSRS the way the SM-2
history was), nested decks (Words has subdecks now, but the import still brings an
Anki deck with chapters in as one deck; `Parent::Child` in the package is the
obvious thing to map onto them next), and fill-in-the-blank cards, which are not a card Words
has. The
FSRS optimiser is the notable one: until it exists the published weights are
used for everybody, which is what FSRS recommends until a learner has several
hundred reviews behind them, and fitting them properly needs a numerical
optimiser rather than another page of arithmetic. What exists now is the screen
that says whether it is needed — if what was promised and what came back agree,
there is nothing to optimise — and the history it would be fitted to, which has
been kept since the first day.

Gender rules exist for nineteen of the thirty-one languages. The other twelve
mark no gender at all, which is the honest answer for Turkish or Japanese
rather than a gap, and a language somebody adds marks none until it is told
otherwise. Every rule that is written has checks behind it — what the mark
looks like, whether it is spoken, and what the voice is handed — because a rule
nobody has checked is worse than no rule.
