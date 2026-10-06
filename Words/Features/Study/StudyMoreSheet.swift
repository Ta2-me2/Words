import SwiftUI

/// "I want more": how many new words and reviews to add to today, and today
/// only.
///
/// Two numbers and a button. The settings are not touched — tomorrow is an
/// ordinary day — and the sitting starts straight away, because somebody who
/// asks for more wants to be studying, not looking at a Home screen.
struct StudyMoreSheet: View {
    let profile: LanguageProfile
    let deck: Deck?

    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AppClock.self) private var clock
    @Environment(\.dismiss) private var dismiss

    @State private var newWords = 0
    @State private var reviews = 0

    /// Worked out once, when the sheet opens. It cannot change while the sheet
    /// is up, and a form's body runs on every keystroke.
    @State private var available: (newWords: Int, reviews: [QueuedCard]) = (0, [])
    @State private var heldBack = 0
    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: deck.map { "More from \(store.library.path(of: $0)) Today" } ?? "Study More Today",
                subtitle: "Just for today. Your settings stay as they are."
            )

            Form {
                Section {
                    LabeledContent {
                        // Rebuilt once the day's figures are in, so the field
                        // is seeded with the default rather than with nought.
                        CountField(value: $newWords, in: 0...available.newWords)
                            .id(available.newWords)
                            .disabled(available.newWords == 0)
                    } label: {
                        Text("New words")
                        Text(newWordsNote)
                    }

                    LabeledContent {
                        CountField(value: $reviews, in: 0...available.reviews.count)
                            .id(available.reviews.count)
                            .disabled(available.reviews.isEmpty)
                    } label: {
                        Text("Reviews")
                        Text(reviewsNote)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            SheetActions {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Study") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(newWords == 0 && reviews == 0)
            }
        }
        .frame(width: 440, height: 290)
        .task { load() }
    }

    private var newWordsNote: String {
        switch available.newWords {
        case 0: "Every word has been started"
        case 1: "1 not started yet"
        default: "\(available.newWords) not started yet"
        }
    }

    /// Where the reviews would come from, said plainly: bringing a word
    /// forward is a real review, and the learner should know that is what it is.
    private var reviewsNote: String {
        let count = available.reviews.count
        guard count > 0 else { return "Nothing left to bring forward" }
        if heldBack > 0 {
            return "\(heldBack) held back by your daily limit first, then words due in the coming days"
        }
        return "Words due in the coming days, brought forward"
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true

        available = store.library.moreAvailable(for: profile.id, deckID: deck?.id, asOf: clock.now)
        heldBack = available.reviews.count { queued in
            store.library.entry(id: queued.entryID)?
                .card(id: queued.cardID)?
                .scheduling
                .isDue(onDayOf: clock.now, calendar: .current) == true
        }

        // Ten of each, or whatever there is. A default the learner can accept
        // with Return is worth more than a blank form.
        newWords = min(10, available.newWords)
        reviews = min(10, available.reviews.count)
    }

    private func commit() {
        store.studyMore(
            profileID: profile.id,
            deckID: deck?.id,
            newWords: newWords,
            reviews: reviews,
            at: clock.now
        )
        clock.refresh()
        // Replaces this sheet with the sitting rather than closing it first:
        // one sheet swapped for another, not a flicker back to Home.
        router.startStudy(deckID: deck?.id)
    }
}
