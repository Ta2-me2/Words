import AppKit
import SwiftUI

/// The mark of the assistant: a small sphere of moving colour, in the family
/// of Siri's, with sparkles on it.
///
/// Not the Apple Intelligence symbol itself, which stands for Apple's own
/// features rather than for an app's use of them.
struct AssistantOrb: View {
    var size: CGFloat = 26

    /// Brighter while the pointer is on it or an answer is being written.
    var isLively = false

    static let colors: [Color] = [
        Color(red: 0.25, green: 0.78, blue: 1.0),
        Color(red: 0.36, green: 0.42, blue: 1.0),
        Color(red: 0.72, green: 0.36, blue: 0.96),
        Color(red: 1.0, green: 0.33, blue: 0.56),
        Color(red: 1.0, green: 0.62, blue: 0.24),
        Color(red: 0.25, green: 0.78, blue: 1.0),
    ]

    var body: some View {
        // The colours turn only while it is lively. Turning all the time, it
        // kept a sitting at seven per cent of a processor doing nothing else.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isLively)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 6) / 6 * 360
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: Self.colors, center: .center))
                    .rotationEffect(.degrees(turn))
                    .blur(radius: size * 0.3)
                    .opacity(isLively ? 0.95 : 0.55)

                Circle()
                    .fill(AngularGradient(colors: Self.colors, center: .center))
                    .rotationEffect(.degrees(-turn))
                    .overlay {
                        Circle().fill(
                            RadialGradient(
                                colors: [.white.opacity(0.55), .white.opacity(0)],
                                center: UnitPoint(x: 0.35, y: 0.28),
                                startRadius: 0,
                                endRadius: size * 0.62
                            )
                        )
                    }
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                    }

                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.25), value: isLively)
        .accessibilityHidden(true)
    }
}

/// The button beside the card that opens the assistant.
struct AssistantButton: View {
    var isResponding = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            AssistantOrb(size: 28, isLively: isHovering || isResponding)
                .padding(4)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.1 : 1)
        .animation(.spring(duration: 0.3, bounce: 0.4), value: isHovering)
        .onHover { isHovering = $0 }
        .help("Ask about this card")
        .accessibilityLabel("Ask about this card")
    }
}

/// The small window the assistant talks in.
struct AssistantPanel: View {
    let assistant: CardAssistant
    let readiness: CardAssistant.Readiness

    @State private var draft = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            switch readiness {
            case .ready:
                conversation
                Divider()
                composer
            case .turnedOff:
                unavailable(
                    title: "Apple Intelligence is turned off",
                    message: "Turn it on in System Settings to ask about your cards.",
                    opensSettings: true
                )
            case .preparing:
                unavailable(
                    title: "Apple Intelligence is getting ready",
                    message: "Its model is still being prepared on this Mac. Try again in a few minutes.",
                    opensSettings: false
                )
            case .unsupported:
                unavailable(
                    title: "Not available on this Mac",
                    message: "This Mac can’t run the companion.",
                    opensSettings: false
                )
            case .notInstalled(let name):
                unavailable(
                    title: "\(name) isn’t installed",
                    message: "Install it in Settings, or choose Apple Intelligence there.",
                    opensSettings: false,
                    opensAppSettings: true
                )
            }
        }
        .frame(width: 380, height: 470)
        .onAppear {
            assistant.prewarm()
            isTyping = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            AssistantOrb(size: 22, isLively: assistant.isResponding)

            VStack(alignment: .leading, spacing: 1) {
                Text("Ask about this card")
                    .font(.headline)
                Text(assistant.sourceLabel)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            Spacer(minLength: 8)

            if !assistant.messages.isEmpty {
                Button("Start Over", systemImage: "arrow.counterclockwise") {
                    assistant.startOver()
                    isTyping = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.secondaryText)
                .help("Start a new conversation about this card")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - The conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if assistant.messages.isEmpty {
                        introduction
                    }

                    ForEach(assistant.messages) { message in
                        bubble(message)
                            .id(message.id)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: assistant.messages.last?.text) {
                guard let last = assistant.messages.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anything about this card — the word, the sentence, the grammar. Ask in any language.")
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(assistant.suggestions, id: \.self) { question in
                    Button {
                        assistant.ask(question)
                    } label: {
                        Text(question)
                            .font(.callout)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Palette.subtleFill, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: CardAssistant.Message) -> some View {
        if message.isLearner {
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Spacer(minLength: 40)
                    Text(message.text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Palette.selection.opacity(0.18), in: .rect(cornerRadius: 12, style: .continuous))
                }

                // Said by the app, from the library itself, whatever the
                // answer below it says.
                ForEach(message.libraryWords, id: \.self) { word in
                    Label {
                        Text("In your library: **\(word.word)** — \(word.meaning) · \(AssistantText.status(of: word))")
                    } icon: {
                        Image(systemName: "books.vertical")
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(2)
                }
            }
        } else if message.text.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Thinking…")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)
            }
        } else if message.isProblem {
            Label(message.text, systemImage: "exclamationmark.bubble")
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(Self.formatted(message.text))
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The model writes Markdown — bold words, italic sentences, lists. The
    /// inline part is drawn; line breaks are kept as they came.
    private static func formatted(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    // MARK: - Asking

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask anything, in any language", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(1...4)
                    .focused($isTyping)
                    .onSubmit(send)

                if assistant.isResponding {
                    Button("Stop", systemImage: "stop.circle.fill") { assistant.stop() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .font(.title2)
                        .foregroundStyle(Palette.secondaryText)
                        .help("Stop the answer")
                } else {
                    Button("Ask", systemImage: "arrow.up.circle.fill", action: send)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .font(.title2)
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Palette.tertiaryText : Palette.selection)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Ask")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Palette.card, in: .rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.separator)
            }

            Text("Written by \(assistant.modelName), which can make mistakes.")
                .font(.caption2)
                .foregroundStyle(Palette.tertiaryText)
        }
        .padding(10)
    }

    private func send() {
        let question = draft
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !assistant.isResponding else { return }
        draft = ""
        assistant.ask(question)
    }

    // MARK: - Not available

    private func unavailable(
        title: String,
        message: String,
        opensSettings: Bool,
        opensAppSettings: Bool = false
    ) -> some View {
        VStack(spacing: 10) {
            Spacer()
            AssistantOrb(size: 40)
                .saturation(0)
                .opacity(0.6)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
            if opensSettings, let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                Button("Open System Settings") { NSWorkspace.shared.open(url) }
                    .padding(.top, 4)
            }
            if opensAppSettings {
                SettingsLink { Text("Open Settings") }
                    .padding(.top, 4)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
