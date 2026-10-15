import SwiftUI

/// What the companion is feeling.
///
/// The only thing that decides how it is drawn. Everything else — the eyes,
/// the tilt, how fast it bobs — is read out of the one table below, so a mood
/// is tuned in a single readable place rather than by hunting through a view
/// for the four numbers that make it look sad.
nonisolated enum CompanionMood: Hashable, Sendable, CaseIterable {

    /// Before it has arrived: eyes shut, small, still.
    case asleep

    /// Waiting for the learner to type. Alert, looking slightly down at the
    /// field, breathing.
    case curious

    /// Working out which language was written. Eyes up and to one side, the
    /// way anybody looks when they are remembering something.
    case thinking

    /// It knows. Eyes closed into two happy arcs.
    case delighted

    /// It does not know. Head tilted, eyes wide and a little off-centre.
    case puzzled

    /// Beside the video, watching along: calmer, smaller, not the subject.
    case watching

    /// About to come apart into the wordmark. Still and centred, taking a
    /// breath in.
    case leaving

    var expression: CompanionExpression {
        switch self {
        case .asleep:
            CompanionExpression(eyeOpen: 0, gaze: .zero, tilt: .degrees(-3),
                                squash: 0.06, bob: 2, breath: 4.6, scale: 0.92)
        case .curious:
            CompanionExpression(eyeOpen: 1, gaze: CGSize(width: 0, height: 0.22), tilt: .degrees(0),
                                squash: 0, bob: 6, breath: 3.2, scale: 1)
        case .thinking:
            // Up and to the left, which is where everybody's eyes go when they
            // are looking something up rather than looking at you.
            CompanionExpression(eyeOpen: 0.72, gaze: CGSize(width: -0.5, height: -0.55), tilt: .degrees(-5),
                                squash: -0.03, bob: 3.5, breath: 2.1, scale: 0.99)
        case .delighted:
            CompanionExpression(eyeOpen: 1, happiness: 1, gaze: .zero, tilt: .degrees(0),
                                squash: 0.05, bob: 9, breath: 2.4, scale: 1.04)
        case .puzzled:
            CompanionExpression(eyeOpen: 1.12, gaze: CGSize(width: 0.28, height: -0.1), tilt: .degrees(9),
                                squash: -0.02, bob: 4, breath: 3.6, scale: 1)
        case .watching:
            // Looking right, because that is where the film is. A character
            // standing beside something and looking away from it is the
            // clearest way to say it is not paying attention.
            CompanionExpression(eyeOpen: 0.95, gaze: CGSize(width: 0.55, height: 0.05), tilt: .degrees(2),
                                squash: 0, bob: 4.5, breath: 3.8, scale: 0.86)
        case .leaving:
            // Eyes closed, not half closed. A happiness of a third would draw
            // an open eye and a smile on top of each other, which is a face
            // with four eyes rather than a face that is pleased.
            CompanionExpression(eyeOpen: 1, happiness: 1, gaze: .zero, tilt: .degrees(0),
                                squash: -0.04, bob: 2, breath: 5.0, scale: 1.06)
        }
    }
}

/// Every number the companion is drawn from, for one mood.
///
/// Flat on purpose. A character reads as alive when the pose changes and the
/// silhouette does not, so these are all pose — nothing here can change what
/// shape it is.
nonisolated struct CompanionExpression: Hashable, Sendable {

    /// How open the eyes are. Above 1 is wider than usual, which is most of
    /// what surprise looks like.
    var eyeOpen: Double

    /// How far the eyes have closed into two upward arcs. This is the whole
    /// of the smile, because it has no mouth to smile with.
    var happiness: Double = 0

    /// Where the pupils are aimed, as a fraction of how far they can travel.
    var gaze: CGSize

    var tilt: Angle

    /// Wider and shorter above zero, taller and narrower below. The body keeps
    /// its area, so a squash of 0.06 is 6 % wider and 6 % shorter rather than
    /// simply bigger.
    var squash: Double

    /// How far it rises and falls, in points at its usual size.
    var bob: Double

    /// How long one breath takes, in seconds. Fast is alert, slow is calm, and
    /// a character that breathes at a constant rate reads as a machine.
    var breath: Double

    var scale: Double
}
