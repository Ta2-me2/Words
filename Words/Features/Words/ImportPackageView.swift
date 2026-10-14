import SwiftUI
import UniformTypeIdentifiers

/// Add Words ▸ From Words — opening a package somebody exported.
///
/// The same screen as From Anki, with the nouns changed: choose the file, see
/// what is inside it and how a card will look, say where each language lands,
/// and only then add anything. A package can hold several languages, and each
/// one is asked about separately, because "put this German in with my German"
/// and "make me a new Greek" are different answers to the same question.
struct ImportPackageView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    private let speaker = Speaker.shared

    @State private var model = PackageImportModel()
    @State private var isChoosingFile = false

    static let readableTypes: [UTType] = [UTType(filenameExtension: WordsPackage.fileExtension), .zip]
        .compactMap { $0 }

    var body: some View {
        Group {
            switch model.state {
            case .empty:
                ImportInvitation(
                    title: "Open a Words Package",
                    systemImage: "shippingbox",
                    description: "Drop a .\(WordsPackage.fileExtension) file here, or choose one. You will see every language and word inside it, and how its cards come out, before anything is added.",
                    buttonTitle: "Choose Package…",
                    fileExtension: WordsPackage.fileExtension,
                    choose: { isChoosingFile = true },
                    open: open
                )

            case .read(let package):
                contents(of: package)

            case .importing:
                ImportProgress(title: "Adding…")

            case .added(let words, let duplicates, let languages):
                ImportSuccess(
                    title: "Added \(words) \(words == 1 ? "Word" : "Words")",
                    description: summary(words: words, duplicates: duplicates, languages: languages),
                    showTitle: "Show in Library",
                    show: { router.show(.library) },
                    againTitle: "Open Another Package…",
                    again: { isChoosingFile = true }
                )

            case .failed(let message, let suggestion):
                ImportFailure(
                    title: "This Package Could Not Be Opened",
                    message: message,
                    suggestion: suggestion,
                    buttonTitle: "Choose Another Package…",
                    retry: { isChoosingFile = true }
                )
            }
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: Self.readableTypes) { result in
            if case .success(let url) = result { open(url) }
        }
        .onDisappear { speaker.stop() }
        // The screen keeps this side when another is chosen, so leaving it is
        // not a disappearance; a card still reading itself aloud should stop.
        .onChange(of: router.addMode) { speaker.stop() }
    }

    private func open(_ url: URL) {
        speaker.stop()
        model.open(url, in: store.library)
    }

    // MARK: - What is inside

    private func contents(of package: WordsPackage) -> some View {
        VStack(spacing: 0) {
            header(package)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)

            Divider()

            HStack(alignment: .top, spacing: Metrics.gutter) {
                languages(package)
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 400)

                preview(package)
                    .frame(minWidth: 320, maxWidth: .infinity)
            }
            .padding(Metrics.gutter)
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            footer(package)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
        }
        .onChange(of: store.library.entries.count) { model.replan(in: store.library) }
        .onChange(of: model.position) { speaker.stop() }
    }

    private func header(_ package: WordsPackage) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(package.manifest.profiles.map(\.name).formatted(.list(type: .and)))
                    .font(.headline)
                    .lineLimit(1)
                Text(made(package))
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button("Choose Another Package…") { model.clear() }
        }
    }

    private func made(_ package: WordsPackage) -> String {
        let words = package.manifest.entries.count
        let when = package.manifest.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(words) \(words == 1 ? "word" : "words") · written by \(package.manifest.createdBy) on \(when)"
    }

    // MARK: The languages

    private func languages(_ package: WordsPackage) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: package.manifest.profiles.count == 1 ? "The Language Inside" : "The Languages Inside") {
                Text("Goes to")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
            }

            ScrollView {
                GroupedRows {
                    ForEach(Array(package.manifest.profiles.enumerated()), id: \.element.id) { index, profile in
                        GroupedRow(showsDivider: index < package.manifest.profiles.count - 1) {
                            language(profile, in: package)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            if model.plan.isEmpty {
                Label(
                    model.plan.duplicates > 0
                        ? "Every word in this package is already in your library."
                        : "Every language is being left out — nothing would be added.",
                    systemImage: "exclamationmark.circle"
                )
                .font(.callout)
                .foregroundStyle(Palette.warning)
                .fixedSize(horizontal: false, vertical: true)
            }

            decks
                .padding(.top, 6)
        }
    }

    private func language(_ profile: LanguageProfile, in package: WordsPackage) -> some View {
        let words = package.manifest.entries.count { $0.profileID == profile.id }

        return HStack(spacing: 10) {
            Text(profile.flag)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .lineLimit(1)
                Text("\(profile.languagePair) · \(words) \(words == 1 ? "word" : "words")")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Picker("", selection: model.binding(for: profile.id, in: store.library)) {
                Text("A new language").tag(PackageImport.Destination.newLanguage)
                Divider()
                ForEach(store.library.profiles) { mine in
                    Text(mine.languagePair).tag(PackageImport.Destination.existing(mine.id))
                }
                Divider()
                Text("Leave it out").tag(PackageImport.Destination.skip)
            }
            .labelsHidden()
            .frame(maxWidth: 170)
        }
    }

    /// The decks that will be made, shown before anything is made — the same
    /// promise the Anki side's deck list gives. A deck the library already has
    /// under that name is reused rather than repeated, and so is not here.
    @ViewBuilder
    private var decks: some View {
        if !model.plan.decks.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                SectionHeader("Decks")

                ScrollView {
                    GroupedRows {
                        ForEach(Array(model.plan.decks.enumerated()), id: \.element.id) { index, deck in
                            GroupedRow(showsDivider: index < model.plan.decks.count - 1) {
                                HStack(spacing: 8) {
                                    DeckLabel(title: deck.displayName, icon: deck.displayIcon)
                                        .font(.callout)
                                        .lineLimit(1)
                                        .padding(.leading, deck.isSubdeck ? 18 : 0)

                                    Spacer(minLength: 8)

                                    Text("New")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(Palette.secondaryText)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Palette.subtleFill, in: .capsule)

                                    Text(words(in: deck) > 0 ? "\(words(in: deck))" : "—")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.secondaryText)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 132)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func words(in deck: Deck) -> Int {
        model.plan.entries.count { $0.deckID == deck.id }
    }

    // MARK: The card

    private func preview(_ package: WordsPackage) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: "How It Will Look") {
                HStack(spacing: 6) {
                    Button { model.step(-1) } label: { Image(systemName: "chevron.left") }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Text(model.visible.isEmpty ? "No words" : "\(model.position + 1) of \(model.visible.count)")
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

            if let entry = model.current, let profile = model.profile(of: entry, in: store.library) {
                let hasVoice = Speaker.voice(for: profile) != nil

                CardFace(
                    entry: entry,
                    profile: profile,
                    isRevealed: model.isRevealed,
                    picture: model.picture(for: entry),
                    isSpeaking: speaker.speakingEntryID == entry.id,
                    // The package's own recordings stay in the package until
                    // the words are added; what can be heard here is the voice.
                    canHearWord: hasVoice,
                    canHearExample: hasVoice && !entry.example.isEmpty,
                    listen: { speaker.speak(entry.displayTerm(in: profile), in: profile, entryID: entry.id) },
                    listenExample: { speaker.speak(entry.example, in: profile, entryID: entry.id) }
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

                    Spacer(minLength: 0)
                }
            } else {
                ContentUnavailableView(
                    "Nothing to Add",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("Every word here is already in your library, or every language is being left out.")
                )
                .frame(height: 330)
            }

            if package.manifest.includesProgress {
                Label(
                    "It carries its owner's schedule: the words will arrive part-learned.",
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text("Words already in the language you choose are left as they are — nothing you have studied is ever overwritten.")
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Doing it

    private func footer(_ package: WordsPackage) -> some View {
        let count = model.plan.wordCount
        return ImportFooter(
            summary: summary(model.plan, in: package),
            buttonTitle: "Add \(count) \(count == 1 ? "Word" : "Words")",
            isDisabled: model.plan.isEmpty,
            action: {
                speaker.stop()
                Task { await model.add(model.plan, from: package, to: store) }
            }
        )
    }

    private func summary(_ plan: PackageImport.Plan, in package: WordsPackage) -> String {
        var parts = ["\(plan.wordCount) \(plan.wordCount == 1 ? "word" : "words")"]
        if plan.duplicates > 0 { parts.append("\(plan.duplicates) already here") }
        if !plan.decks.isEmpty { parts.append("\(plan.decks.count) \(plan.decks.count == 1 ? "deck" : "decks")") }
        if !plan.media.isEmpty { parts.append("\(plan.media.count) files") }
        if package.manifest.includesProgress, !plan.reviews.isEmpty {
            parts.append("\(plan.reviews.count) answers")
        }
        return parts.joined(separator: " · ")
    }

    private func summary(words: Int, duplicates: Int, languages: [String]) -> String {
        let into = languages.isEmpty ? "" : " to \(languages.formatted(.list(type: .and)))"
        var text = "Added \(words) \(words == 1 ? "word" : "words")\(into)."
        if duplicates > 0 {
            text += " \(duplicates) \(duplicates == 1 ? "was" : "were") already in your library and left alone."
        }
        return text
    }
}
