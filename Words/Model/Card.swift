import Foundation

/// Which way round a word is being asked.
///
/// The first version only ever makes recognition cards. The case that follows
/// it is why the model has a direction at all: adding production later is a new
/// card on an existing word, not a new kind of word.
nonisolated enum CardDirection: String, Codable, CaseIterable, Sendable {

    /// The foreign word is shown; its meaning is recalled.
    case recognition

    /// The meaning is shown; the foreign word is recalled. Not yet made.
    case production

    var title: String {
        switch self {
        case .recognition: "Recognition"
        case .production: "Production"
        }
    }
}

/// One question about one word, with its own schedule.
///
/// A word can carry several of these — both directions, a spelling drill, an
/// audio prompt — and each is scheduled separately, because knowing "Haus"
/// means "house" and being able to produce "Haus" are learned at different
/// speeds.
nonisolated struct Card: Identifiable, Codable, Hashable, Sendable {

    var id: UUID
    var direction: CardDirection
    var scheduling: SchedulingState

    init(id: UUID = UUID(), direction: CardDirection = .recognition, scheduling: SchedulingState = SchedulingState()) {
        self.id = id
        self.direction = direction
        self.scheduling = scheduling
    }
}
