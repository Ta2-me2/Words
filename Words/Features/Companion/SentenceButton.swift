import SwiftUI
import WordsCompanion

/// The button that asks the companion for an example sentence for one word.
///
/// Beside the Example field in Add Words, and in every row of a pasted list.
/// The same button in both, because it does the same thing and nobody should
/// have to learn it twice: dim while there is no word to write for, spinning
/// while the model is writing — and a click then lets go of it — and, if
/// nothing usable came back, the field is left alone and the reason is said
/// next to it by whoever put the button there.
struct SentenceButton: View {
    let profile: LanguageProfile
    /// What is being written for, as the view that owns the writer names it.
    let key: String
    /// The word itself, bare: no article, nothing the model has to unpick.
    let word: String
    let meaning: String
    /// Whether the button says what it does, or is only the sparkles.
    var showsTitle = true
    /// The writer this screen shares between its rows, so one request runs at
    /// a time and the row that asked is the row that spins.
    let writer: SentenceWriter
    let filled: (String, String) -> Void

    @Environment(AppSettings.self) private var settings

    private var companion: CompanionModel? { CompanionModel.named(settings.companionID) }
    private var companionName: String { companion?.name ?? "Apple Intelligence" }

    /// Why it cannot be asked: no companion to ask, or no word to ask about.
    private var problem: String? {
        if let problem = SentenceWriter.problem(with: companion) { return problem }
        if word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Type the word first."
        }
        if writer.isWriting { return "\(companionName) is writing another one." }
        return nil
    }

    var body: some View {
        if writer.isWriting(key) {
            Button { writer.cancel() } label: {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    if showsTitle { Text("Writing…") }
                }
            }
            .buttonStyle(.borderless)
            .help("\(companionName) is writing — click to stop")
        } else {
            Button {
                writer.write(
                    key, word: word, meaning: meaning,
                    for: profile, companion: companion, filled: filled
                )
            } label: {
                if showsTitle {
                    Label("Write an Example", systemImage: "sparkles")
                } else {
                    Image(systemName: "sparkles")
                }
            }
            .buttonStyle(.borderless)
            .disabled(problem != nil)
            .help(problem ?? "\(companionName) writes an example sentence using \u{201C}\(word)\u{201D}, and its translation.")
        }
    }
}
