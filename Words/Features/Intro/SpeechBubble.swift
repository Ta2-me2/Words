import SwiftUI

/// What the companion says, in a bubble pointing at it.
///
/// Text in the middle of a screen is the app talking. Text in a bubble with a
/// tail is *somebody* talking, and the whole of this screen rests on there
/// being somebody there — so every line it says is in one of these, and
/// everything the learner does (a field, a row of buttons) is outside them.
struct SpeechBubble<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        content
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .padding(.top, BubbleShape.tail)
            .background {
                BubbleShape()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        BubbleShape()
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            }
            .compositingGroup()
    }
}

/// A rounded bubble with a soft tail on top, pointing up at whoever is
/// speaking.
nonisolated struct BubbleShape: Shape {

    static let tail: CGFloat = 11
    private let radius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let body = CGRect(
            x: rect.minX, y: rect.minY + Self.tail,
            width: rect.width, height: rect.height - Self.tail
        )

        var path = Path(roundedRect: body, cornerRadius: radius, style: .continuous)

        // Curved rather than a triangle: a sharp spike on a soft creature
        // reads as a warning sign.
        let tip = CGPoint(x: rect.midX, y: rect.minY)
        let half: CGFloat = 13
        path.move(to: CGPoint(x: tip.x - half, y: body.minY + 1))
        path.addQuadCurve(to: tip, control: CGPoint(x: tip.x - half * 0.45, y: body.minY - Self.tail * 0.55))
        path.addQuadCurve(
            to: CGPoint(x: tip.x + half, y: body.minY + 1),
            control: CGPoint(x: tip.x + half * 0.45, y: body.minY - Self.tail * 0.55)
        )
        path.closeSubpath()
        return path
    }
}

/// Three dots that think.
///
/// What the companion says while it is working out what was typed, because a
/// bubble with nothing in it is a bubble that failed to load.
struct ThinkingDots: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 7) {
                ForEach(0 ..< 3, id: \.self) { index in
                    Circle()
                        .fill(Palette.secondaryText)
                        .frame(width: 8, height: 8)
                        .opacity(reduceMotion ? 0.6 : Self.lift(t, index) * 0.55 + 0.35)
                        .offset(y: reduceMotion ? 0 : -Self.lift(t, index) * 4)
                }
            }
            .frame(height: 22)
        }
    }

    /// Each dot a third of a beat behind the one before it.
    private static func lift(_ t: Double, _ index: Int) -> Double {
        let phase = t * 2.0 - Double(index) * 0.34
        return max(0, sin(phase * .pi))
    }
}
