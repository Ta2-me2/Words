import SwiftUI

/// Projection updates invalidate this small overlay, not the RealityKit host and entire HUD.
struct GateSigns: View {
    @ObservedObject var session: GameSession
    @ObservedObject var projection: GateProjection
    let size: CGSize
    var body: some View {
        if projection.anchors.count == 3 && [.ready, .playing, .rebound].contains(session.snapshot.phase) {
            let center = max(260, min(size.width - 260, projection.anchors[1].x))
            let signY = max(195, min(size.height * 0.55, projection.anchors.map(\.y).min()! - 16))
            let spacing = max(150, min(size.width * 0.22, abs(projection.anchors[2].x - projection.anchors[0].x) / 2))
            ZStack {
                Text(session.snapshot.challenge.prompt)
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .foregroundStyle(Color.ink).lineLimit(2).minimumScaleFactor(0.7)
                    .frame(maxWidth: 320).padding(.horizontal, 24).padding(.vertical, 13)
                    .background(Color(rgb: 0xFFFCF2), in: RoundedRectangle(cornerRadius: 19))
                    .shadow(color: Color.ink.opacity(0.12), radius: 8, y: 3)
                    .position(x: center, y: signY - 75)
                ForEach(0..<3) { lane in
                    let anchor = projection.anchors[lane]
                    let x = max(80, min(size.width - 145, center + CGFloat(lane - 1) * spacing))
                    Path { path in
                        path.move(to: CGPoint(x: x, y: signY + 19)); path.addLine(to: anchor)
                    }.stroke(.white.opacity(0.65), lineWidth: 1)
                    Text(session.snapshot.challenge.options[lane])
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(session.snapshot.challenge.rejectedLanes.contains(lane) ? Color(rgb: 0xB53C61) : Color.ink)
                        .strikethrough(session.snapshot.challenge.rejectedLanes.contains(lane))
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .frame(width: 124).frame(minHeight: 24).padding(.horizontal, 8).padding(.vertical, 8)
                        .background(Color(rgb: 0xFFFCF2).opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(session.snapshot.selectedLane == lane ? Color(rgb: 0xF18B88) : .clear, lineWidth: 2))
                        .position(x: x, y: signY)
                }
            }.allowsHitTesting(false)
        }
    }
}
