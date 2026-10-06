import SwiftUI

struct DistanceRibbon: View {
    let progress: Double
    let distance: Double
    let total: Double
    private let height: CGFloat = 235
    var body: some View {
        let filled = CGFloat(min(1, max(0, progress))) * height
        ZStack(alignment: .topTrailing) {
            Capsule().fill(Color(rgb: 0x29364F).opacity(0.65)).frame(width: 7, height: height)
            Capsule().fill(Color(rgb: 0x90ECD4)).frame(width: 7, height: filled).offset(y: height - filled)
            Text("\(Int(total).formatted()) m")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Color(rgb: 0x29364F), in: Capsule())
                .offset(x: 0, y: -33)
            HStack(spacing: 6) {
                Text("\(Int(distance).formatted()) m")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color(rgb: 0x29364F), in: Capsule())
                Circle().fill(Color(rgb: 0x90ECD4)).frame(width: 11, height: 11)
            }.offset(x: 2, y: max(0, height - filled - 12))
        }.foregroundStyle(.white).frame(width: 110, height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Level progress").accessibilityValue("\(Int(distance)) of \(Int(total)) meters")
    }
}
