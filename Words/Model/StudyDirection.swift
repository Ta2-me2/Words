import Foundation

/// Which way round a language's cards are asked.
///
/// Not a second card with a schedule of its own — that is what
/// `CardDirection.production` is kept for. This turns the card the word already
/// has around: the meaning is shown, the word is recalled, and the answer goes
/// to the same schedule. A learner who asks for it wants the words they are
/// learning practised from the other side, not twice as many reviews.
nonisolated enum StudyDirection: String, Codable, CaseIterable, Identifiable, Sendable {

    /// The word is shown and its meaning recalled. How every card was asked
    /// before there was a choice.
    case wordToMeaning

    /// The meaning is shown and the word recalled.
    case meaningToWord

    /// Some cards one way and some the other, half and half.
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wordToMeaning: "Word → Meaning"
        case .meaningToWord: "Meaning → Word"
        case .mixed: "Mixed"
        }
    }

    /// What one card shows first in a sitting.
    ///
    /// A mixed sitting decides by the card and the sitting together: the same
    /// card is asked the same way every time it comes back in one sitting — a
    /// word being learned should not change sides between its steps — and may
    /// be asked the other way in the next.
    func prompt(for cardID: UUID, seed: UInt64) -> CardPrompt {
        switch self {
        case .wordToMeaning:
            return .word
        case .meaningToWord:
            return .meaning
        case .mixed:
            let (high, low) = cardID.halves
            var value = seed ^ high
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value ^= low
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            return value & 1 == 0 ? .word : .meaning
        }
    }
}

/// What a card shows before its answer.
nonisolated enum CardPrompt: Hashable, Sendable {
    /// The word; the meaning is the answer.
    case word
    /// The meaning; the word is the answer.
    case meaning
}

/// The order new words are started in.
nonisolated enum NewWordOrder: String, Codable, CaseIterable, Identifiable, Sendable {

    /// The first word added is the first word learned.
    case added

    /// Any word in scope, in an order that changes every day.
    case random

    var id: String { rawValue }

    var title: String {
        switch self {
        case .added: "In the order added"
        case .random: "In random order"
        }
    }
}

private extension UUID {
    nonisolated var halves: (UInt64, UInt64) {
        let bytes = uuid
        let high = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7]
            .reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let low = [bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15]
            .reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return (high, low)
    }
}
