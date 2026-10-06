import Foundation

/// One line of the vocabulary table.
///
/// A flattened copy rather than the word itself, so the table can sort on plain
/// comparable values and does not have to reach into a card's schedule to draw
/// a row.
nonisolated struct WordRow: Identifiable, Hashable {
    let id: UUID
    let term: String
    let meaning: String
    let note: String

    /// Empty when the word is not filed under a deck, so the column sorts the
    /// unfiled words together instead of scattering them.
    let deckName: String

    /// The article the word takes, where its language has one. Shown beside the
    /// word but never sorted on: a hundred words filed under "die" would be a
    /// dictionary nobody could use.
    let article: String

    /// How the word can be heard.
    let audio: AudioAvailability

    /// Nothing, then the system voice, then a recording of its own — so sorting
    /// on the column gathers the words still waiting to be recorded.
    let audioOrder: Int

    /// Whether the learner drew something for it.
    let hasAssociation: Bool

    /// Whether it carries a photograph instead.
    let hasPicture: Bool

    /// Nothing, then a drawing, then a photo — so sorting on the column gathers
    /// the words that already have a picture of either kind.
    let associationOrder: Int

    let stageTitle: String
    let stageSymbol: String

    /// New first, then the stages in the order a word passes through them.
    let stageOrder: Int

    /// Words with no schedule sort to the end: they are not waiting for
    /// anything, they have simply not started.
    let dueSort: Date
    let dueText: String

    init(
        entry: Entry,
        profile: LanguageProfile,
        now: Date,
        deckName: String? = nil,
        hasVoice: Bool = false,
        calendar: Calendar = .current
    ) {
        id = entry.id
        term = entry.term
        article = entry.articlePrefix(in: profile) ?? ""
        meaning = entry.meaning
        note = entry.note
        self.deckName = deckName ?? ""

        audio = entry.audioAvailability(hasVoice: hasVoice)
        switch audio {
        case .none: audioOrder = 0
        case .voice: audioOrder = 1
        case .clip: audioOrder = 2
        }

        hasAssociation = entry.hasAssociation
        hasPicture = entry.picture != nil
        associationOrder = hasPicture ? 2 : (hasAssociation ? 1 : 0)

        let state = entry.recognitionCard?.scheduling ?? SchedulingState()
        stageTitle = state.stage.title
        stageSymbol = state.stage.symbol

        switch state.stage {
        case .new: stageOrder = 0
        case .learning: stageOrder = 1
        case .relearning: stageOrder = 2
        case .review: stageOrder = 3
        }

        if state.stage == .new {
            dueSort = .distantFuture
            dueText = "—"
        } else {
            dueSort = state.dueDate ?? now
            dueText = DueText.describe(state.dueDate, now: now, calendar: calendar)
        }
    }
}

/// The columns of the vocabulary table, each of which can order it.
nonisolated enum WordColumn: String, CaseIterable, Identifiable, Sendable {
    case word
    case meaning
    case deck
    case audio
    case drawing
    case stage
    case due

    var id: String { rawValue }

    var title: String {
        switch self {
        case .word: "Word"
        case .meaning: "Meaning"
        case .deck: "Deck"
        case .audio: "Audio"
        case .drawing: "Drawing"
        case .stage: "Stage"
        case .due: "Due"
        }
    }
}

/// How the table is ordered: by one column, one way.
nonisolated struct WordSort: Hashable, Sendable {
    var column: WordColumn = .due
    var ascending = true
}

extension WordRow {

    /// Rows in a table's order. Rows that tie on the column keep a fixed order
    /// among themselves — by word, then by identity — so that a table sorted
    /// by stage does not shuffle its rows every time a word is edited.
    nonisolated static func sorted(_ rows: [WordRow], by sort: WordSort) -> [WordRow] {
        rows.sorted { first, second in
            let order = compare(first, second, on: sort.column)
            if order != .orderedSame {
                return sort.ascending ? order == .orderedAscending : order == .orderedDescending
            }
            let byWord = first.term.localizedStandardCompare(second.term)
            if byWord != .orderedSame { return byWord == .orderedAscending }
            return first.id.uuidString < second.id.uuidString
        }
    }

    nonisolated private static func compare(_ first: WordRow, _ second: WordRow, on column: WordColumn) -> ComparisonResult {
        switch column {
        case .word: first.term.localizedStandardCompare(second.term)
        case .meaning: first.meaning.localizedStandardCompare(second.meaning)
        case .deck: first.deckName.localizedStandardCompare(second.deckName)
        case .audio: order(first.audioOrder, second.audioOrder)
        case .drawing: order(first.associationOrder, second.associationOrder)
        case .stage: order(first.stageOrder, second.stageOrder)
        case .due: order(first.dueSort, second.dueSort)
        }
    }

    nonisolated private static func order<Value: Comparable>(_ first: Value, _ second: Value) -> ComparisonResult {
        first < second ? .orderedAscending : (first > second ? .orderedDescending : .orderedSame)
    }
}
