import SwiftUI

/// Sentences the learner writes straight into the game.
///
/// For the ones that belong to no word — a line from a song, something heard
/// at work. A sentence that belongs to a word belongs on that word, as its
/// example, which is where the companion puts the ones it makes.
struct DictationSentencesView: View {
    let profile: LanguageProfile
    let store: DictationStore

    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var chosen: Set<UUID> = []
    @State private var added: Int?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Your Sentences", subtitle: profile.languagePair)

            Form {
                Section {
                    TextEditor(text: $draft)
                        .font(.body.monospaced())
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                        .padding(6)
                        .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                                .strokeBorder(Palette.separator)
                        }
                        .overlay(alignment: .topLeading) {
                            if draft.isEmpty {
                                Text(Self.placeholder)
                                    .font(.body.monospaced())
                                    .foregroundStyle(Palette.tertiaryText)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                        }

                    HStack {
                        if let added {
                            Label(
                                added == 0 ? "Nothing new in that" : "Added \(added)",
                                systemImage: added == 0 ? "equal.circle" : "checkmark.circle"
                            )
                            .font(.callout)
                            .foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        Button("Add", action: add)
                            .disabled(parsed.isEmpty)
                    }
                } header: {
                    Text("Write or paste")
                } footer: {
                    Text("One sentence a line. A translation after a semicolon is optional, and is shown once the answer is in.")
                }

                Section {
                    if store.progress.sentences.isEmpty {
                        Text("None yet.")
                            .foregroundStyle(Palette.tertiaryText)
                    } else {
                        List(selection: $chosen) {
                            ForEach(store.progress.sentences.reversed()) { sentence in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(sentence.text)
                                    if !sentence.meaning.isEmpty {
                                        Text(sentence.meaning)
                                            .font(.caption)
                                            .foregroundStyle(Palette.secondaryText)
                                    }
                                }
                                .tag(sentence.id)
                            }
                        }
                        .frame(minHeight: 160)
                    }
                } header: {
                    HStack {
                        Text("\(store.progress.sentences.count) \(store.progress.sentences.count == 1 ? "sentence" : "sentences")")
                        Spacer()
                        if !chosen.isEmpty {
                            Button("Delete \(chosen.count)", role: .destructive) {
                                store.remove(sentences: chosen)
                                chosen = []
                            }
                            .buttonStyle(.link)
                        }
                    }
                } footer: {
                    Text("Deleting one forgets how it was going, too.")
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Metrics.cardPadding)
        }
        .frame(width: 520, height: 560)
    }

    private static let placeholder = """
        Ich gehe nach Hause.;I am going home.
        Das Wetter ist heute schön.
        """

    /// One sentence a line; a semicolon separates it from what it means.
    private var parsed: [DictationSentence] {
        draft.components(separatedBy: .newlines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let parts = line.split(separator: ";", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard let text = parts.first, !text.isEmpty else { return nil }
            return DictationSentence(text: text, meaning: parts.count > 1 ? parts[1] : "")
        }
    }

    private func add() {
        added = store.add(parsed)
        draft = ""
    }
}
