import AppKit
import SwiftUI

/// The card itself: the word, its picture, and — once asked for — everything
/// that answers it.
///
/// One view for every place a card is shown, so that what a learner sees while
/// deciding how to import a deck is the card they will actually study, and not
/// a sketch of it. Everything the card cannot know for itself — whether a sound
/// is playing, what to do when a speaker is pressed, what a picture looks like —
/// is handed in.
struct CardFace<BeforeAnswer: View, AfterAnswer: View>: View {
    let entry: Entry
    let profile: LanguageProfile
    let isRevealed: Bool

    /// What is asked: the word, or — turned around — its meaning. Only the
    /// order changes. Sound stays with the word and the example, and arrives
    /// with the answer either way: the meaning is what the learner already
    /// speaks, and hearing the word before recalling it would answer a card
    /// that asks for the word.
    var prompt: CardPrompt = .word

    /// Shown with the word, before the answer and after it: a picture is part
    /// of the word, not a clue to be earned.
    var picture: NSImage?

    var isSpeaking = false
    var canHearWord = true
    var canHearExample = true
    var listen: () -> Void = {}
    var listenExample: () -> Void = {}

    @ViewBuilder var beforeAnswer: () -> BeforeAnswer
    @ViewBuilder var afterAnswer: () -> AfterAnswer

    var body: some View {
        // A scroll view whose content is at least as tall as the view: a short
        // card sits in the middle exactly as it always has, and a long one — a
        // meaning that is a whole grammar table — can be read to the end.
        GeometryReader { proxy in
            ScrollView(.vertical) {
                content(fitting: proxy.size.height - CardColumn.verticalPadding * 2)
                    .frame(maxWidth: Metrics.readableWidth)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, CardColumn.verticalPadding)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func content(fitting height: CGFloat) -> some View {
        // Not a VStack: the photo is the one part of a card that can give way,
        // and a stack cannot be told so. See `CardColumn`.
        CardColumn(spacing: 16, fits: height) {
            switch prompt {
            case .word: word
            case .meaning: meaning
            }

            if let picture {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
                    .layoutValue(key: GivesWay.self, value: true)
            }

            if !isRevealed {
                beforeAnswer()
            } else {
                Divider()
                    .frame(width: 96)

                VStack(spacing: 8) {
                    switch prompt {
                    case .word: meaning
                    case .meaning: word
                    }

                    // Only where the language has no article to show instead:
                    // the gender still has to reach the learner somehow.
                    if let gender = entry.gender, entry.articlePrefix(in: profile) == nil {
                        Text(gender.title)
                            .font(.callout)
                            .foregroundStyle(Palette.secondaryText)
                    }

                    // Only once the answer is out: hearing the word before
                    // recalling it would answer the question.
                    if canHearWord { listenButton }

                    if !entry.example.isEmpty {
                        VStack(spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(entry.example)
                                    .font(.callout)
                                    .italic()
                                    .multilineTextAlignment(.center)

                                if canHearExample { exampleButton }
                            }

                            if !entry.exampleTranslation.isEmpty {
                                Text(entry.exampleTranslation)
                                    .font(.callout)
                                    .foregroundStyle(Palette.secondaryText)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 2)
                    }

                    afterAnswer()
                }

                // Its own row of the column, so that it can be left out of the
                // sum the photo is sized against: a note is for scrolling down
                // to, and a conjugation table brought in from a deck must not
                // shrink the picture to a stamp to make room for itself.
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryText)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .layoutValue(key: MayOverflow.self, value: true)
                }
            }
        }
    }

    /// The word, with its article once the answer is out.
    ///
    /// The article arrives with the answer and the pair settles back into the
    /// middle of the card. No timing of its own: it moves with everything else
    /// the answer brings, so a word with an article opens exactly like a word
    /// without. On a card turned around the word is itself the answer, and has
    /// its article from the moment it appears.
    private var word: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                if isRevealed, let article = entry.articlePrefix(in: profile) {
                    Text(article)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(Palette.secondaryText)
                }

                Text(entry.term)
                    .font(.largeTitle.weight(.semibold))
                    .textSelection(.enabled)
                    // A selectable text is offered its half of the row first and
                    // cut short to "Ha…" before the article has taken its share;
                    // the word is the one thing on the card that must not be.
                    .layoutPriority(1)
            }

            // Under the word wherever the word is — the prompt side or the
            // answer side. It says how to say what is already on screen, so it
            // gives nothing away that the word has not given away first.
            if !entry.transcription.isEmpty {
                Text(entry.transcription)
                    .font(.title3)
                    .foregroundStyle(Palette.secondaryText)
                    .textSelection(.enabled)
            }
        }
        .multilineTextAlignment(.center)
    }

    /// As big as the word it answers when it is a word: a translation in small
    /// print reads as a footnote to the thing being learned. A meaning that is a
    /// paragraph, or a table brought in from a deck, is set to be read instead.
    @ViewBuilder
    private var meaning: some View {
        let lines = entry.meaning.split(separator: "\n").count
        if entry.meaning.count <= 40 && lines <= 1 {
            Text(entry.meaning)
                .font(.largeTitle)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        } else if entry.meaning.count <= 140 && lines <= 3 {
            Text(entry.meaning)
                .font(.title2)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        } else {
            Text(entry.meaning)
                .font(.body)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    /// The word said out loud: its own recording if it has one, the language's
    /// voice if it has not.
    private var listenButton: some View {
        Button(action: listen) {
            Label(
                entry.audio == nil ? "Listen" : "Play recording",
                systemImage: isSpeaking ? "speaker.wave.2.fill" : (entry.audio == nil ? "speaker.wave.2" : "waveform")
            )
            .labelStyle(.iconOnly)
            .imageScale(.large)
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Palette.secondaryText)
        .keyboardShortcut("p", modifiers: [])
        .help(entry.audio == nil ? "Hear it in the system voice (P)" : "Play the recording (P)")
        .padding(.top, 2)
    }

    /// The example sentence, said on its own.
    private var exampleButton: some View {
        Button(action: listenExample) {
            Image(systemName: entry.exampleAudio == nil ? "speaker.wave.2" : "waveform")
                .imageScale(.small)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Palette.tertiaryText)
        .keyboardShortcut("p", modifiers: .shift)
        .help(entry.exampleAudio == nil ? "Hear the example (⇧P)" : "Play the example’s recording (⇧P)")
    }
}

/// Marks the part of a card that gives up height when there is not enough.
nonisolated private struct GivesWay: LayoutValueKey {
    static let defaultValue = false
}

/// Marks a part of a card that is allowed to fall below the fold rather than
/// take height from the photo.
nonisolated private struct MayOverflow: LayoutValueKey {
    static let defaultValue = false
}

/// A card's column: everything stacked and centred, with the photo taking
/// whatever height the words leave it.
///
/// A photo is the most elastic thing on a card. Before the answer it is the
/// whole clue and can be large. Once the meaning, the example and its
/// translation arrive, they are what the learner is reading, and a photograph
/// of a fixed size would push them off the bottom of the card — which is how an
/// imported deck used to lose half of every answer. So the words are measured
/// first, and the photo gets the rest, within limits: never so small that it
/// stops being a picture, never so large that a short card looks like a poster.
/// If even the smallest photo leaves too little room, the card scrolls.
private struct CardColumn: Layout {

    /// The margin above and below a card's contents.
    static let verticalPadding: CGFloat = 16

    var spacing: CGFloat

    /// The height the column tries to fit into.
    var fits: CGFloat

    var pictureHeights: ClosedRange<CGFloat> = 64...240
    var pictureMaxWidth: CGFloat = 360

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measure(width: proposal.width, subviews: subviews)
        let width = proposal.width ?? sizes.map(\.width).max() ?? 0
        return CGSize(width: width, height: total(sizes))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measure(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.midX, y: y),
                anchor: .top,
                proposal: ProposedViewSize(sizes[index])
            )
            y += sizes[index].height + spacing
        }
    }

    private func measure(width: CGFloat?, subviews: Subviews) -> [CGSize] {
        var sizes = subviews.map { subview in
            subview[GivesWay.self]
                ? .zero
                : subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
        }
        guard let picture = subviews.firstIndex(where: { $0[GivesWay.self] }) else { return sizes }

        // What must be on screen without scrolling: everything but the photo
        // and the parts that are allowed to be scrolled to.
        let required = zip(subviews, sizes)
            .filter { !$0.0[MayOverflow.self] }
            .map(\.1)
        let room = fits - total(required)
        let height = min(max(room, pictureHeights.lowerBound), pictureHeights.upperBound)
        let pictureWidth = min(width ?? pictureMaxWidth, pictureMaxWidth)
        sizes[picture] = subviews[picture].sizeThatFits(ProposedViewSize(width: pictureWidth, height: height))
        return sizes
    }

    private func total(_ sizes: [CGSize]) -> CGFloat {
        sizes.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, sizes.count - 1))
    }
}

extension CardFace where BeforeAnswer == EmptyView, AfterAnswer == EmptyView {
    init(
        entry: Entry,
        profile: LanguageProfile,
        isRevealed: Bool,
        picture: NSImage? = nil,
        isSpeaking: Bool = false,
        canHearWord: Bool = true,
        canHearExample: Bool = true,
        listen: @escaping () -> Void = {},
        listenExample: @escaping () -> Void = {}
    ) {
        self.entry = entry
        self.profile = profile
        self.isRevealed = isRevealed
        self.picture = picture
        self.isSpeaking = isSpeaking
        self.canHearWord = canHearWord
        self.canHearExample = canHearExample
        self.listen = listen
        self.listenExample = listenExample
        self.beforeAnswer = { EmptyView() }
        self.afterAnswer = { EmptyView() }
    }
}

/// Pictures read from the library, once each.
///
/// The card's body runs whenever anything about it changes — a sound starting,
/// a button hovering — and reading a photograph off the disk on every one of
/// those is the mistake the Library once made with voices.
@MainActor
enum PictureCache {
    private static var images: [String: NSImage] = [:]
    private static var order: [String] = []
    private static let limit = 64

    static func image(for picture: Picture?, store: LibraryStore) -> NSImage? {
        guard let picture else { return nil }
        if let cached = images[picture.file] { return cached }
        guard let image = NSImage(contentsOf: store.mediaURL(for: picture.file)) else { return nil }
        images[picture.file] = image
        order.append(picture.file)
        if order.count > limit, let oldest = order.first {
            order.removeFirst()
            images[oldest] = nil
        }
        return image
    }
}
