import SwiftUI

/// The exercise itself: hear a phrase, type it back, see what was missed.
///
/// A sheet, like a review, because a sitting is a task with a beginning and an
/// end. The phrase is never written out. What is on screen is a box per word
/// with its shape underneath — how long it is and, unless the learner asked
/// for less, what it begins with — and everything is heard first; the eyes
/// only ever confirm.
struct DictationPlayView: View {
    let profile: LanguageProfile
    @Bindable var session: DictationSession
    let hint: DictationHint
    /// Whether there is a voice to slow down. A language macOS cannot read has
    /// only its recordings, and a recording plays at the speed it was made.
    let canSlowDown: Bool
    let speak: (DictationItem, Bool) -> Void
    let answered: (DictationItem, DictationResult, ReviewGrade, Double, Bool) -> Void
    let finish: () -> Void

    @FocusState private var focused: Int?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let item = session.item {
                ScrollView {
                    VStack(spacing: 26) {
                        listen
                        switch session.phase {
                        case .typing:
                            boxes
                        case .marked(let result, _):
                            marked(result, item: item)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .padding(.horizontal, Metrics.gutter)
                }
            } else {
                Spacer()
            }

            Divider()
            footer
        }
        .frame(width: 680, height: 560)
        .onAppear { begin() }
        .onChange(of: session.item?.key) { begin() }
    }

    private func begin() {
        guard let item = session.item else { return }
        speak(item, false)
        focused = 0
    }

    // MARK: - Above

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(GameKind.dictation.title)
                    .font(.headline)
                Text(progressText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)
            }

            Spacer(minLength: 12)

            if session.wordsWanted > 0 {
                figure("\(Int((session.accuracy * 100).rounded()))%", "accurate")
            }
            if session.run > 1 {
                figure("\(session.run)", "in a row")
            }

            Button("End", action: finish)
                .padding(.leading, 6)
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 12)
    }

    private var progressText: String {
        var parts = ["\(session.queue.done) of \(session.queue.total)"]
        if session.queue.dueCount > 0 { parts.append("\(session.queue.dueCount) to go over") }
        if session.queue.newCount > 0 { parts.append("\(session.queue.newCount) new") }
        return parts.joined(separator: " · ")
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(Palette.secondaryText)
        }
    }

    // MARK: - The sound

    private var listen: some View {
        VStack(spacing: 10) {
            Button { replay(slowly: false) } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Palette.selection)
                    .frame(width: 76, height: 76)
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

    private var words: [String] {
        guard let item = session.item else { return [] }
        return DictationText.words(of: item.text)
    }

    private var boxes: some View {
        let written = DictationText.words(of: session.typed)
        let active = written.count - (session.typed.last?.isWhitespace == true ? 0 : 1)

        return VStack(spacing: 22) {
            // What has been typed, word by word, over the shape each one has
            // to take. Read-only: the typing happens in the field below, so
            // there is no cursor to lose between boxes.
            WrapLayout(spacing: 12, lineSpacing: 18) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    slot(index: index, word: word, written: written, active: active)
                }
            }
            .frame(maxWidth: .infinity)

            TextField("", text: $session.typed, prompt: Text("Type what you hear"))
                .textFieldStyle(.plain)
                .font(.title2)
                .multilineTextAlignment(.center)
                .focused($focused, equals: 0)
                .onSubmit(check)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(focused == 0 ? Palette.selection : Palette.separator, lineWidth: focused == 0 ? 2 : 1)
                }
                .frame(maxWidth: 520)

            Text("Click anywhere in it to fix a word you have already passed.")
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
        }
    }

    /// One word of the phrase: what has been typed for it, and underneath the
    /// shape it has to take.
    private func slot(index: Int, word: String, written: [String], active: Int) -> some View {
        let typed = index < written.count ? written[index] : ""
        let isActive = index == active

        return VStack(spacing: 4) {
            Text(typed.isEmpty ? " " : typed)
                .font(.title2.weight(.medium))
                .foregroundStyle(typed.isEmpty ? Palette.tertiaryText : Palette.primaryText)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(
                    isActive ? Palette.selection.opacity(0.12) : Palette.subtleFill.opacity(0.6),
                    in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous)
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isActive ? Palette.selection : Palette.separator)
                        .frame(height: isActive ? 2 : 1)
                }

            Text(hint.drawn(for: word))
                .font(.caption.monospaced())
                .foregroundStyle(Palette.tertiaryText)
                .tracking(1)
        }
        .frame(width: width(of: word))
        .animation(.easeOut(duration: 0.12), value: isActive)
    }

    /// Wide enough for the word that has to go in it, and never so narrow that
    /// a three-letter box looks like a mistake.
    private func width(of word: String) -> CGFloat {
        min(260, max(62, CGFloat(word.count) * 16 + 26))
    }

    // MARK: - Marked

    private func marked(_ result: DictationResult, item: DictationItem) -> some View {
        VStack(spacing: 20) {
            WrapLayout(spacing: 12, lineSpacing: 18) {
                ForEach(result.words) { word in
                    markedBox(word)
                }
            }
            .frame(maxWidth: .infinity)

            if !result.extra.isEmpty {
                Text("Nothing was said after that: \(result.extra.joined(separator: " "))")
                    .font(.callout)
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

    /// What was typed stays where it was typed, in the colour it earned; the
    /// word it should have been appears under it, in green. Nothing moves, so
    /// the two are compared in place.
    private func markedBox(_ word: DictationWord) -> some View {
        let widest = word.expected.count >= word.typed.count ? word.expected : word.typed

        return VStack(spacing: 4) {
            Text(word.typed.isEmpty ? "—" : word.typed)
                .font(.title2.weight(.medium))
                .foregroundStyle(word.typed.isEmpty ? Palette.tertiaryText : colour(of: word.mark))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(
                    colour(of: word.mark).opacity(0.10),
                    in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous)
                )
                .overlay(alignment: .bottom) {
                    Rectangle().fill(colour(of: word.mark)).frame(height: 2)
                }

            // Only where they differ: a word already right does not need
            // telling twice.
            if word.mark == .right {
                Text(" ").font(.callout)
            } else {
                Text(word.expected)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Palette.complete)
            }
        }
        .frame(width: width(of: widest))
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

    // MARK: - Below

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            Button("Hear It Again", systemImage: "arrow.clockwise") { replay(slowly: false) }
                .keyboardShortcut("r", modifiers: .command)

            Button("Slower", systemImage: "tortoise") { replay(slowly: true) }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!canSlowDown)
                .help(canSlowDown
                      ? "Hear it read slowly (⌘L)"
                      : "macOS has no voice for \(LanguageCatalog.name(for: profile.learningCode)) to slow down.")

            if case .typing = session.phase {
                Button("Show Me", systemImage: "eye") { session.reveal() }
                    .keyboardShortcut("h", modifiers: .command)
            }

            Spacer(minLength: 8)

            switch session.phase {
            case .typing:
                Text("Return to check")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
                Button("Check", action: check)
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isEmpty)

            case .marked:
                Text("Return to carry on")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
                Button("Next", action: next)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 12)
    }

    // MARK: - Doing

    private func replay(slowly: Bool) {
        guard let item = session.item else { return }
        if case .typing = session.phase { session.heardAgain() }
        speak(item, slowly)
    }

    private func check() {
        guard case .typing = session.phase else { return }
        // A stray Return is not an answer. Nothing typed and nothing shown
        // means the learner is still listening.
        guard session.revealed || !session.isEmpty else { return }
        session.check()
        focused = nil
    }

    /// Written down here and nowhere else: an answer is recorded once, when
    /// the learner has seen it and moved on.
    private func next() {
        guard case .marked(let result, let grade) = session.phase, let item = session.item else { return }
        let seconds = session.lastSeconds
        let counted = session.advance()
        answered(item, result, grade, seconds, counted)
        if session.item == nil { finish() }
    }
}
