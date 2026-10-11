import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Export — handing decks to somebody else, or keeping a copy of one's own.
///
/// The whole library is on screen at once, every language and every deck, each
/// with a tick. Not the language being studied: a backup that only ever covered
/// one language would be a backup nobody could rely on, and the one thing a
/// learner wants to hand over is often the deck they are not currently in.
struct ExportView: View {
    @Environment(LibraryStore.self) private var store
    @State private var model = ExportModel()

    var body: some View {
        let plan = model.plan(for: store.library, mediaURL: { store.mediaURL(for: $0) })

        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(store.library.profiles) { profile in
                        language(profile)
                    }
                } header: {
                    Text("What to take")
                } footer: {
                    Text("The number beside a row is what that row itself holds. Ticking a deck ticks the decks inside it.")
                }

                Section {
                    kind("Photographs", symbol: "photo", isOn: $model.selection.includesPhotos, count: counts(plan).photos)
                    kind("Recordings", symbol: "waveform", isOn: $model.selection.includesRecordings, count: counts(plan).sounds)
                    kind("Drawings", symbol: "scribble", isOn: $model.selection.includesDrawings, count: counts(plan).drawings)
                } header: {
                    Text("Files")
                } footer: {
                    Text("Turning one off leaves the words and takes only the files off them.")
                }

                Section {
                    Toggle(isOn: $model.selection.includesProgress) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("My progress")
                            Text("The dates, the schedule and every answer behind it. Leave it off to hand somebody a deck they can start from the beginning; turn it on to keep a copy of your own work.")
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            footer(plan)
        }
        .navigationTitle(AppSection.export.title)
        .navigationSubtitle(subtitle(plan))
        .onChange(of: model.selection) { model.reset() }
    }

    // MARK: - One language and its decks

    @ViewBuilder
    private func language(_ profile: LanguageProfile) -> some View {
        let nodes = ExportModel.nodes(for: profile.id, in: store.library)
        let words = store.library.entries(in: profile.id).count

        TickRow(
            tick: model.tick(of: nodes),
            indent: 0,
            title: "\(profile.flag)  \(profile.name)",
            detail: profile.languagePair,
            count: words,
            isEnabled: !nodes.isEmpty
        ) {
            let wanted = model.tick(of: nodes) != .all
            for node in nodes { model.selection.set(node, to: wanted) }
        }

        ForEach(store.library.topLevelDecks(in: profile.id)) { deck in
            deckRow(deck, indent: 1)
            ForEach(store.library.subdecks(of: deck.id)) { subdeck in
                deckRow(subdeck, indent: 2)
            }
        }

        if nodes.contains(.unfiled(profile.id)) {
            let loose = store.library.entries(in: profile.id).count { $0.deckID == nil }
            TickRow(
                tick: model.selection.contains(.unfiled(profile.id)) ? .all : .none,
                indent: 1,
                title: "Words in no deck",
                detail: nil,
                count: loose,
                isEnabled: true
            ) {
                model.selection.set(.unfiled(profile.id), to: !model.selection.contains(.unfiled(profile.id)))
            }
        }
    }

    private func deckRow(_ deck: Deck, indent: Int) -> some View {
        let own = store.library.entries.count { $0.deckID == deck.id }
        return TickRow(
            tick: model.selection.contains(.deck(deck.id)) ? .all : .none,
            indent: indent,
            title: deck.displayName,
            detail: nil,
            icon: deck.displayIcon,
            count: own,
            isEnabled: true
        ) {
            model.set(.deck(deck.id), to: !model.selection.contains(.deck(deck.id)), in: store.library)
        }
    }

    private func kind(_ title: String, symbol: String, isOn: Binding<Bool>, count: Int) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 18)
                Text(title)
                Spacer(minLength: 8)
                Text(isOn.wrappedValue ? "\(count)" : "—")
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    // MARK: - What it comes to

    private func counts(_ plan: ExportPlan) -> (photos: Int, sounds: Int, drawings: Int) {
        var photos = 0, sounds = 0, drawings = 0
        for entry in plan.entries {
            if entry.picture != nil { photos += 1 }
            if entry.audio != nil { sounds += 1 }
            if entry.exampleAudio != nil { sounds += 1 }
            if entry.association != nil { drawings += 1 }
        }
        return (photos, sounds, drawings)
    }

    private func subtitle(_ plan: ExportPlan) -> String {
        guard !plan.isEmpty else { return "Nothing chosen" }
        var parts = ["\(plan.wordCount) \(plan.wordCount == 1 ? "word" : "words")"]
        if !plan.mediaFiles.isEmpty {
            parts.append("\(plan.mediaFiles.count) \(plan.mediaFiles.count == 1 ? "file" : "files")")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func footer(_ plan: ExportPlan) -> some View {
        HStack(spacing: 12) {
            switch model.state {
            case .writing:
                ProgressView().controlSize(.small)
                Text("Writing…")
                    .foregroundStyle(Palette.secondaryText)

            case .written(let name, let words, let missing):
                Label {
                    Text(missing == 0
                         ? "Wrote \(words) \(words == 1 ? "word" : "words") to \(name)"
                         : "Wrote \(name). \(missing) \(missing == 1 ? "file was" : "files were") missing from the library and left out.")
                } icon: {
                    Image(systemName: missing == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                }
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(2)

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Palette.warning)
                    .lineLimit(2)

            case .choosing:
                Text(plan.isEmpty
                     ? "Tick a language or a deck to export."
                     : "\(plan.wordCount) \(plan.wordCount == 1 ? "word" : "words")\(size(plan))")
                    .foregroundStyle(Palette.secondaryText)
            }

            Spacer(minLength: 8)

            Button("Export…", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(plan.isEmpty || model.state == .writing)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func size(_ plan: ExportPlan) -> String {
        guard plan.mediaBytes > 0 else { return "" }
        return " · about \(plan.mediaBytes.formatted(.byteCount(style: .file)))"
    }

    // MARK: - Writing it

    private func save() {
        let plan = model.plan(for: store.library, mediaURL: { store.mediaURL(for: $0) })
        guard !plan.isEmpty else { return }

        let panel = NSSavePanel()
        panel.title = "Export"
        panel.nameFieldStringValue = "\(model.suggestedName(for: plan, in: store.library)).\(WordsPackage.fileExtension)"
        panel.canCreateDirectories = true
        if let type = UTType(filenameExtension: WordsPackage.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.isExtensionHidden = false

        // As a sheet on the window rather than a modal of its own:
        // `runModal` stops the main thread, which stops the window answering
        // anything at all while the panel is up.
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model.write(plan, to: url, using: store, appVersion: AppVersion.described) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            panel.begin(completionHandler: write)
        }
    }
}

/// One row of the export tree: a tick, a name, and what ticking it takes.
private struct TickRow: View {
    let tick: ExportModel.Tick
    let indent: Int
    let title: String
    var detail: String?
    var icon: DeckIcon?
    let count: Int
    let isEnabled: Bool
    let toggle: () -> Void

    var body: some View {
        // A real button rather than a row with a tap gesture on it: a gesture
        // is invisible to the keyboard and to VoiceOver, which would leave the
        // whole screen unusable without a mouse.
        Button(action: toggle) {
            row
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("\(title), \(count) \(count == 1 ? "word" : "words")")
        .accessibilityAddTraits(tick == .all ? .isSelected : [])
    }

    private var row: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: CGFloat(indent) * 20, height: 1)

            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(tick == .none ? Palette.tertiaryText : Palette.selection)

            if let icon {
                switch icon {
                case .symbol(let name):
                    Image(systemName: name).foregroundStyle(Palette.secondaryText).frame(width: 18)
                case .emoji(let emoji):
                    Text(emoji).frame(width: 18)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }

            Spacer(minLength: 8)

            Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .opacity(isEnabled ? 1 : 0.5)
    }

    private var symbol: String {
        switch tick {
        case .none: "square"
        case .some: "minus.square.fill"
        case .all: "checkmark.square.fill"
        }
    }
}
