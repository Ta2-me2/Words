import AppKit
import SwiftUI

/// The companion coming apart and the word putting itself together out of it.
///
/// Assembled rather than scattered. The obvious reading of "it bursts and
/// becomes the name" is an explosion that happens to leave letters behind, and
/// that is the version that looks cheap: an explosion is noise, and noise is
/// not a word. So the particles leave the body in a hurry and then *arrive*,
/// one sweep from left to right, the way a word is written.
///
/// It resolves into real text at the end. The particles are only ever the way
/// the word gets there — what is left standing is a `Text`, crisp at any scale,
/// which is also what the app can hand to the window behind it.
struct WordmarkBurst: View {

    /// Called once the word has formed and been held.
    var onDone: () -> Void

    /// Called once, the moment the specks stop being specks.
    var onAssemble: () -> Void = {}

    /// How long the whole thing takes, the holding of the finished word
    /// included. Under two seconds is hurried, over four is somebody admiring
    /// their own animation.
    private let duration: Double = 3.1

    private let wordmark = "Words"
    private let markSize: CGFloat = 104
    private let bodySize: CGFloat = 190

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var motes: [Mote] = []
    @State private var began: Date?
    @State private var finished = false

    var body: some View {
        ZStack {
            if reduceMotion {
                calm
            } else {
                flight
            }
        }
        .frame(width: 640, height: 320)
        .task { await start() }
    }

    // MARK: - With motion

    private var flight: some View {
        TimelineView(.animation) { context in
            let p = progress(at: context.date)

            ZStack {
                Canvas { canvas, size in
                    guard p > 0.08 else { return }
                    let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                    for mote in motes {
                        guard let place = mote.place(at: p, around: centre) else { continue }
                        let dot = CGRect(
                            x: place.point.x - mote.radius,
                            y: place.point.y - mote.radius,
                            width: mote.radius * 2,
                            height: mote.radius * 2
                        )
                        canvas.fill(
                            Path(ellipseIn: dot),
                            with: .color(mote.colour.opacity(place.opacity))
                        )
                    }
                }
                .opacity(Self.motesFade(p))
                .blur(radius: p < 0.2 ? 1.2 : 0)

                // The word itself, taking over from the dots that drew it.
                Text(wordmark)
                    .font(.system(size: markSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.primaryText)
                    .opacity(Self.textFade(p))
            }
            .onChange(of: p >= Self.textFadeStart) { _, assembling in
                if assembling { onAssemble() }
            }
            .onChange(of: p >= 1) { _, done in
                if done, !finished { finished = true; onDone() }
            }
        }
    }

    /// The same beat without the motion: the word simply appears where the
    /// companion was. Nothing flies anywhere, because for somebody who has
    /// asked for less motion a cloud of a thousand moving dots is the exact
    /// thing they asked not to see.
    private var calm: some View {
        Text(wordmark)
            .font(.system(size: markSize, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.primaryText)
            .opacity(finished ? 1 : 0)
            .animation(.smooth(duration: 0.9), value: finished)
    }

    // MARK: - Timing

    private func progress(at date: Date) -> Double {
        guard let began else { return 0 }
        return min(1, max(0, date.timeIntervalSince(began) / duration))
    }

    private static func motesFade(_ p: Double) -> Double {
        guard p > 0.60 else { return 1 }
        return max(0, 1 - (p - 0.60) / 0.11)
    }

    private static func textFade(_ p: Double) -> Double {
        guard p > 0.60 else { return 0 }
        return min(1, (p - 0.60) / 0.10)
    }

    /// The word, finished, with nothing happening to it.
    ///
    /// A third of the whole beat, and the most important third. Everything
    /// before it was the name arriving; this is the name being read, and an
    /// animation that cuts the moment its last keyframe lands never gives
    /// anybody time to see what it spelled.
    private static let holding = 0.30

    private static let textFadeStart = 0.60

    // MARK: - Setting up

    @MainActor
    private func start() async {
        guard motes.isEmpty else { return }
        let targets = Self.shape(
            of: wordmark,
            size: NSFont.systemFont(ofSize: markSize, weight: .semibold).pointSize,
            wanted: 1200
        )
        motes = Self.scatter(to: targets, from: bodySize)
        began = .now

        if reduceMotion {
            try? await Task.sleep(for: .milliseconds(450))
            finished = true
            try? await Task.sleep(for: .milliseconds(1100))
            onDone()
        }
    }

    /// Where the word is, as points to fly to.
    ///
    /// Drawn into a one-channel bitmap and read back, which is the only way to
    /// find out where the ink of a typeface actually falls. Every point is in
    /// the frame's own coordinates, centred, so nothing has to know what the
    /// word says.
    private static func shape(of word: String, size: CGFloat, wanted: Int) -> [CGPoint] {
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        let rounded = NSFontDescriptor
            .preferredFontDescriptor(forTextStyle: .largeTitle)
            .withDesign(.rounded)
            .map { NSFont(descriptor: $0.withSymbolicTraits(.bold), size: size) ?? font } ?? font

        let attributes: [NSAttributedString.Key: Any] = [.font: rounded, .foregroundColor: NSColor.white]
        let text = NSAttributedString(string: word, attributes: attributes)
        let bounds = text.size()

        let width = Int(bounds.width.rounded(.up)) + 8
        let height = Int(bounds.height.rounded(.up)) + 8
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return [] }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(at: CGPoint(x: 4, y: 4))
        NSGraphicsContext.current = previous

        guard let data = context.data else { return [] }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)

        var ink: [CGPoint] = []
        ink.reserveCapacity(width * height / 8)
        for y in 0 ..< height {
            for x in 0 ..< width where pixels[y * width + x] > 110 {
                // Back the right way up, and centred on the frame.
                ink.append(CGPoint(
                    x: CGFloat(x) - CGFloat(width) / 2,
                    y: CGFloat(height) / 2 - CGFloat(y)
                ))
            }
        }
        guard !ink.isEmpty else { return [] }

        // Thinned evenly rather than at random, so the strokes keep an even
        // weight instead of coming out blotchy.
        guard ink.count > wanted else { return ink }
        let step = Double(ink.count) / Double(wanted)
        return (0 ..< wanted).map { ink[Int(Double($0) * step)] }
    }

    /// One mote for each point of ink, starting somewhere inside the body and
    /// wearing the colour of the place it left.
    private static func scatter(to targets: [CGPoint], from bodySize: CGFloat) -> [Mote] {
        var generator = SplitMix(seed: 0x5EED_1234)

        return targets.enumerated().map { index, target in
            // Somewhere inside the silhouette, not inside the square it sits
            // in: a word made of the dust around the companion is not made of
            // the companion.
            var unit = CGPoint(x: 0.5, y: 0.5)
            for _ in 0 ..< 24 {
                let candidate = CGPoint(x: generator.unit(), y: generator.unit())
                if CloudShape.contains(candidate) { unit = candidate; break }
            }

            let origin = CGPoint(
                x: (unit.x - 0.5) * bodySize,
                y: (unit.y - 0.5) * bodySize
            )

            // Left to right, like a word being written, with enough jitter
            // that it is a sweep and not a wipe.
            let across = (target.x + 300) / 600
            let delay = 0.08 + across * 0.16 + generator.unit() * 0.07

            return Mote(
                origin: origin,
                target: target,
                colour: CompanionPalette.colour(at: unit),
                radius: 1.45 + generator.unit() * 1.15,
                delay: min(delay, 0.30),
                bow: (generator.unit() - 0.5) * 70,
                index: index
            )
        }
    }
}

/// One speck of the companion on its way to being part of a letter.
private struct Mote {
    var origin: CGPoint
    var target: CGPoint
    var colour: Color
    var radius: CGFloat
    var delay: Double
    var bow: CGFloat
    var index: Int

    /// Where it is, and how solid, at this point in the whole thing.
    func place(at p: Double, around centre: CGPoint) -> (point: CGPoint, opacity: Double)? {
        let travel = 0.34
        let local = (p - delay) / travel
        guard local > -0.12 else { return nil }

        let t = Mote.settle(min(max(local, 0), 1))
        let x = origin.x + (target.x - origin.x) * t
        let y = origin.y + (target.y - origin.y) * t

        // A little off the straight line, most of all half way across, so a
        // thousand specks do not travel as a thousand parallel rulers.
        let arc = sin(min(max(local, 0), 1) * .pi) * bow * 0.35

        let fadeIn = min(1, max(0, (local + 0.12) / 0.22))
        return (CGPoint(x: centre.x + x + arc * 0.25, y: centre.y - y - arc), fadeIn)
    }

    /// Fast away, slow in, and the smallest overshoot at the end so the specks
    /// arrive like things with weight rather than stopping dead on the line.
    private static func settle(_ t: Double) -> Double {
        let c = 1.06
        let p = t - 1
        return 1 + (c + 1) * p * p * p + c * p * p
    }
}

/// A small, fast, repeatable generator.
///
/// Repeatable on purpose: the burst looks the same every time it is run, so
/// what is being looked at while it is tuned is what somebody else will see.
private struct SplitMix {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
