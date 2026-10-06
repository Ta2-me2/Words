import SwiftUI
import WortfallCore

/// Embeddable, self-contained RealityKit game. Callbacks run on the main actor.
public struct WortfallGameView: View {
    private var showsIntroduction = true
    private let onExit: (() -> Void)?
    @StateObject private var session: GameSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    public init(deck: VocabularyDeck = .demo, startingLevel: Int = 1, onAnswer: ((AnswerRecord) -> Void)? = nil, onLevelEnd: ((LevelResult) -> Void)? = nil, scopeID: String = "default", onExit: (() -> Void)? = nil) {
        self.onExit = onExit
        _session = StateObject(wrappedValue: GameSession(deck: deck, startingLevel: startingLevel, onAnswer: onAnswer, onLevelEnd: onLevelEnd, scopeID: scopeID))
    }
    init(session: GameSession, onExit: @escaping () -> Void) {
        self.onExit = onExit
        showsIntroduction = false
        _session = StateObject(wrappedValue: session)
    }
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                NativeGameView(session: session)
                LinearGradient(colors: [.black.opacity(0.08), .clear, .clear, Color(rgb: 0x555879).opacity(0.18)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                if session.snapshot.phase == .playing && !session.reducedMotion { speedLines.allowsHitTesting(false) }
                if showsIntroduction || session.snapshot.phase != .ready {
                    GateSigns(session: session, projection: session.projection, size: geometry.size)
                }
                VStack(spacing: 18) {
                    if showsIntroduction || session.snapshot.phase != .ready { header }
                    Spacer(minLength: 0)
                    if [.playing, .rebound, .finishing].contains(session.snapshot.phase) { playHUD }
                }
                .padding(geometry.size.width < 800 ? 20 : 32)
                if [.playing, .rebound, .finishing].contains(session.snapshot.phase) {
                    DistanceRibbon(progress: session.snapshot.progress, distance: session.snapshot.distance, total: session.snapshot.finishDistance)
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 22).allowsHitTesting(false)
                }
                if showsIntroduction && session.snapshot.phase == .ready { introduction(compact: geometry.size.width < 850) }
                if showsIntroduction && session.snapshot.isPaused { pausePanel }
                if session.snapshot.phase == .won || session.snapshot.phase == .lost { resultPanel }
                if session.isLoading { LevelLoadingOverlay(session: session) }
                if let error = session.error {
                    Text("Could not create the scene\n\(error)").padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(rgb: WorldTheme.level(session.snapshot.level).sky))
            .onContinuousHover { phase in
                if case let .active(location) = phase, !session.snapshot.isPaused { session.point(Double(location.x / max(1, geometry.size.width))) }
            }
        }
        .foregroundStyle(Color.ink)
        .environment(\.colorScheme, .light)
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.pause() } }
        .onAppear { session.reducedMotion = systemReduceMotion }
        .onChange(of: systemReduceMotion) { _, value in session.reducedMotion = value }
        .onDisappear { session.pause() }
    }
    private var theme: WorldTheme { .level(session.snapshot.level) }
    private var header: some View {
        HStack(alignment: .top) {
            if session.snapshot.phase != .ready {
                HStack(spacing: 12) {
                    Text(session.snapshot.score.formatted()).font(.system(size: 23, weight: .black, design: .rounded)).monospacedDigit()
                    Text("×\(session.snapshot.multiplier)").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Color(rgb: 0x8970C5))
                }.padding(.horizontal, 17).padding(.vertical, 10)
                    .background(.white.opacity(0.92), in: Capsule())
            }
            Spacer()
            HStack(spacing: 8) {
                iconButton(session.snapshot.isPaused ? "play.fill" : "pause.fill", label: "Pause, Escape") { session.togglePause() }
                    .disabled([.ready, .won, .lost].contains(session.snapshot.phase))
                iconButton(session.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", label: "Sound") { session.soundEnabled.toggle() }
                if let onExit { iconButton("xmark", label: "Main menu") { session.pause(); onExit() } }
            }
        }
    }
    private var playHUD: some View {
        VStack(spacing: 12) {
            if session.snapshot.phase == .finishing {
                Text("To the finish!").font(.system(size: 20, weight: .heavy, design: .rounded)).padding(.horizontal, 22).padding(.vertical, 10).background(.white.opacity(0.9), in: Capsule())
            }
            if let feedback = session.feedback {
                Text(feedback).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Color.ink)
                    .padding(.horizontal, 18).padding(.vertical, 8).background(.white.opacity(0.9), in: Capsule())
            }
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(index < session.snapshot.lives ? Color(rgb: 0x58C7A9) : Color.white.opacity(0.15))
                        .frame(width: 70, height: 12)
                }
            }.padding(7).background(Color(rgb: 0x29364F).opacity(0.9), in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Health").accessibilityValue("\(session.snapshot.lives) of 3")
        }.frame(maxWidth: .infinity)
    }
    private func introduction(compact: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("LEARN ON THE FLY").font(.system(size: 10, weight: .heavy)).tracking(2.3).foregroundStyle(Color(rgb: 0x9B6997))
                Text("Words.\nSpeed.\nWonder.").font(.system(size: compact ? 43 : 56, weight: .black, design: .rounded)).lineSpacing(-5)
                Text("Slide into new words.\nFind the match. Catch your rhythm.").font(.system(size: 14, weight: .medium)).lineSpacing(5).foregroundStyle(Color.ink.opacity(0.7))
                VStack(alignment: .leading, spacing: 12) {
                    rule("arrow.left.and.right", "Three zones. One correct answer.", 0x8C7AC8)
                    rule("sparkles", "Build a streak. Earn more points.", 0xC19343)
                    rule("heart.fill", "Four correct answers restore one life.", 0xDF7B92)
                }
                Button { session.start() } label: {
                    HStack { Text("Let’s slide"); Spacer(); Image(systemName: "arrow.right") }
                        .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(.white).padding(19)
                        .background(Color(rgb: 0xEF857F), in: RoundedRectangle(cornerRadius: 19))
                }.buttonStyle(.plain)
                Text("MOUSE · ← → · 1 2 3").font(.system(size: 9, weight: .bold)).tracking(1.8).frame(maxWidth: .infinity).foregroundStyle(Color.ink.opacity(0.5))
            }.padding(compact ? 26 : 34).frame(width: compact ? 340 : 405)
                .background(Color(rgb: 0xFFFBF4).opacity(0.96), in: RoundedRectangle(cornerRadius: 32))
                .shadow(color: Color.ink.opacity(0.08), radius: 30, y: 15)
            Spacer()
        }.padding(.horizontal, compact ? 28 : 52).padding(.top, 60)
    }
    private var pausePanel: some View {
        modal {
            Text("Take a breather").font(.system(size: 28, weight: .black, design: .rounded))
            Text("The slope can wait. Continue when you’re ready.").font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Toggle("Game sounds", isOn: $session.soundEnabled)
            Toggle("Reduce motion effects", isOn: $session.reducedMotion)
            action("Continue sliding", symbol: "play.fill") { session.togglePause(); session.scene?.focus() }
        }
    }
    private var resultPanel: some View {
        let won = session.snapshot.phase == .won
        return modal {
            Image(systemName: won ? "flag.checkered" : "heart.slash.fill").font(.system(size: 40, weight: .bold)).foregroundStyle(Color(rgb: won ? 0xDDB05C : 0xE88699))
            Text(won ? "Well done!" : "One more try?").font(.system(size: 34, weight: .black, design: .rounded))
            Text(won ? "Level \(session.snapshot.level) complete. A longer slope awaits." : "Out of lives. Give this level another try.").font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 35) {
                resultStat("LEVEL SCORE", "\(session.snapshot.result.score)")
            }.padding(.vertical, 10)
            if let missed = session.snapshot.records.last(where: { !$0.isCorrect }) {
                VStack(spacing: 4) {
                    Text("REMEMBER FOR NEXT TIME").font(.system(size: 9, weight: .bold)).tracking(1.4)
                    Text("\(missed.prompt) → \(missed.correctAnswer)").font(.system(size: 16, weight: .bold, design: .rounded))
                }.padding(15).frame(maxWidth: .infinity).background(Color(rgb: 0xF3EAF4), in: RoundedRectangle(cornerRadius: 15))
            }
            if let onExit { Button("Main menu", action: onExit).buttonStyle(.plain).font(.headline) }
            action(won ? "Next level" : "Try again", symbol: won ? "arrow.right" : "arrow.clockwise") { Task { if won { await session.next(); if !showsIntroduction { session.start() } } else { await session.retry() } } }
        }
    }
    private func translation(for id: String) -> String { session.translation(for: id) }
    private func resultStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 6) { Text(title).font(.system(size: 9, weight: .bold)).tracking(1); Text(value).font(.system(size: 28, weight: .black, design: .rounded)) }
    }
    private func modal<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color(rgb: 0x293451).opacity(0.32).ignoresSafeArea()
            VStack(spacing: 20, content: content).padding(34).frame(width: 430)
                .background(Color(rgb: 0xFFFCF5), in: RoundedRectangle(cornerRadius: 30)).shadow(color: .black.opacity(0.15), radius: 40, y: 15)
        }
    }
    private func rule(_ symbol: String, _ text: String, _ color: UInt32) -> some View {
        HStack(spacing: 10) { Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(Color(rgb: color)).frame(width: 24); Text(text).font(.system(size: 11, weight: .semibold)) }
    }
    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { HStack { Text(title); Spacer(); Image(systemName: symbol) }.font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(.white).padding(18).background(Color(rgb: 0xEF857F), in: RoundedRectangle(cornerRadius: 17)) }.buttonStyle(.plain)
    }
    private func iconButton(_ symbol: String, label: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Image(systemName: symbol).font(.system(size: 15, weight: .bold)).frame(width: 42, height: 42).background(.white.opacity(0.75), in: Circle()) }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
    private var speedLines: some View {
        Canvas { context, size in
            let phase = session.snapshot.distance.truncatingRemainder(dividingBy: 8) / 8
            for i in 0..<32 {
                let angle = Double(i) / 32 * .pi * 2
                let r = 0.65 + (Double(i % 3) / 3 + phase).truncatingRemainder(dividingBy: 1) * 0.35
                let center = CGPoint(x: size.width / 2, y: size.height * 0.48)
                var path = Path()
                path.move(to: CGPoint(x: center.x + cos(angle) * size.width * r * 0.65, y: center.y + sin(angle) * size.height * r * 0.65))
                path.addLine(to: CGPoint(x: center.x + cos(angle) * size.width * (r + 0.07) * 0.65, y: center.y + sin(angle) * size.height * (r + 0.07) * 0.65))
                context.stroke(path, with: .color(.white.opacity(0.12 + session.snapshot.boost * 0.28)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }
}
