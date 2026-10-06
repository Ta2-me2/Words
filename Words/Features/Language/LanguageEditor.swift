import SwiftUI

/// Creating or changing a language profile.
///
/// A sheet rather than a window: it is one short form belonging to the library
/// in front of it, and it has an end.
struct LanguageEditor: View {

    enum Mode {
        case add
        case edit(LanguageProfile)
    }

    let mode: Mode

    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var learningCode: String
    @State private var nativeCode: String
    @State private var flag: String
    @State private var dailyNewLimit: Int
    @State private var dailyReviewLimit: Int?
    @State private var desiredRetention: Double
    @State private var newWordOrder: NewWordOrder

    /// Until the name is typed in, it follows the language being learned. After
    /// that it is the user's, and nothing may overwrite it.
    @State private var hasEditedName: Bool

    @State private var isConfirmingDeletion = false

    @State private var voiceIdentifier: String?
    @State private var speechRate: Double
    @State private var speaksOnReveal: Bool
    @State private var speaksExampleOnReveal: Bool

    private let codes = LanguageCatalog.sortedCodes

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            let suggested = LanguageCatalog.suggestedLearningCode
            _name = State(initialValue: LanguageCatalog.name(for: suggested))
            _learningCode = State(initialValue: suggested)
            _nativeCode = State(initialValue: LanguageCatalog.systemCode)
            _flag = State(initialValue: LanguageCatalog.defaultFlag(for: suggested))
            _dailyNewLimit = State(initialValue: 20)
            _dailyReviewLimit = State(initialValue: nil)
            _desiredRetention = State(initialValue: Retention.standard)
            _newWordOrder = State(initialValue: .added)
            _hasEditedName = State(initialValue: false)
            _voiceIdentifier = State(initialValue: nil)
            _speechRate = State(initialValue: 0.45)
            _speaksOnReveal = State(initialValue: false)
            _speaksExampleOnReveal = State(initialValue: false)
        case .edit(let profile):
            _name = State(initialValue: profile.name)
            _learningCode = State(initialValue: profile.learningCode)
            _nativeCode = State(initialValue: profile.nativeCode)
            _flag = State(initialValue: profile.flag)
            _dailyNewLimit = State(initialValue: profile.dailyNewLimit)
            _dailyReviewLimit = State(initialValue: profile.dailyReviewLimit)
            _desiredRetention = State(initialValue: profile.desiredRetention)
            _newWordOrder = State(initialValue: profile.newWordOrder)
            _hasEditedName = State(initialValue: true)
            _voiceIdentifier = State(initialValue: profile.voiceIdentifier)
            _speechRate = State(initialValue: profile.speechRate)
            _speaksOnReveal = State(initialValue: profile.speaksOnReveal)
            _speaksExampleOnReveal = State(initialValue: profile.speaksExampleOnReveal)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: isEditing ? "Language" : "New Language",
                subtitle: isEditing ? nil : "The language you are learning, and the one its words are explained in."
            )

            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text(LanguageCatalog.name(for: learningCode)))
                        .onChange(of: name) { hasEditedName = true }

                    Picker("Learning", selection: $learningCode) {
                        ForEach(codes, id: \.self) { code in
                            Text(LanguageCatalog.name(for: code)).tag(code)
                        }
                    }
                    .onChange(of: learningCode) {
                        // The flag follows the language until it is chosen by
                        // hand, and the suggestions are always the new
                        // language's.
                        if !LanguageCatalog.flags(for: learningCode).contains(flag) {
                            flag = LanguageCatalog.defaultFlag(for: learningCode)
                        }
                        guard !hasEditedName else { return }
                        name = LanguageCatalog.name(for: learningCode)
                        // Setting the field fired its own change; the name is
                        // still the app's suggestion, not the user's choice.
                        hasEditedName = false
                    }

                    Picker("Meanings in", selection: $nativeCode) {
                        ForEach(codes, id: \.self) { code in
                            Text(LanguageCatalog.name(for: code)).tag(code)
                        }
                    }
                    LabeledContent("Flag") {
                        FlagPicker(code: learningCode, selection: $flag)
                    }
                } footer: {
                    if learningCode == nativeCode {
                        Text("Choose two different languages.")
                            .foregroundStyle(Palette.warning)
                    }
                }

                VoiceSettings(
                    learningCode: learningCode,
                    sampleWord: sampleWord,
                    voiceIdentifier: $voiceIdentifier,
                    speechRate: $speechRate,
                    speaksOnReveal: $speaksOnReveal,
                    speaksExampleOnReveal: $speaksExampleOnReveal
                )

                Section {
                    LabeledContent("New words a day") {
                        CountField(value: $dailyNewLimit, in: 0...999)
                    }
                    .help("How many unseen words a day may be started. It keeps a long list of new words from becoming a wall of reviews tomorrow.")

                    Picker("New words come", selection: $newWordOrder) {
                        ForEach(NewWordOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .help("In random order, a day's new words are drawn from anywhere in the language or deck — the same ones all day, different ones tomorrow.")

                    LabeledContent("Reviews a day") {
                        CountField(value: $dailyReviewLimit, in: 0...9999, placeholder: "No limit")
                    }
                    .help("Leave empty for no limit. A limit does not make reviews go away: whatever it holds back waits until tomorrow.")

                    // The one number that decides how much work a day holds.
                    // Explained on request rather than printed under the slider,
                    // where it was read once and then only took up room.
                    LabeledContent {
                        HStack(spacing: 10) {
                            Slider(value: $desiredRetention, in: Retention.range, step: 0.01)
                                .frame(width: 150)
                            Text(retentionText)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text("Words remembered")
                            RetentionInfo(retention: desiredRetention)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 10) {
                if case .edit = mode {
                    Button("Delete Language…", role: .destructive) { isConfirmingDeletion = true }
                }

                Spacer(minLength: 0)

                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Save" : "Add Language") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(learningCode == nativeCode)
            }
            .padding(Metrics.cardPadding)
        }
        .frame(width: 480, height: 620)
        .task {
            // The list of voices is worth asking the system for again here: a
            // learner may have installed one a minute ago.
            Speaker.refreshVoices()
        }
        .alert("Delete this language?", isPresented: $isConfirmingDeletion) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(deletionMessage)
        }
    }

    private var deletionMessage: String {
        guard case .edit(let profile) = mode else { return "" }
        let words = store.library.entries(in: profile.id).count
        guard words > 0 else { return "It has no words in it." }
        return "Its \(words) \(words == 1 ? "word" : "words") and decks will be deleted too. This cannot be undone."
    }

    private func delete() {
        guard case .edit(let profile) = mode else { return }
        if router.profileID == profile.id { router.profileID = nil }
        let id = profile.id
        store.deleteProfile(id: id)
        // The games' record of this language goes with it — its levels, its
        // points, every word it asked about.
        Task { await WortfallHost.shared.discard(id) }
        router.restoreSelection(in: store.library)
        dismiss()
    }

    private var retentionText: String {
        "\(Int((desiredRetention * 100).rounded()))%"
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// Something real for the voice to say. A word out of the language's own
    /// vocabulary if there is one, and otherwise the language's name for
    /// itself — "Deutsch" rather than "German".
    private var sampleWord: String {
        if case .edit(let profile) = mode,
           let word = store.library.entries(in: profile.id).first?.term {
            return word
        }
        return Locale(identifier: learningCode).localizedString(forLanguageCode: learningCode)
            ?? LanguageCatalog.name(for: learningCode)
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? LanguageCatalog.name(for: learningCode) : trimmed

        switch mode {
        case .add:
            let profile = store.addProfile(
                name: finalName,
                learningCode: learningCode,
                nativeCode: nativeCode,
                flag: flag,
                dailyNewLimit: dailyNewLimit,
                dailyReviewLimit: dailyReviewLimit,
                desiredRetention: desiredRetention,
                voiceIdentifier: voiceIdentifier,
                speechRate: speechRate,
                speaksOnReveal: speaksOnReveal,
                speaksExampleOnReveal: speaksExampleOnReveal
            )
            if newWordOrder != profile.newWordOrder {
                var ordered = profile
                ordered.newWordOrder = newWordOrder
                store.save(ordered)
            }
            // A language that has just been created is the one to be looking
            // at, and the first thing it needs is words.
            router.profileID = profile.id
            router.show(store.library.entries(in: profile.id).isEmpty ? .add : .home)

        case .edit(let existing):
            var updated = existing
            updated.name = finalName
            updated.learningCode = learningCode
            updated.nativeCode = nativeCode
            updated.flag = flag
            updated.voiceIdentifier = voiceIdentifier
            updated.speechRate = speechRate
            updated.speaksOnReveal = speaksOnReveal
            updated.speaksExampleOnReveal = speaksExampleOnReveal
            updated.dailyNewLimit = dailyNewLimit
            updated.dailyReviewLimit = dailyReviewLimit
            updated.desiredRetention = Retention.clamped(desiredRetention)
            updated.newWordOrder = newWordOrder
            store.save(updated)
        }

        dismiss()
    }
}

/// The flags worth offering for a language, as a row to pick from.
///
/// Not a text field: the point is to choose in one click, and a language rarely
/// has more than a handful of flags anyone would want.
struct FlagPicker: View {
    let code: String
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(LanguageCatalog.flags(for: code), id: \.self) { flag in
                Button {
                    selection = flag
                } label: {
                    Text(flag)
                        .font(.title3)
                        .frame(width: 30, height: 26)
                        .background {
                            RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                                .fill(selection == flag ? Palette.selection.opacity(0.18) : .clear)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                                .strokeBorder(
                                    selection == flag ? Palette.selection : Palette.separator,
                                    lineWidth: selection == flag ? 1.5 : 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Flag \(flag)")
            }

            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.12), value: selection)
    }
}

/// What "Words remembered" means, on request.
///
/// Short on purpose: what the number is, what it costs, and which way to move
/// it. The figures follow the slider, so the explanation is always about the
/// value on screen rather than a textbook one.
private struct RetentionInfo: View {
    let retention: Double

    @State private var isShown = false

    var body: some View {
        let percent = Int((retention * 100).rounded())

        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Palette.secondaryText)
        .help("What this means")
        .accessibilityLabel("About words remembered")
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Words remembered")
                    .font(.headline)

                Text("How many of your words you want to still know when they come up again.")

                Text("At \(percent)%, about \(100 - percent) in 100 will have slipped by then — those simply get learned again.")

                VStack(alignment: .leading, spacing: 3) {
                    Text("**Higher** — words come back sooner: less forgetting, more reviews each day.")
                    Text("**Lower** — fewer reviews, more forgetting.")
                }

                Text("90% suits most people. A change applies from each word's next answer.")
                    .foregroundStyle(Palette.secondaryText)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 290, alignment: .leading)
            .padding(14)
        }
    }
}
