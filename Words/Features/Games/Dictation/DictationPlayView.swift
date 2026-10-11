import SwiftUI

/// The exercise itself: hear a phrase, type it back, see what was missed.
///
/// The phrase is never written out. What is on screen is its shape — how many
/// words and, unless the learner asked for less, what each one begins with —
/// and underneath it whatever has been typed so far. Everything is heard
/// first; the eyes only ever confirm.
struct DictationPlayView: View {
    let profile: LanguageProfile
    @Bindable var session: DictationSession
    let speak: (DictationItem) -> Void
    let answered: (DictationItem, DictationResult, ReviewGrade, Double, Bool) -> Void
    let finish: () -> Void

    @FocusState private var isTyping: Bool
    @State private var hint: DictationHint = .firstLetter

    init(
        profile: LanguageProfile,
        session: DictationSession,
        hint: DictationHint,
        speak: @escaping (DictationItem) -> Void,
        answered: @escaping (DictationItem, DictationResult, ReviewGrade, Double, Bool) -> Void,
        finish: @escaping () -> Void
    ) {
        self.profile = profile
        self.session = session
        self.speak = speak
        self.answered = answered
        self.finish = finish
        _hint = State(initialValue: hint)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 28) {
                    if let item = session.item {
                        listenButton(item)

                        switch session.phase {
                        case .typing:
                            typingBoard
                        case .marked(let result, _):
                            markedBoard(result, item: item)
                        }
                    }
                }
                .frame(maxWidth: Metrics.readableWidth)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, Metrics.gutter)
            }

            Divider()
            footer
        }
        // The field is invisible; a click anywhere brings the cursor back, so
        // a learner who clicked the window's background is never left typing
        // into nothing.
        .navigationTitle(GameKind.dictation.title)
        .navigationSubtitle(profile.languagePair)
        .contentShape(.rect)
        .onTapGesture { isTyping = true }
        .onAppear {
            isTyping = true
            if let item = session.item { speak(item) }
        }
    }

    // MARK: - Above and below

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.queue.done) of \(session.queue.total)")
                    .font(.headline)
                    .monospacedDigit()
                HStack(spacing: 6) {
                    if session.queue.dueCount > 0 {
                        Text("\(session.queue.dueCount) to go over")
                    }
                    if session.queue.newCount > 0 {
                        Text("\(session.queue.newCount) new")
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
            }

            ProgressView(value: Double(session.queue.done), total: Double(max(1, session.queue.total)))
                .frame(maxWidth: 200)

            Spacer(minLength: 8)

            if session.wordsWanted > 0 {
                stat("\(Int((session.accuracy * 100).rounded()))%", "accurate")
            }
            if session.run > 1 {
                stat("\(session.run)", "in a row")
            }

            Button("End", action: finish)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(Palette.secondaryText)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            switch session.phase {
            case .typing:
                Button("Hear It Again", systemImage: "arrow.clockwise") { replay() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Show Me", systemImage: "eye") { session.reveal() }
                    .keyboardShortcut("h", modifiers: .command)
                Spacer(minLength: 8)
                Text("Return to check")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
                Button("Check", action: check)
                    .disabled(session.typed.trimmingCharacters(in: .whitespaces).isEmpty)

            case .marked:
                Button("Hear It Again", systemImage: "arrow.clockwise") { replay() }
                    .keyboardShortcut("r", modifiers: .command)
                Spacer(minLength: 8)
                Text("Return to carry on")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
                Button("Next", action: next)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - The sound

    private func listenButton(_ item: DictationItem) -> some View {
        VStack(spacing: 8) {
            Button {
                replay()
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Palette.selection)
                    .frame(width: 84, height: 84)
                    .background(Palette.selection.opacity(0.12), in: .circle)
            }
            .buttonStyle(.plain)
            .help("Hear it again (⌘R)")

            Text(caption)
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    private var caption: String {
        if case .marked = session.phase { return "Hear it once more before you move on" }
        return session.replays == 0 ? "Listen, then type what you hear" : "Heard \(session.replays + 1) times"
    }

    // MARK: - Typing

    private var typingBoard: some View {
        VStack(spacing: 18) {
            WrapLayout(spacing: 14, lineSpacing: 16) {
                ForEach(Array(session.words.enumerated()), id: \.offset) { index, word in
                    slot(index: index, word: word)
                }
            }
            .frame(maxWidth: .infinity)

            // Where the keys actually land. Drawn as nothing: what the learner
            // watches is the row of words above, which is the whole point of
            // the exercise.
            TextField("", text: $session.typed)
                .textFieldStyle(.plain)
                .focused($isTyping)
                .onSubmit(check)
                .opacity(0.001)
                .frame(height: 1)
                .accessibilityLabel("What you hear")

            if !isTyping {
                Label("Click here to type", systemImage: "cursorarrow.click")
                    .font(.caption)
                    .foregroundStyle(Palette.warning)
            }
        }
    }

    /// One word: what has been typed into it, over the shape it has to take.
    private func slot(index: Int, word: String) -> some View {
        let typed = session.typedWords
        let written = index < typed.count ? typed[index] : ""
        let isActive = index == (session.isMidWord ? max(0, typed.count - 1) : typed.count)

        return VStack(spacing: 3) {
            Text(written.isEmpty ? " " : written)
                .font(.title3.weight(.medium))
                .foregroundStyle(written.isEmpty ? Palette.tertiaryText : Palette.primaryText)

            Rectangle()
                .fill(isActive ? Palette.selection : Palette.separator)
                .frame(height: isActive ? 2 : 1)

            Text(hint.drawn(for: word))
                .font(.caption.monospaced())
                .foregroundStyle(Palette.tertiaryText)
                .tracking(1)
        }
        .frame(minWidth: max(28, CGFloat(word.count) * 11))
        .animation(.easeOut(duration: 0.12), value: isActive)
    }

    // MARK: - Marked

    private func markedBoard(_ result: DictationResult, item: DictationItem) -> some View {
        VStack(spacing: 18) {
            WrapLayout(spacing: 14, lineSpacing: 16) {
                ForEach(result.words) { word in
                    marked(word)
                }
            }
            .frame(maxWidth: .infinity)

            if !result.extra.isEmpty {
                Text("Nothing was said after that: \(result.extra.joined(separator: " "))")
                    .font(.caption)
                    .foregroundStyle(Palette.critical)
            }

            if !item.meaning.isEmpty {
                Text(item.meaning)
                    .font(.title3)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }

            verdict(result)
        }
    }

    private func marked(_ word: DictationWord) -> some View {
        VStack(spacing: 3) {
            Text(word.expected)
                .font(.title3.weight(.medium))
                .foregroundStyle(colour(of: word.mark))

            Rectangle()
                .fill(colour(of: word.mark).opacity(0.6))
                .frame(height: 2)

            // Only where it is worth seeing: what was typed instead.
            if word.mark == .wrong || word.mark == .almost, !word.typed.isEmpty {
                Text(word.typed)
                    .font(.caption)
                    .strikethrough(word.mark == .wrong)
                    .foregroundStyle(Palette.tertiaryText)
            } else if word.mark == .missing {
                Text("missed")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
            } else {
                Text(" ").font(.caption)
            }
        }
        .frame(minWidth: max(28, CGFloat(word.expected.count) * 11))
    }

    private func colour(of mark: DictationMark) -> Color {
        switch mark {
        case .right: Palette.complete
        case .almost: Palette.warning
        case .wrong, .missing: Palette.critical
        }
    }

    @ViewBuilder
    private func verdict(_ result: DictationResult) -> some View {
        if session.revealed {
            Label("Shown to you — it will come round again", systemImage: "eye")
                .foregroundStyle(Palette.secondaryText)
        } else if result.isPerfect {
            Label("Every word", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.complete)
        } else if result.isRight {
            Label("Right — mind the spelling", systemImage: "checkmark.circle")
                .foregroundStyle(Palette.warning)
        } else {
            Label(
                "\(result.mistakes) \(result.mistakes == 1 ? "word" : "words") to catch next time",
                systemImage: "arrow.counterclockwise"
            )
            .foregroundStyle(Palette.secondaryText)
        }
    }

    // MARK: - Doing

    private func replay() {
        guard let item = session.item else { return }
        if case .typing = session.phase { session.heardAgain() }
        speak(item)
        isTyping = true
    }

    private func check() {
        guard case .typing = session.phase else { return }
        // A stray Return is not an answer. Nothing typed and nothing shown
        // means the learner is still listening.
        guard session.revealed || !session.typed.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        session.check()
    }

    /// Written down here and nowhere else: an answer is recorded once, when
    /// the learner has seen it and moved on.
    private func next() {
        guard case .marked(let result, let grade) = session.phase, let item = session.item else { return }
        let seconds = session.lastSeconds
        let counted = session.advance()
        answered(item, result, grade, seconds, counted)
        if let next = session.item {
            speak(next)
            isTyping = true
        } else {
            finish()
        }
    }
}
