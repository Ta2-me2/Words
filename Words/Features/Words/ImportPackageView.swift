import SwiftUI
import UniformTypeIdentifiers

/// Add Words ▸ From Words — opening a package somebody exported.
///
/// Nothing is added until the whole of what is in the file is on screen: which
/// languages, how many words, how many are already here. A package can hold
/// several languages, and each one is told separately where to land, because
/// "put this German in with my German" and "make me a new Greek" are different
/// answers to the same question.
struct ImportPackageView: View {
    @Environment(LibraryStore.self) private var store

    @State private var model = PackageImportModel()
    @State private var isChoosingFile = false
    @State private var isTargeted = false

    static let readableTypes: [UTType] = [UTType(filenameExtension: WordsPackage.fileExtension), .zip]
        .compactMap { $0 }

    var body: some View {
        Form {
            switch model.state {
            case .empty, .failed:
                Section {
                    dropArea
                } footer: {
                    if case .failed(let message) = model.state {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("A Words package holds whole decks — the words, their transcriptions, photographs, recordings and drawings — and the decks they were filed in.")
                    }
                }

            case .read(let package):
                contents(of: package)

            case .importing:
                Section { Label("Adding…", systemImage: "hourglass") }

            case .added(let words, let duplicates, let languages):
                Section {
                    Label {
                        Text(summary(words: words, duplicates: duplicates, languages: languages))
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                    Button("Open Another…") { model.clear() }
                        .buttonStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: Self.readableTypes) { result in
            if case .success(let url) = result { open(url) }
        }
    }

    // MARK: - Choosing one

    private var dropArea: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 34))
                .foregroundStyle(Palette.tertiaryText)
            Text("Drop a .\(WordsPackage.fileExtension) here")
                .foregroundStyle(Palette.secondaryText)
            Button("Choose File…") { isChoosingFile = true }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(
                    isTargeted ? Palette.selection : Palette.separator,
                    lineWidth: isTargeted ? 1.5 : 1
                )
        }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            open(url)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func open(_ url: URL) {
        model.open(url, in: store.library)
    }

    // MARK: - What is inside

    @ViewBuilder
    private func contents(of package: WordsPackage) -> some View {
        let plan = model.plan(for: store.library)

        Section {
            ForEach(package.manifest.profiles) { profile in
                language(profile, in: package)
            }
        } header: {
            Text(package.manifest.profiles.count == 1 ? "The language inside" : "The languages inside")
        } footer: {
            Text("Words already in the language you choose are left as they are — nothing you have studied is ever overwritten.")
        }

        Section {
            LabeledContent("Words to add", value: "\(plan.wordCount)")
            if plan.duplicates > 0 {
                LabeledContent("Already in your library", value: "\(plan.duplicates)")
            }
            if !plan.decks.isEmpty {
                LabeledContent("Decks to make", value: "\(plan.decks.count)")
            }
            if !plan.media.isEmpty {
                LabeledContent("Files to copy", value: "\(plan.media.count)")
            }
            if package.manifest.includesProgress {
                LabeledContent("Answers to bring over", value: "\(plan.reviews.count)")
            }
        } header: {
            Text("What will happen")
        } footer: {
            Text(wrote(package))
        }

        Section {
            HStack {
                Button("Choose Another…") { model.clear() }
                    .buttonStyle(.link)
                Spacer()
                Button("Add \(plan.wordCount) \(plan.wordCount == 1 ? "Word" : "Words")") {
                    Task { await model.add(plan, from: package, to: store) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func language(_ profile: LanguageProfile, in package: WordsPackage) -> some View {
        let words = package.manifest.entries.count { $0.profileID == profile.id }

        LabeledContent {
            Picker("", selection: model.binding(for: profile.id)) {
                Text("A new language").tag(PackageImport.Destination.newLanguage)
                Divider()
                ForEach(store.library.profiles) { mine in
                    Text(mine.languagePair).tag(PackageImport.Destination.existing(mine.id))
                }
                Divider()
                Text("Leave it out").tag(PackageImport.Destination.skip)
            }
            .labelsHidden()
            .frame(maxWidth: 220)
        } label: {
            HStack(spacing: 8) {
                Text(profile.flag)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name)
                    Text("\(profile.languagePair) · \(words) \(words == 1 ? "word" : "words")")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
    }

    private func wrote(_ package: WordsPackage) -> String {
        let when = package.manifest.createdAt.formatted(date: .abbreviated, time: .shortened)
        var text = "Written by \(package.manifest.createdBy) on \(when)."
        if package.manifest.includesProgress {
            text += " It carries its owner's schedule; the words will arrive part-learned."
        }
        return text
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
