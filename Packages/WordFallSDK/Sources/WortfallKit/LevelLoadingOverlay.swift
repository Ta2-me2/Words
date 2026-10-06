import SwiftUI

/// Progress counts completed preparation work, not an estimated download time.
struct LevelLoadingOverlay: View {
    @ObservedObject var session: GameSession

    var body: some View {
        ZStack {
            Color.black.opacity(0.48).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "mountain.2.fill")
                        .foregroundStyle(Color(rgb: 0xB6AEF0)).font(.title2)
                    Text("Preparing your slope")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
                HStack {
                    Text("Level \(session.snapshot.level)")
                    Spacer()
                    Text("\(Int(session.loadingProgress * 100))%")
                        .monospacedDigit()
                }.font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
                ProgressView(value: session.loadingProgress)
                    .tint(Color(rgb: 0xF39B94))
                    .accessibilityLabel("Level preparation")
                Text(session.loadingStage)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                Text("Your run starts when everything is ready.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            .padding(28).frame(width: 360)
            .foregroundStyle(.white)
            .background(Color(rgb: 0x171C2C), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        }
        .contentShape(Rectangle())
        .environment(\.colorScheme, .dark)
    }
}
