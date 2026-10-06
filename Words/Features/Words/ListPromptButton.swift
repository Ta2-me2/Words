import AppKit
import SwiftUI

/// The button beside Choose File… that holds the instructions for an AI.
///
/// A list of a hundred words is quicker to ask for than to type, and the only
/// hard part of asking is explaining the format. The instructions are here to
/// be copied as they are, or changed once and kept: they are the learner's for
/// this language, and what they want the list to contain is still theirs to
/// write underneath.
struct ListPromptButton: View {
    let profile: LanguageProfile

    @State private var isShown = false

    var body: some View {
        Button("AI Prompt…") { isShown.toggle() }
            .help("Instructions that make an AI write a list in this format")
            .popover(isPresented: $isShown, arrowEdge: .bottom) {
                ListPromptEditor(profile: profile)
            }
    }
}

private struct ListPromptEditor: View {
    let profile: LanguageProfile

    @Environment(LibraryStore.self) private var store

    @State private var draft: String
    @State private var isCopied = false

    init(profile: LanguageProfile) {
        self.profile = profile
        _draft = State(initialValue: ListPrompt.current(for: profile))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt for an AI")
                    .font(.headline)

                Text("Paste it into a chat with an AI, then say what you need — “100 \(LanguageCatalog.name(for: profile.learningCode)) words for level A1”. Paste the list it writes back here.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextEditor(text: $draft)
                .font(.callout.monospaced())
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 320)
                .background(Palette.card, in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                        .strokeBorder(Palette.separator)
                }

            HStack(spacing: 12) {
                Button("Restore Standard") { draft = standard }
                    .disabled(draft == standard)
                    .help("Go back to the prompt the app writes for this language")

                Spacer(minLength: 0)

                if isCopied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.callout)
                        .foregroundStyle(Palette.secondaryText)
                        .transition(.opacity)
                }

                Button("Copy", systemImage: "doc.on.doc") { copy() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 480)
        .animation(.easeOut(duration: 0.15), value: isCopied)
        .onChange(of: draft) { isCopied = false }
        // Closing the window is what keeps a change; there is no Save, because
        // a prompt is not a document and nobody wants to be asked about it.
        .onDisappear { keep() }
    }

    private var standard: String {
        ListPrompt.standard(for: profile)
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(draft, forType: .string)
        isCopied = true
        keep()
    }

    private func keep() {
        // The profile as it is now, not as it was when the window opened:
        // a rename or a voice change in between must not be undone by this.
        guard var current = store.library.profile(id: profile.id) else { return }
        let stored = ListPrompt.stored(draft, for: current)
        guard stored != current.listPrompt else { return }
        current.listPrompt = stored
        store.save(current)
    }
}
