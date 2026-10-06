import SwiftUI
import WordsCompanion

/// The review itself: one word at a time, its meaning on request, and four
/// answers.
///
/// A sheet, because a sitting is a task with a beginning and an end.
/// Everything on screen is either the word or the way to answer it.
struct StudySessionView: View {
    let profile: LanguageProfile
    let deck: Deck?
    let mode: StudyMode

    @Environment(LibraryStore.self) private var store
    @Environment(AppClock.self) private var clock
    @Environment(AppSettings.self) private var settings
    private let speaker = Speaker.shared
    @Environment(\.dismiss) private var dismiss

    @State private var session: StudySession?

    /// Whether the word on screen is one the learner keeps losing. Worked out
    /// when the card changes rather than on every pass through the body: it
    /// reads the whole review history, and the answer cannot change while one
    /// card is being looked at.
    @State private var isStruggling = false

    @State private var isEditingWord = false
    @State private var isDrawing = false
    @State private var isShowingHint = false

    /// The conversation about the card on screen, once the learner has asked
    /// for one. It belongs to that card and goes when the card does.
    @State private var assistant: CardAssistant?
    @State private var isAsking = false
    @State private var assistantReadiness: CardAssistant.Readiness?

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                header(session)
                Divider()

                if session.isFinished {
                    summary(session)
                } else {
                    card(session)
                }
            }
        }
        .frame(width: Metrics.sessionWidth, height: Metrics.sessionHeight)
        // Selecting a word to copy it must not cost the sitting its keys.
        .background(KeyboardReclaimer())
        .task {
            if session == nil {
                session = StudySession(profile: profile, deck: deck, mode: mode, store: store)
            }
        }
        .onDisappear {
            // The counts behind the sheet are about to be looked at, and the
            // library has just changed.
            speaker.stop()
            clock.refresh()
            // An installed model holds gigabytes while it is loaded; the
            // sitting is over, so it can be let go of until the next question.
            Task {
                await store.saveNow()
                await CompanionStore.unload()
            }
        }
        // Both of these are opened from the card itself rather than routed
        // through the window: a sitting is a place you are in, and being sent
        // somewhere else to fix a typo would end it.
        .sheet(isPresented: $isEditingWord) {
            if let entry = session?.currentEntry {
                WordEditor(entry: entry, profile: profile)
            }
        }
        .sheet(isPresented: $isDrawing) {
            if let entry = session?.currentEntry {
                AssociationSheet(
                    term: entry.displayTerm(in: profile),
                    meaning: entry.meaning,
                    existing: entry.association.flatMap { store.associationData(for: $0) }
                ) { data, strokes in
                    let id = entry.id
                    if strokes == 0 {
                        store.removeAssociation(from: id)
                    } else {
                        Task { await store.attachAssociation(data, strokeCount: strokes, to: id) }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private func header(_ session: StudySession) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(deck.map { store.library.path(of: $0) } ?? profile.displayName)
                            .font(.headline)

                        if mode.isPractice {
                            // Said plainly, because the difference between this
                            // and a review is the whole point of it.
                            chip("Practice")
                        }

                        // Only when it is not the usual way round: a card that
                        // shows a meaning where a word was expected needs a
                        // reason on screen.
                        if session.direction != .wordToMeaning {
                            chip(session.direction.title)
                        }
                    }

                    // "Resumed" is worth a word of its own: without it, a
                    // sitting picked up where it was left looks exactly like a
                    // sitting starting again.
                    Text(session.isFinished ? "Finished" : session.progressText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryText)
                }

                Spacer(minLength: 12)

                // Everything about the card on screen, without leaving the
                // sitting: a word that turns out to have a typo, or one that
                // wants a picture before the app has thought to offer one.
                if let entry = session.currentEntry {
                    Menu {
                        Button("Edit Word…") { isEditingWord = true }
                        if entry.picture == nil {
                            Button(entry.hasAssociation ? "Edit Association…" : "Draw an Association…") {
                                isDrawing = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("This card")
                }

                // "Stop for Now" rather than "End Session", because that is
                // what it does: a sitting with a plan is written down as it
                // goes and opens again where it was left.
                Button(session.isFinished ? "Done" : (mode.isResumable ? "Stop for Now" : "End Session")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            if let progress = session.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .animation(.easeInOut(duration: 0.2), value: progress)
            }
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 12)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Palette.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Palette.subtleFill, in: .capsule)
    }

    // MARK: - The card

    @ViewBuilder
    private func card(_ session: StudySession) -> some View {
        if let entry = session.currentEntry {
            VStack(spacing: 0) {
                CardFace(
                    entry: entry,
                    profile: profile,
                    isRevealed: session.isRevealed,
                    prompt: session.currentPrompt,
                    picture: PictureCache.image(for: entry.picture, store: store),
                    isSpeaking: speaker.speakingEntryID == entry.id,
                    canHearWord: entry.audio != nil || Speaker.voice(for: profile) != nil,
                    canHearExample: entry.exampleAudio != nil || Speaker.voice(for: profile) != nil,
                    listen: { speaker.speak(entry, in: profile, store: store) },
                    listenExample: { speaker.speakExample(entry, in: profile, store: store) }
                ) {
                    // Before the answer, and only for a word that is being
                    // lost: the picture the learner drew for it, on request.
                    // This is the only place it appears on its own. Once the
                    // meaning is on screen the drawing has nothing left to do,
                    // and once the word is known the offer stops being made —
                    // though the card's own menu still opens it.
                    if isStruggling, entry.hasAssociation {
                        hintButton(for: entry)
                    }
                } afterAnswer: {
                    // Offered only to a word with no picture of either kind
                    // yet. A word that has one does not want it shown here: the
                    // learner is already looking at the answer.
                    if !entry.hasAssociation, entry.picture == nil, isStruggling {
                        offerButton()
                    }
                }
                .animation(.easeOut(duration: 0.15), value: session.isRevealed)
                .onChange(of: session.isRevealed) {
                    guard session.isRevealed else { return }
                    // Two switches, because hearing a word and hearing it used
                    // are two different exercises.
                    if profile.speaksOnReveal {
                        speaker.speak(entry, in: profile, store: store, thenExample: profile.speaksExampleOnReveal)
                    } else if profile.speaksExampleOnReveal {
                        speaker.speakExample(entry, in: profile, store: store)
                    }
                }
                .onChange(of: entry.id) {
                    speaker.stop()
                    isAsking = false
                    assistant = nil
                }
                .onChange(of: session.isRevealed) {
                    isShowingHint = false
                    assistant?.update(isRevealed: session.isRevealed)
                }
                // Recomputed when the card changes and after every answer: the
                // third bad answer in a row is exactly the moment the offer
                // becomes worth making, and a sitting with one card in it never
                // changes card.
                .onChange(of: entry.id, initial: true) { judge(session) }
                .onChange(of: session.answerCount) { judge(session) }
                // Always beside the card, before the answer and after it: a
                // word or a sentence nobody can make sense of is exactly what
                // the assistant is for.
                .overlay(alignment: .topTrailing) {
                    if let readiness = assistantReadiness, readiness != .unsupported {
                        AssistantButton(isResponding: assistant?.isResponding == true) {
                            openAssistant(for: entry, in: session)
                        }
                        .padding(10)
                        .popover(isPresented: $isAsking, arrowEdge: .leading) {
                            if let assistant {
                                AssistantPanel(assistant: assistant, readiness: readiness)
                            }
                        }
                    }
                }
                .task { assistantReadiness = CardAssistant.readiness(for: companion) }

                answers(session)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LibraryEmptyState(
                title: "Nothing to Review",
                message: "Everything in this language is up to date.",
                symbol: "checkmark.circle"
            )
        }
    }

    /// None while the assistant is open: a question typed there is typed, and
    /// a "3" in it must never be an answer to the card.
    private func gradeShortcut(_ grade: ReviewGrade) -> KeyboardShortcut? {
        isAsking ? nil : KeyboardShortcut(KeyEquivalent(grade.shortcut), modifiers: [])
    }

    private func openAssistant(for entry: Entry, in session: StudySession) {
        assistantReadiness = CardAssistant.readiness(for: companion)
        if assistant?.entryID != entry.id {
            let picture = PictureCache.image(for: entry.picture, store: store)
            assistant = CardAssistant(
                entryID: entry.id,
                learner: learnerBrief(),
                card: cardBrief(entry, in: session, hasPicture: picture != nil),
                picture: picture,
                library: libraryFacts(),
                languageCodes: [profile.learningCode, profile.nativeCode],
                companion: companion
            )
        }
        isAsking.toggle()
    }

    /// The model the learner chose in Settings, or `nil` for Apple's own.
    private var companion: CompanionModel? {
        CompanionModel.named(settings.companionID)
    }

    private func learnerBrief() -> LearnerBrief {
        let entries = store.library.entries(in: profile.id)
        let knownWell = entries.count {
            guard let state = $0.recognitionCard?.scheduling else { return false }
            return state.stage == .review && state.intervalDays >= 21
        }
        return LearnerBrief(
            learning: LanguageCatalog.englishName(for: profile.learningCode),
            meanings: LanguageCatalog.englishName(for: profile.nativeCode),
            words: entries.count,
            knownWell: knownWell,
            streakDays: store.library.streak(asOf: clock.now).length,
            isPractice: mode.isPractice
        )
    }

    private func cardBrief(_ entry: Entry, in session: StudySession, hasPicture: Bool) -> CardBrief {
        let state = session.current.flatMap { entry.card(id: $0.cardID)?.scheduling }
            ?? entry.recognitionCard?.scheduling
            ?? SchedulingState()
        return CardBrief(
            word: entry.displayTerm(in: profile),
            // Where the language has an article, the word already says it.
            gender: entry.articlePrefix(in: profile) == nil ? entry.gender?.title.lowercased() : nil,
            meaning: entry.meaning,
            example: entry.example,
            exampleTranslation: entry.exampleTranslation,
            note: entry.note,
            deck: store.library.deck(id: entry.deckID).map { store.library.path(of: $0) },
            stage: state.stage,
            lapses: state.lapses,
            isStruggling: isStruggling,
            shows: session.currentPrompt,
            isRevealed: session.isRevealed,
            hasPicture: hasPicture
        )
    }

    private func libraryFacts() -> [WordFact] {
        store.library.entries(in: profile.id).map { entry in
            let state = entry.recognitionCard?.scheduling ?? SchedulingState()
            return WordFact(
                term: entry.term,
                word: entry.displayTerm(in: profile),
                meaning: String(entry.meaning.prefix(80)),
                stage: state.stage,
                intervalDays: state.intervalDays
            )
        }
    }

    private func judge(_ session: StudySession) {
        guard let card = session.current else { return }
        isStruggling = AssociationPrompt.isStruggling(cardID: card.cardID, reviews: store.library.reviews)
    }

    /// The drawing, offered before the answer for a word that keeps going.
    private func hintButton(for entry: Entry) -> some View {
        Button {
            isShowingHint = true
        } label: {
            Label("Your association", systemImage: "lightbulb")
                .font(.callout)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Palette.secondaryText)
        .popover(isPresented: $isShowingHint, arrowEdge: .bottom) {
            if let association = entry.association {
                AssociationRenderer.view(for: association, store: store)
                    .frame(width: 360, height: 232)
                    .padding(10)
            }
        }
    }

    /// The offer to draw one, made after the answer and nowhere earlier: a
    /// learner who cannot remember the word has nothing to draw a picture of.
    private func offerButton() -> some View {
        Button {
            isDrawing = true
        } label: {
            Label("Draw an association", systemImage: "lightbulb")
                .font(.callout)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Palette.secondaryText)
        .help("This one keeps going. A picture might hold it.")
        .padding(.top, 4)
    }

    private func answers(_ session: StudySession) -> some View {
        VStack(spacing: 8) {
            if session.isRevealed {
                HStack(spacing: 8) {
                    ForEach(ReviewGrade.allCases) { grade in
                        gradeButton(grade, session: session)
                    }
                }
            } else {
                Button(session.currentPrompt == .meaning ? "Show Word" : "Show Meaning") { session.reveal() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(isAsking ? nil : KeyboardShortcut(.space, modifiers: []))
            }

            Text(hint(session))
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func hint(_ session: StudySession) -> String {
        guard session.isRevealed else {
            return session.currentPrompt == .meaning ? "Space to show the word" : "Space to show the meaning"
        }
        let answers = mode.isPractice ? "1 – 4 to answer · nothing is rescheduled" : "1 – 4 to answer"
        guard let entry = session.currentEntry,
              entry.audio != nil || Speaker.voice(for: profile) != nil
        else { return answers }
        guard !entry.example.isEmpty, entry.exampleAudio != nil || Speaker.voice(for: profile) != nil else {
            return "\(answers) · P to hear it"
        }
        return "\(answers) · P for the word, ⇧P for the example"
    }

    @ViewBuilder
    private func gradeButton(_ grade: ReviewGrade, session: StudySession) -> some View {
        let title = session.title(for: grade)
        let label = VStack(spacing: 1) {
            Text(title)
                .lineLimit(1)
            if let interval = session.intervalText(for: grade) {
                Text(interval)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, session.intervalText(for: grade)].compactMap { $0 }.joined(separator: ", "))

        // Good is the answer most reviews end with, so it is the one the eye
        // lands on. The rest are ordinary buttons: four coloured blocks would
        // turn a quiet screen into a control panel.
        if grade == .good {
            Button { session.answer(grade) } label: { label }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(gradeShortcut(grade))
        } else {
            Button { session.answer(grade) } label: { label }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(gradeShortcut(grade))
                .help(grade == .easy && session.isFirstSight
                      ? "You knew this word before you added it. It is counted as known, and comes back in about a month."
                      : "")
        }
    }

    // MARK: - The end

    private func summary(_ session: StudySession) -> some View {
        ContentUnavailableView {
            Label(mode.isPractice ? "Practice Finished" : "Session Complete", systemImage: "checkmark.circle")
        } description: {
            Text(summaryText(session))
        } actions: {
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summaryText(_ session: StudySession) -> String {
        let cards = session.finishedCount
        guard cards > 0 else {
            return mode == .practiceToday
                ? "Nothing has been reviewed today yet."
                : "Nothing was due."
        }

        let noun = cards == 1 ? "card" : "cards"
        guard mode == .scheduled else {
            return "\(cards) \(noun) practised. Nothing was rescheduled."
        }

        let next = DueText.sentence(
            nextDue: store.library.nextDueDate(for: profile.id, deckID: deck?.id, after: .now),
            now: .now
        )
        return "\(cards) \(noun) reviewed. \(next)"
    }
}
