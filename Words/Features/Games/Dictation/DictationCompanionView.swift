import SwiftUI
import WordsCompanion

/// Asking the companion to write an example for every word that has none.
///
/// Nothing reaches the library until it has been read. Every line can be
/// edited or dropped, because the learner is the one who will be taught by it
/// and the model is the one that cannot be asked whether it was right.
struct DictationCompanionView: View {
    let profile: LanguageProfile
    let deckID: UUID?

    @Environment(LibraryStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var maker = SentenceMaker()
    @State private var limit = 20
    @State private var saved: Int?

    private var companion: CompanionModel? { CompanionModel.named(settings.companionID) }
    private var companionName: String { companion?.name ?? "Apple Intelligence" }

    private var candidates: [Entry] {
        DictationMaterial.wordsWithoutExamples(for: profile, in: store.library, deckID: deckID)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Make Sentences", subtitle: "\(companionName) · \(profile.languagePair)")

            if maker.lines.isEmpty {
                setup
            } else {
                written
            }

            Divider()
            footer
        }
        .frame(width: 620, height: 600)
    }

    // MARK: - Before

    private var setup: some View {
        Form {
            Section {
                LabeledContent("Words with no example yet", value: "\(candidates.count)")
                Stepper(value: $limit, in: 1 ... 200, step: 5) {
                    LabeledContent("Write for", value: "\(min(limit, candidates.count))")
                }
            } header: {
                Text("What there is")
            } footer: {
                Text("The oldest words first. A sentence is written for each, and goes onto that word as its example — so it turns up in this game and on the card during an ordinary sitting.")
            }

            if candidates.isEmpty {
                Section {
                    Label("Every word in this language already has an example.", systemImage: "checkmark.circle")
                        .foregroundStyle(Palette.complete)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - As they arrive

    private var written: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(maker.lines) { line in
                        row(line)
                            .id(line.id)
                        Divider()
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 8)
            }
            .onChange(of: maker.finished) {
                guard let writing = maker.lines.first(where: { $0.state == .writing }) else { return }
                withAnimation { proxy.scrollTo(writing.id, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func row(_ line: SentenceMaker.Line) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                maker.setKept(!line.isKept, for: line.id)
            } label: {
                Image(systemName: line.isKept ? "checkmark.square.fill" : "square")
                    .foregroundStyle(line.isKept ? Palette.selection : Palette.tertiaryText)
            }
            .buttonStyle(.plain)
            .disabled(line.state != .done)
            .opacity(line.state == .done ? 1 : 0.3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(line.term)
                        .font(.body.weight(.medium))
                    Text(line.meaning)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                    Spacer(minLength: 4)
                    state(of: line)
                }

                switch line.state {
                case .done:
                    TextField("Sentence", text: Binding(
                        get: { line.sentence },
                        set: { maker.edit(line.id, sentence: $0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.callout)

                    TextField("Translation", text: Binding(
                        get: { line.translation },
                        set: { maker.edit(line.id, translation: $0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)

                case .refused(let why):
                    HStack(spacing: 8) {
                        Text(why)
                            .font(.caption)
                            .foregroundStyle(Palette.warning)
                        Button("Try Again") { maker.retry(line.id, for: profile, companion: companion) }
                            .buttonStyle(.link)
                            .disabled(maker.isRunning)
                    }

                case .waiting, .writing:
                    Text(line.state == .writing ? "writing…" : "waiting")
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
        }
        .padding(.vertical, 8)
        .opacity(line.isKept || line.state != .done ? 1 : 0.45)
    }

    @ViewBuilder
    private func state(of line: SentenceMaker.Line) -> some View {
        switch line.state {
        case .writing: ProgressView().controlSize(.small)
        case .done: Image(systemName: "sparkles").foregroundStyle(Palette.selection).font(.caption)
        case .refused: Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.warning).font(.caption)
        case .waiting: EmptyView()
        }
    }

    // MARK: - Below

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            if let failure = maker.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Palette.warning)
                    .lineLimit(2)
            } else if let saved {
                Label("Saved \(saved) to your library", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)
            } else if !maker.lines.isEmpty {
                Text("\(maker.finished) of \(maker.lines.count) written · \(maker.usable.count) to keep")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            if maker.isRunning {
                Button("Stop") { maker.stop() }
            } else if maker.lines.isEmpty {
                Button("Close") { dismiss() }
                Button("Write \(min(limit, candidates.count))") { begin() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(candidates.isEmpty)
            } else if saved != nil {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Discard") { dismiss() }
                Button("Save \(maker.usable.count) to Library") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(maker.usable.isEmpty)
            }
        }
        .padding(Metrics.cardPadding)
    }

    private func begin() {
        maker.prepare(Array(candidates.prefix(limit)))
        maker.start(for: profile, companion: companion)
    }

    private func save() {
        let keeping = maker.usable
        for line in keeping {
            store.setExample(line.sentence, translation: line.translation, for: line.id)
        }
        saved = keeping.count
    }
}
