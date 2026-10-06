import SwiftUI
import UniformTypeIdentifiers

/// Bringing in a deck made for Anki.
///
/// Anki decks have no fixed shape: every author decides what the fields are and
/// how a card is laid out. So the screen does not pretend to know. It reads the
/// deck, makes a guess about which field is the word, which the meaning and so
/// on, and shows the guess as it would actually come out — the real card, the
/// real sound — for the learner to judge and correct. The guess is made once
/// per note type, and a note type gives every one of its notes the same shape,
/// so one card that looks right means a deck that looks right.
struct AnkiImportView: View {
    let profile: LanguageProfile

    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    private let speaker = Speaker.shared

    private enum Stage {
        case choosing
        case reading
        case mapping(AnkiImportModel)
        case importing(Double)
        case done(count: Int, placement: AnkiDeckPlacement)
        case failed(String, String?)
    }

    @State private var stage: Stage = .choosing
    @State private var isChoosingFile = false
    @State private var isTargeted = false

    var body: some View {
        Group {
            switch stage {
            case .choosing: choosing
            case .reading: working("Reading the deck…", progress: nil)
            case .mapping(let model): mapping(model)
            case .importing(let progress): working("Importing…", progress: progress)
            case .done(let count, let placement): done(count: count, placement: placement)
            case .failed(let message, let suggestion): failed(message, suggestion: suggestion)
            }
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: Self.packageTypes) { result in
            if case .success(let url) = result { open(url) }
        }
        .onDisappear { speaker.stop() }
        // The screen keeps this side when another is chosen, so leaving it is
        // not a disappearance; a card still reading itself aloud should stop.
        .onChange(of: router.addMode) { speaker.stop() }
    }

    // MARK: - Choosing a file

    private var choosing: some View {
        ContentUnavailableView {
            Label("Import an Anki Deck", systemImage: "square.and.arrow.down.on.square")
        } description: {
            Text("Drop an .apkg file here, or choose one. You will see how its cards come out in Words, and decide where each part goes, before anything is added.")
        } actions: {
            Button("Choose Deck…") { isChoosingFile = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.selection, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .opacity(isTargeted ? 1 : 0)
                .padding(Metrics.gutter)
        }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "apkg" }) else { return false }
            open(url)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func working(_ title: String, progress: Double?) -> some View {
        VStack(spacing: 12) {
            if let progress {
                ProgressView(value: progress)
                    .frame(width: 260)
            } else {
                ProgressView()
            }
            Text(title)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ message: String, suggestion: String?) -> some View {
        ContentUnavailableView {
            Label("This Deck Could Not Be Opened", systemImage: "exclamationmark.triangle")
        } description: {
            Text([message, suggestion].compactMap { $0 }.joined(separator: "\n\n"))
        } actions: {
            Button("Choose Another Deck…") { isChoosingFile = true }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func done(count: Int, placement: AnkiDeckPlacement) -> some View {
        ContentUnavailableView {
            Label("Imported \(count) \(count == 1 ? "Word" : "Words")", systemImage: "checkmark.circle")
        } description: {
            Text(doneDescription(placement))
        } actions: {
            Button("Show in Library") {
                if let top = placement.top { router.show(deck: top.deck.id) } else { router.show(.library) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Import Another Deck…") { isChoosingFile = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func doneDescription(_ placement: AnkiDeckPlacement) -> String {
        guard let top = placement.top else { return "They are in \(profile.displayName), in no deck." }
        let name = store.library.path(of: top.deck)
        switch placement.subdecks.count {
        case 0: return "They are in the deck “\(name)”."
        case 1: return "They are in “\(name)” and one subdeck inside it."
        default: return "They are in “\(name)” and \(placement.subdecks.count) subdecks inside it."
        }
    }

    // MARK: - Deciding where things go

    private func mapping(_ model: AnkiImportModel) -> some View {
        VStack(spacing: 0) {
            header(model)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)

            Divider()

            HStack(alignment: .top, spacing: Metrics.gutter) {
                fieldList(model)
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 400)

                preview(model)
                    .frame(minWidth: 320, maxWidth: .infinity)
            }
            .padding(Metrics.gutter)
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            footer(model)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
        }
        .onChange(of: store.library.entries.count) {
            model.refresh(existing: store.library.entries)
        }
        .onChange(of: model.position) { speaker.stop() }
        .onChange(of: model.audio) { speaker.stop() }
    }

    private func header(_ model: AnkiImportModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.package.mainDeckName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(model.notes.count) notes · note type “\(model.type.name)”")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            // Most decks are one note type. A package that mixes several is
            // imported one type at a time, because each has its own fields.
            if model.package.usedNoteTypes.count > 1 {
                Picker("Note Type", selection: Binding(
                    get: { model.type.id },
                    set: { model.switchType(to: $0) }
                )) {
                    ForEach(model.package.usedNoteTypes) { type in
                        Text("\(type.name) (\(model.package.notes(of: type.id).count))").tag(type.id)
                    }
                }
                .frame(maxWidth: 260)
            }

            Button("Choose Another Deck…") { isChoosingFile = true }
        }
    }

    // MARK: The fields

    private func fieldList(_ model: AnkiImportModel) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: "Anki Fields") {
                Text("Goes to")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
            }

            ScrollView {
                GroupedRows {
                    ForEach(Array(model.type.fields.enumerated()), id: \.offset) { index, name in
                        GroupedRow(showsDivider: index < model.type.fields.count - 1) {
                            fieldRow(model, index: index, name: name)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            if let problem = model.mapping.problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(Palette.warning)
            }

            decks(model)
                .padding(.top, 6)
        }
    }

    // MARK: The decks

    /// Where the words go, and the decks that will be made to hold them —
    /// shown before anything is made, the same way the card is.
    private func decks(_ model: AnkiImportModel) -> some View {
        let placement = model.placement(in: store.library)
        let existing = store.library.decks(in: profile.id)
        let nameTaken = existing.contains {
            !$0.isSubdeck && $0.displayName.compare(model.layout.baseName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Decks")

            Picker("Into", selection: Binding(get: { model.target }, set: { model.target = $0 })) {
                // A deck with this name is already in the language, so it is
                // offered as itself below rather than as a "new" one that
                // would quietly turn out to be the same deck.
                if !nameTaken {
                    Text("New Deck “\(model.layout.baseName)”").tag(AnkiDeckTarget.newDeck(model.layout.baseName))
                }
                if !existing.isEmpty {
                    if !nameTaken { Divider() }
                    ForEach(existing) { deck in
                        Text(store.library.path(of: deck)).tag(AnkiDeckTarget.existing(deck.id))
                    }
                }
                Divider()
                Text("No Deck").tag(AnkiDeckTarget.none)
            }

            if model.layout.hasSubdecks {
                Picker("Subdecks", selection: Binding(get: { model.subdeckStyle }, set: { model.subdeckStyle = $0 })) {
                    ForEach(model.layout.styles) { style in
                        Text(model.title(for: style)).tag(style)
                    }
                }
                .disabled(!placement.canHoldSubdecks)

                if !placement.canHoldSubdecks {
                    Text(model.target == .none
                         ? "Without a deck there is nothing to put subdecks in."
                         : "This is already a subdeck, and a subdeck cannot hold others. Everything goes straight into it.")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.subdeckStyle == .firstLevel, model.layout.hasDeeperLevels {
                    Text("The deck is divided more finely than Words goes. Those smaller parts are merged into the subdeck above them.")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let top = placement.top {
                ScrollView {
                    GroupedRows {
                        GroupedRow(showsDivider: !placement.subdecks.isEmpty) {
                            deckRow(top, title: store.library.path(of: top.deck), indent: false)
                        }
                        ForEach(Array(placement.subdecks.enumerated()), id: \.element.id) { index, planned in
                            GroupedRow(showsDivider: index < placement.subdecks.count - 1) {
                                deckRow(planned, title: planned.deck.displayName, indent: true)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 132)
            }
        }
    }

    private func deckRow(_ planned: AnkiDeckPlacement.Planned, title: String, indent: Bool) -> some View {
        HStack(spacing: 8) {
            DeckLabel(title: title, icon: planned.deck.displayIcon)
                .font(.callout)
                .lineLimit(1)
                .padding(.leading, indent ? 18 : 0)

            Spacer(minLength: 8)

            if planned.isNew {
                Text("New")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Palette.subtleFill, in: .capsule)
            }

            // Only the words that land in the row itself: a deck's own count
            // in the sidebar includes its subdecks, but here the point is to
            // see where each word goes.
            Text(planned.wordCount > 0 ? "\(planned.wordCount)" : "—")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryText)
        }
    }

    private func fieldRow(_ model: AnkiImportModel, index: Int, name: String) -> some View {
        let slot = model.mapping.slots[safe: index] ?? .skip
        let value = model.currentNote?.values[safe: index]

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(slot == .skip ? Palette.secondaryText : Palette.primaryText)

                sample(model, value: value, index: index)
            }

            Spacer(minLength: 8)

            Picker("Goes to", selection: Binding(
                get: { slot },
                set: { model.mapping.assign($0, toField: index) }
            )) {
                ForEach(model.choices(forField: index)) { choice in
                    if choice == .skip { Divider() }
                    Text(choice.title).tag(choice)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    /// What this field holds in the note on screen, so a field called "Back"
    /// can be seen to be a sentence.
    @ViewBuilder
    private func sample(_ model: AnkiImportModel, value: AnkiValue?, index: Int) -> some View {
        if let value, !value.sounds.isEmpty {
            Button {
                if let url = model.sound(inField: index) { speaker.stop(); speaker.play(url) }
            } label: {
                Label("Listen to this recording", systemImage: "play.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        } else if let value, !value.images.isEmpty {
            Label("Picture", systemImage: "photo")
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
        } else {
            let text = value?.text ?? ""
            Text(text.isEmpty || AnkiText.isPlaceholder(text) ? "Empty in this note" : text)
                .font(.caption)
                .foregroundStyle(text.isEmpty ? Palette.tertiaryText : Palette.secondaryText)
                .lineLimit(2)
        }
    }

    // MARK: The card

    private func preview(_ model: AnkiImportModel) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: "How It Will Look") {
                HStack(spacing: 6) {
                    Button { model.step(-1) } label: { Image(systemName: "chevron.left") }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Text(model.visible.isEmpty ? "No notes" : "\(model.position + 1) of \(model.visible.count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryText)
                        .frame(minWidth: 70)
                    Button { model.step(1) } label: { Image(systemName: "chevron.right") }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
                .buttonStyle(.borderless)
                .disabled(model.visible.count < 2)
            }

            if let word = model.current {
                let entry = model.previewEntry(for: word)

                CardFace(
                    entry: entry,
                    profile: profile,
                    isRevealed: model.isRevealed,
                    picture: model.picture(for: word),
                    isSpeaking: speaker.speakingEntryID == entry.id,
                    canHearWord: entry.audio != nil || Speaker.voice(for: profile) != nil,
                    canHearExample: entry.exampleAudio != nil || Speaker.voice(for: profile) != nil,
                    listen: { speaker.speak(entry, in: profile, media: model.previewURL) },
                    listenExample: { speaker.speakExample(entry, in: profile, media: model.previewURL) }
                )
                .frame(height: 330)
                .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(Palette.separator)
                }
                .animation(.easeOut(duration: 0.15), value: model.isRevealed)

                HStack(spacing: 10) {
                    Button(model.isRevealed ? "Hide Meaning" : "Show Meaning") {
                        model.isRevealed.toggle()
                    }

                    if let status = model.currentStatus {
                        Label(status, systemImage: "minus.circle")
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
            } else {
                ContentUnavailableView("Nothing to Show", systemImage: "rectangle.on.rectangle.slash")
                    .frame(height: 330)
            }

            if model.skippedCount > 0 {
                Toggle("Show only the \(model.skippedCount) notes that will be skipped", isOn: Binding(
                    get: { model.showsSkippedOnly },
                    set: { model.showsSkippedOnly = $0 }
                ))
                .font(.callout)
            }

            if model.hasRecordings {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Sound", selection: Binding(
                        get: { model.audio },
                        set: { model.audio = $0 }
                    )) {
                        ForEach(AnkiAudioChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 340)

                    Text(model.recordingsDescription)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Doing it

    private func footer(_ model: AnkiImportModel) -> some View {
        HStack(spacing: 12) {
            Text(summary(model.plan))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(2)

            Spacer(minLength: 12)

            let count = model.plan.usable.count
            Button("Import \(count) \(count == 1 ? "Word" : "Words")") {
                perform(model)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.mapping.problem != nil || count == 0)
        }
    }

    private func summary(_ plan: AnkiImportPlan) -> String {
        var parts = ["\(plan.usable.count) \(plan.usable.count == 1 ? "word" : "words")"]
        if plan.duplicates > 0 { parts.append("\(plan.duplicates) already here") }
        if plan.incomplete > 0 { parts.append("\(plan.incomplete) incomplete") }
        if plan.recordings > 0 { parts.append("\(plan.recordings) recordings") }
        if plan.pictures > 0 { parts.append("\(plan.pictures) pictures") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Work

    private static let packageTypes: [UTType] = {
        var types: [UTType] = []
        if let apkg = UTType(filenameExtension: "apkg") { types.append(apkg) }
        types.append(.zip)
        return types
    }()

    private func open(_ url: URL) {
        speaker.stop()
        stage = .reading
        let profile = profile

        Task {
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try await AnkiImportModel.prepare(url, profile: profile)
                }.value

                let model = AnkiImportModel(prepared, profile: profile, existing: store.library.entries)
                model.chooseTarget(in: store.library)
                stage = .mapping(model)
            } catch let failure as AnkiPackage.Failure {
                stage = .failed(failure.errorDescription ?? "", failure.recoverySuggestion)
            } catch {
                stage = .failed(error.localizedDescription, nil)
            }
        }
    }

    private func perform(_ model: AnkiImportModel) {
        speaker.stop()
        let words = model.plan.usable
        let package = model.package
        let target = model.target
        let style = model.subdeckStyle
        let layout = model.layout

        stage = .importing(0)
        Task {
            let result = await store.importAnki(
                words,
                from: package,
                profileID: profile.id,
                target: target,
                style: style,
                layout: layout
            ) { fraction in
                if case .importing = stage { stage = .importing(fraction) }
            }
            stage = .done(count: result.count, placement: result.placement)
        }
    }
}
