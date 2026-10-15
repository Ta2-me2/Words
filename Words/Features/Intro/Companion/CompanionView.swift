import SwiftUI

/// The companion.
///
/// Drawn rather than animated frame by frame, so it can be any size and can
/// hold any pose between two moods instead of only the poses somebody drew.
///
/// Two kinds of motion, kept apart on purpose. Its *life* — breathing, bobbing,
/// blinking, the small wander of the eyes — is worked out from the clock, so it
/// never stops and never needs winding. Its *pose* — how open the eyes are,
/// where they look, how it leans — comes from the mood, and is eased from the
/// old pose to the new one by hand. By hand because a `TimelineView` redraws
/// every frame and SwiftUI's own animation would be overwritten by the next
/// frame before it had travelled anywhere.
struct CompanionView: View {

    var mood: CompanionMood

    /// How wide it is. Everything else is a fraction of this.
    var size: CGFloat = 200

    /// Where it is looking, over and above whatever the mood says: the field
    /// being typed into, so it watches the learner work.
    var attention: CGSize = .zero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var previous: CompanionExpression = CompanionMood.asleep.expression
    @State private var changedAt: Date = .distantPast

    /// How long it takes to settle into a new mood.
    private let settling: Double = 0.55

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let now = context.date
            let clock = now.timeIntervalSinceReferenceDate
            let pose = settledPose(at: now)
            let life = Life(clock: clock, pose: pose, still: reduceMotion)

            creature(pose: pose, life: life)
        }
        .frame(width: size, height: size)
        .onChange(of: mood) { old, _ in
            previous = CompanionExpression.between(previous, old.expression, settledAmount(at: .now))
            changedAt = .now
        }
        .accessibilityHidden(true)
    }

    // MARK: - Drawing

    @ViewBuilder
    private func creature(pose: CompanionExpression, life: Life) -> some View {
        let squash = pose.squash + life.squash
        let scale = pose.scale * (1 + life.swell)

        ZStack {
            shadow(life: life, scale: scale)

            ZStack {
                shell
                eyes(pose: pose, life: life)
            }
            // Area is kept: wider means shorter, so it reads as a soft thing
            // being pressed rather than a picture being stretched.
            .scaleEffect(x: scale * (1 + squash), y: scale * (1 - squash), anchor: .bottom)
            .rotationEffect(pose.tilt, anchor: .bottom)
            .offset(y: -life.rise)
        }
    }

    /// The soft body: its own colour down the body, one light from above and
    /// to the right, and its own blue left showing on the shaded side.
    private var shell: some View {
        CloudShape()
            .fill(CompanionPalette.body)
            .overlay {
                // The flush at the foot. A band across the body would read as
                // two colours stuck together; this reads as one thing that is
                // pink where it is pink.
                CloudShape()
                    .fill(RadialGradient(
                        colors: [
                            CompanionPalette.deepBlush.opacity(0.85),
                            CompanionPalette.blush.opacity(0.45),
                            CompanionPalette.blush.opacity(0),
                        ],
                        center: UnitPoint(x: 0.58, y: 0.95),
                        startRadius: 0,
                        endRadius: size * 0.55
                    ))
            }
            .overlay {
                CloudShape()
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0)],
                        center: UnitPoint(x: 0.62, y: 0.14),
                        startRadius: 0,
                        endRadius: size * 0.62
                    ))
            }
            .overlay {
                // Not a shadow. The left of the reference is not darker, it is
                // *bluer* — the side the light is not washing out — and
                // painting a grey shadow there is what makes a soft object
                // look like a sticker with a bevel on it.
                CloudShape()
                    .fill(RadialGradient(
                        colors: [CompanionPalette.sky.opacity(0.42), CompanionPalette.sky.opacity(0)],
                        center: UnitPoint(x: 0.10, y: 0.46),
                        startRadius: 0,
                        endRadius: size * 0.52
                    ))
            }
            .overlay {
                // The faintest turning away at the rim, which is all the
                // modelling a matte thing needs.
                CloudShape()
                    .fill(RadialGradient(
                        colors: [.clear, .black.opacity(0.07)],
                        center: UnitPoint(x: 0.48, y: 0.40),
                        startRadius: size * 0.30,
                        endRadius: size * 0.58
                    ))
            }
    }

    /// The shadow it stands on. It shrinks and sharpens as the companion
    /// rises, which is most of what says the thing is in a room.
    private func shadow(life: Life, scale: Double) -> some View {
        let lift = life.rise / max(life.bob, 0.001)
        return Ellipse()
            .fill(Color.black.opacity(0.13 - lift * 0.05))
            .frame(width: size * (0.56 - lift * 0.05), height: size * 0.075)
            .blur(radius: size * (0.035 + lift * 0.012))
            .offset(y: size * 0.47)
            .scaleEffect(scale)
    }

    /// Where the eyes sit, measured off the reference rather than guessed.
    /// They are most of the face, and a few points too small turns a creature
    /// into a bun with raisins in it.
    private enum Face {
        static let left: CGFloat = 0.376
        static let right: CGFloat = 0.689
        static let height: CGFloat = 0.411
        static let width: CGFloat = 0.168
        static let tall: CGFloat = 0.251
    }

    private func eyes(pose: CompanionExpression, life: Life) -> some View {
        let gaze = CGSize(
            width: pose.gaze.width + life.wander.width + attention.width,
            height: pose.gaze.height + life.wander.height + attention.height
        )
        return ZStack {
            eye(at: Face.left, pose: pose, life: life, gaze: gaze)
            eye(at: Face.right, pose: pose, life: life, gaze: gaze)
        }
    }

    private func eye(at x: CGFloat, pose: CompanionExpression, life: Life, gaze: CGSize) -> some View {
        let width = size * Face.width
        let height = size * Face.tall
        // The open eye and the smile are never both on screen. They used to
        // cross-fade through each other, and halfway through you could see an
        // eye with a smile drawn over it — so the eye is gone before the
        // smile has really started, with the briefest overlap in between.
        let smiling = Self.smoothstep(0.45, 1.0, pose.happiness)
        let showingEye = 1 - Self.smoothstep(0.0, 0.55, pose.happiness)
        let open = max(0, pose.eyeOpen * (1 - life.blink)) * showingEye
        let travel = size * 0.020

        return ZStack {
            // The open eye, which closes to nothing as it smiles.
            ZStack {
                Capsule(style: .continuous)
                    .fill(.white)
                    .frame(width: width, height: height)

                // Nearly the whole eye, with a white rim left showing. The
                // reference is almost all pupil, and that is what reads as
                // open rather than as suspicious.
                Capsule(style: .continuous)
                    .fill(Color(red: 0.06, green: 0.06, blue: 0.08))
                    .frame(width: width * 0.74, height: height * 0.70)
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(.white.opacity(0.92))
                            .frame(width: width * 0.21)
                            .offset(x: width * 0.10, y: height * 0.09)
                    }
                    .offset(x: gaze.width * travel, y: gaze.height * travel - height * 0.03)
            }
            .frame(width: width, height: height)
            .scaleEffect(y: max(open, 0.001), anchor: .center)
            .opacity(showingEye)

            // The smile, which is the whole of its face: it has no mouth, so
            // happiness has to happen in the eyes or nowhere.
            SmilingEye()
                .stroke(Color(red: 0.06, green: 0.06, blue: 0.08),
                        style: StrokeStyle(lineWidth: size * 0.032, lineCap: .round))
                .frame(width: width * 1.1, height: height * 0.40)
                .opacity(smiling)
        }
        .position(x: size * x, y: size * Face.height)
    }

    // MARK: - Settling between moods

    private func settledAmount(at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(changedAt)
        guard elapsed < settling else { return 1 }
        return Self.easeOutBack(max(0, elapsed) / settling)
    }

    private func settledPose(at date: Date) -> CompanionExpression {
        CompanionExpression.between(previous, mood.expression, settledAmount(at: date))
    }

    /// A little past the mark and back, which is what makes a face look like
    /// it meant the expression rather than arrived at it. Gently: a soft thing
    /// that snaps past its pose and back reads as a twitch.
    private static func easeOutBack(_ t: Double) -> Double {
        let c = 0.72
        let p = t - 1
        return 1 + (c + 1) * p * p * p + c * p * p
    }

    /// Nought below, one above, and a smooth ride in between.
    private static func smoothstep(_ from: Double, _ to: Double, _ x: Double) -> Double {
        guard to > from else { return x >= to ? 1 : 0 }
        let t = min(max((x - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// One upward curve. A closed, smiling eye.
private nonisolated struct SmilingEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.55)
        )
        return path
    }
}

/// Everything the clock decides: breathing, bobbing, blinking, and the small
/// wander of the eyes.
///
/// Worked out from the time rather than scheduled, so there is no timer to
/// leak, nothing to get out of step with the drawing, and the companion is in
/// the same place whenever a view is rebuilt.
private struct Life {

    var rise: Double
    var squash: Double
    var swell: Double
    var blink: Double
    var wander: CGSize
    var bob: Double

    init(clock: Double, pose: CompanionExpression, still: Bool) {
        bob = pose.bob

        guard !still else {
            rise = 0; squash = 0; swell = 0; blink = 0; wander = .zero
            return
        }

        let breath = sin(clock * 2 * .pi / pose.breath)
        rise = (breath * 0.5 + 0.5) * pose.bob
        // Stretched at the top of the rise, pressed at the bottom. The oldest
        // trick there is, and the one that does the most.
        squash = -breath * 0.022
        swell = breath * 0.012

        blink = Life.blink(at: clock)

        // Two slow waves that never line up, so the eyes drift without ever
        // repeating a path somebody could notice.
        wander = CGSize(
            width: sin(clock * 0.37) * 0.16 + sin(clock * 0.11 + 1.3) * 0.09,
            height: sin(clock * 0.29 + 2.1) * 0.10
        )
    }

    /// How shut the eyes are, 0 to 1.
    ///
    /// A blink lands somewhere in each four-second window rather than on the
    /// beat, because a face that blinks to a metronome is the uncanniest thing
    /// a drawn character can do. Every so often it blinks twice.
    private static func blink(at clock: Double) -> Double {
        let window = 4.2
        let slot = (clock / window).rounded(.down)
        let offset = noise(slot) * (window - 1.2)
        let local = clock - slot * window - offset

        var amount = shut(local)
        if noise(slot + 0.5) > 0.78 {
            amount = max(amount, shut(local - 0.34))
        }
        return amount
    }

    /// One blink: down fast, up a little slower, which is how an eyelid moves.
    private static func shut(_ t: Double) -> Double {
        guard t >= 0, t < 0.20 else { return 0 }
        return t < 0.075
            ? t / 0.075
            : 1 - (t - 0.075) / 0.125
    }

    private static func noise(_ n: Double) -> Double {
        let x = sin(n * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }
}

extension CompanionExpression {

    /// The pose part way from one mood to the next.
    static func between(_ a: CompanionExpression, _ b: CompanionExpression, _ amount: Double) -> CompanionExpression {
        let t = min(max(amount, 0), 1)
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return CompanionExpression(
            eyeOpen: mix(a.eyeOpen, b.eyeOpen),
            happiness: mix(a.happiness, b.happiness),
            gaze: CGSize(width: mix(a.gaze.width, b.gaze.width), height: mix(a.gaze.height, b.gaze.height)),
            tilt: .degrees(mix(a.tilt.degrees, b.tilt.degrees)),
            squash: mix(a.squash, b.squash),
            bob: mix(a.bob, b.bob),
            breath: mix(a.breath, b.breath),
            scale: mix(a.scale, b.scale)
        )
    }
}
