import SwiftUI

/// The companion's silhouette: a handful of overlapping circles filled as one
/// shape.
///
/// Overlapping circles in a single path, filled with the non-zero rule, come
/// out as their union — one soft outline with no seams where they meet. That
/// is cheaper than blurring and thresholding a layer into a blob, and it holds
/// its edge: the reference is a firm soft-plastic toy, and a metaball silhouette
/// wobbles like a lava lamp however carefully it is tuned.
///
/// The lobes are in a unit square so everything scales from one number, and
/// they are shared rather than private because the wordmark has to know where
/// the body was in order to come apart out of it.
nonisolated struct CloudShape: Shape {

    /// Where the puffs are, in a unit square, with their radii.
    ///
    /// Six round the outside and one filling the middle, which is what stops
    /// the union having a dent in the centre.
    static let lobes: [(centre: CGPoint, radius: CGFloat)] = [
        (CGPoint(x: 0.345, y: 0.300), 0.205),
        (CGPoint(x: 0.625, y: 0.268), 0.225),
        (CGPoint(x: 0.790, y: 0.470), 0.205),
        (CGPoint(x: 0.655, y: 0.700), 0.205),
        (CGPoint(x: 0.385, y: 0.722), 0.190),
        (CGPoint(x: 0.215, y: 0.512), 0.195),
        (CGPoint(x: 0.500, y: 0.500), 0.285),
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for lobe in Self.lobes {
            let radius = lobe.radius * rect.width
            let centre = CGPoint(
                x: rect.minX + lobe.centre.x * rect.width,
                y: rect.minY + lobe.centre.y * rect.height
            )
            path.addEllipse(in: CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
        return path
    }

    /// Whether a point in the unit square is inside the body.
    ///
    /// Used to scatter particles through it rather than round it, so the
    /// wordmark is made of the companion and not of a cloud of dust it was
    /// standing in.
    static func contains(_ point: CGPoint) -> Bool {
        lobes.contains { lobe in
            let dx = point.x - lobe.centre.x
            let dy = point.y - lobe.centre.y
            return dx * dx + dy * dy <= lobe.radius * lobe.radius
        }
    }
}

/// The colours the companion is made of.
///
/// Its own type because two things need them and they must agree: the body
/// itself, and the particles it comes apart into. A particle that is not the
/// colour of the thing it came out of reads as confetti thrown at the screen.
nonisolated enum CompanionPalette {

    // Read off the reference rather than chosen: a gradient guessed by eye
    // comes out a shade grey every time, because grey is the average of
    // everything and the eye averages.
    static let lit = Color(red: 0.718, green: 0.906, blue: 0.992)      // #B7E7FD
    static let sky = Color(red: 0.435, green: 0.765, blue: 0.937)      // #6FC3EF
    static let lilac = Color(red: 0.686, green: 0.745, blue: 0.933)    // #AFBEEE
    static let blush = Color(red: 0.886, green: 0.600, blue: 0.816)    // #E299D0
    static let deepBlush = Color(red: 0.933, green: 0.600, blue: 0.761) // #EE99C2

    /// Blue at the top, lavender through the middle, pink at the foot. The
    /// whole colour of the thing is this one run down the body; the light and
    /// the shadow are laid over it afterwards.
    static let stops: [(Double, Color)] = [
        (0.00, Color(red: 0.718, green: 0.906, blue: 0.992)),   // #B7E7FD
        (0.22, Color(red: 0.565, green: 0.839, blue: 0.973)),   // #90D6F8
        (0.46, Color(red: 0.584, green: 0.776, blue: 0.945)),   // #95C6F1
        (0.72, Color(red: 0.835, green: 0.745, blue: 0.925)),   // #D5BEEC
        (1.00, blush),                                          // #E299D0
    ]

    static let body = LinearGradient(
        stops: stops.map { .init(color: $0.1, location: $0.0) },
        startPoint: .top,
        endPoint: .bottom
    )

    /// The colour at a point of the unit square, near enough for a particle to
    /// be the colour of the place it left.
    ///
    /// The same three layers the body is painted in, flattened: it does not
    /// have to be exact, it has to be unmistakably the same creature.
    static func colour(at point: CGPoint) -> Color {
        var colour = down(point.y)
        colour = blend(colour, deepBlush, flush(at: point) * 0.72)
        colour = blend(colour, .white, light(at: point) * 0.22)
        colour = blend(colour, sky, shade(at: point) * 0.34)
        return colour
    }

    /// Where the body's own colour has got to, this far down.
    private static func down(_ v: Double) -> Color {
        let y = min(max(v, 0), 1)
        for index in 1 ..< stops.count where y <= stops[index].0 {
            let (a, from) = stops[index - 1]
            let (b, to) = stops[index]
            return blend(from, to, b == a ? 0 : (y - a) / (b - a))
        }
        return blush
    }

    /// The pink welling up from the foot, which is not a band across the body
    /// but a flush strongest at the bottom middle.
    private static func flush(at point: CGPoint) -> Double {
        falloff(point, centre: CGPoint(x: 0.58, y: 0.95), reach: 0.55)
    }

    /// How lit a point is. The light is above and to the right.
    private static func light(at point: CGPoint) -> Double {
        falloff(point, centre: CGPoint(x: 0.62, y: 0.14), reach: 0.62)
    }

    /// How much of the body's own blue shows through, which is most on the
    /// shaded left where nothing is washing it out.
    private static func shade(at point: CGPoint) -> Double {
        falloff(point, centre: CGPoint(x: 0.10, y: 0.46), reach: 0.52)
    }

    private static func falloff(_ point: CGPoint, centre: CGPoint, reach: Double) -> Double {
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        return max(0, 1 - sqrt(dx * dx + dy * dy) / reach)
    }

    private static func blend(_ a: Color, _ b: Color, _ amount: Double) -> Color {
        let t = min(max(amount, 0), 1)
        let first = NSColor(a).usingColorSpace(.sRGB) ?? .white
        let second = NSColor(b).usingColorSpace(.sRGB) ?? .white
        return Color(
            red: first.redComponent + (second.redComponent - first.redComponent) * t,
            green: first.greenComponent + (second.greenComponent - first.greenComponent) * t,
            blue: first.blueComponent + (second.blueComponent - first.blueComponent) * t
        )
    }
}
