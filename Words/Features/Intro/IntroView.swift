import SwiftUI

/// The first thing anybody sees.
///
/// One scene rather than a sequence of screens: the companion is on it from
/// the first frame to the last and never leaves, and everything else arrives
/// and goes around it. That is the whole trick. A wizard that replaces its
/// contents step by step reads as a form being filled in; a character that
/// stays put while the room changes around it reads as a conversation.
struct IntroView: View {

    /// Called once, with the language that was settled on.
    let onFinished: (IntroChoice) -> Void

    @State private var model = IntroModel()
    @State private var audio = IntroAudio()
    @State private var listing = false
    @State private var naming = false
    @FocusState private var typing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stage: IntroStage { model.stage }

    var body: some View {
        ZStack {
            Backdrop()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                scene
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            // On screen from the first frame. An introduction that starts
            // playing music at somebody with no visible way to stop it is the
            // thing people remember about it.
            SoundSwitch(audio: audio)
                .padding(20)
        }
        .toolbar(.hidden, for: .windowToolbar)
        .task {
            model.begin()
            audio.play(.arrive)
            audio.start(.theme)
        }
        .onChange(of: stage) { _, now in
            sound(for: now)
            if case .asking = now { typing = true }
            if case .done(let choice) = now { onFinished(choice) }
        }
    }

    /// Every beat has a sound. Here rather than in the model, because what a
    /// thing sounds like is how it is presented, not what it is.
    private func sound(for stage: IntroStage) {
        switch stage {
        case .waking:
            break
        case .asking:
            audio.stop(.thinking)
        case .thinking:
            audio.play(.ask)
            audio.start(.thinking)
        case .choosing:
            audio.stop(.thinking)
        case .lost:
            audio.stop(.thinking)
            audio.play(.puzzled)
        case .greeting:
            audio.stop(.thinking)
            audio.play(.delight)
        case .touring:
            break
        case .becoming:
            audio.play(.burst)
        case .done:
            audio.play(.open)
            audio.bowOut()
        }
    }

    // MARK: - The scene

    @ViewBuilder
    private var scene: some View {
        if case .becoming = stage {
            WordmarkBurst(onDone: { model.finish() }, onAssemble: { audio.play(.assemble) })
                .frame(maxWidth: .infinity)
                .transition(.opacity)
        } else if case .touring = stage {
            tour
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            VStack(spacing: 34) {
                CompanionView(mood: stage.mood, size: 190, attention: attention)
                    .transition(.scale(scale: 0.55).combined(with: .opacity))

                words
                    .frame(maxWidth: 520)
            }
            .transition(.opacity)
        }
    }

    /// Where the companion is looking, over and above its mood: down at the
    /// field while somebody is typing into it, so it is watching them work.
    private var attention: CGSize {
        guard case .asking = stage, typing else { return .zero }
        return CGSize(width: 0, height: 0.18)
    }

    @ViewBuilder
    private var words: some View {
        switch stage {
        case .waking:
            Color.clear.frame(height: 1)

        case .asking:
            asking

        case .thinking:
            heard

        case .choosing(let codes):
            choosing(codes)

        case .lost:
            lost

        case .greeting(let choice):
            greeting(choice)

        case .touring, .becoming, .done:
            Color.clear.frame(height: 1)
        }
    }

    // MARK: - Asking

    private var asking: some View {
        VStack(spacing: 22) {
            Headline("Hello.", subtitle: "Write “hello” in the language you want to learn.")

            VStack(spacing: 12) {
                TextField("", text: $model.typed, prompt: Text("привет · hola · 你好"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 30, weight: .regular, design: .rounded))
                    .multilineTextAlignment(.center)
                    .focused($typing)
                    .onSubmit(model.submit)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 26)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.quaternary.opacity(0.45))
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(typing ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 2)
                            }
                    }
                    .animation(.smooth(duration: 0.25), value: typing)

                if let nudge = model.nudge {
                    Text(nudge)
                        .font(.callout)
                        .foregroundStyle(Palette.secondaryText)
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }

                Button("or choose from a list") { listing = true }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.top, 2)
            }
        }
        .modifier(Choosers(listing: $listing, naming: $naming, pick: pick))
    }

    /// What it heard, held up while it thinks about it.
    private var heard: some View {
        Text(model.typed)
            .font(.system(size: 34, weight: .regular, design: .rounded))
            .foregroundStyle(Palette.secondaryText)
            .transition(.blurReplace)
    }

    // MARK: - Unsure

    private func choosing(_ codes: [String]) -> some View {
        VStack(spacing: 20) {
            Headline("“\(model.typed)”", subtitle: "A few languages say it that way. Which is yours?")

            HStack(spacing: 12) {
                ForEach(codes, id: \.self) { code in
                    Button { audio.play(.choose); model.choose(.known(code)) } label: {
                        VStack(spacing: 6) {
                            Text(LanguageCatalog.defaultFlag(for: code)).font(.system(size: 30))
                            Text(LanguageCatalog.name(for: code)).font(.callout.weight(.medium))
                        }
                        .frame(minWidth: 112)
                        .padding(.vertical, 16)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.quaternary.opacity(0.4))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("none of these") { model.askAgain() }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    private var lost: some View {
        VStack(spacing: 20) {
            Headline("I don’t know that one.", subtitle: "Show me which language you mean.")

            HStack(spacing: 10) {
                Button("Choose from a list") { listing = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                Button("Make my own") { naming = true }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Button("let me type it again") { model.askAgain() }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
        }
        .modifier(Choosers(listing: $listing, naming: $naming, pick: pick))
    }

    private func pick(_ choice: IntroChoice) {
        listing = false
        naming = false
        model.choose(choice)
    }

    // MARK: - Saying hello back

    private func greeting(_ choice: IntroChoice) -> some View {
        VStack(spacing: 14) {
            // A language it has never heard of gets its own name in the big
            // type instead of a greeting somebody made up for it.
            Text(choice.reply ?? "\(choice.flag) \(choice.displayName)")
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .transition(.blurReplace)
                .reads(choice.code ?? "en")

            Text("\(choice.displayName) it is.")
                .font(.title3)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    // MARK: - The tour

    private var tour: some View {
        HStack(spacing: 36) {
            CompanionView(mood: stage.mood, size: 128)

            VStack(alignment: .leading, spacing: 14) {
                TourFilm(onEnd: model.endTour)

                HStack {
                    Spacer()
                    Button("Skip") { model.endTour() }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .frame(maxWidth: 620)
        }
    }
}

/// A line and the line under it, set the way the rest of this screen is.
private struct Headline: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.title3)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .transition(.blurReplace)
    }
}

/// The two ways out of the question, carried together so the list and the
/// make-your-own sheet are offered from wherever they are asked for.
private struct Choosers: ViewModifier {
    @Binding var listing: Bool
    @Binding var naming: Bool
    var pick: (IntroChoice) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $listing) {
                LanguageChoice(
                    onPick: { pick(.known($0)) },
                    onInvent: { listing = false; naming = true }
                )
            }
            .sheet(isPresented: $naming) {
                InventLanguage { name, flag in pick(.invented(name: name, flag: flag)) }
            }
    }
}

/// The wash behind everything.
///
/// Two very slow blooms in the companion's own colours, far too slow to watch
/// and just fast enough that the screen is never quite still. The point is for
/// the background to feel lit rather than painted — a flat panel behind a soft
/// object makes the object look like a sticker on it.
///
/// It is not the window's usual background. This screen is the one place the
/// app is allowed its own light, and a plain grey field drains the colour out
/// of the only thing on it.
private struct Backdrop: View {

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                base
                bloom(CompanionPalette.sky, x: 0.24 + sin(t * 0.045) * 0.05, y: 0.26 + cos(t * 0.037) * 0.05, strength: 0.34)
                bloom(CompanionPalette.blush, x: 0.76 + cos(t * 0.041) * 0.05, y: 0.74 + sin(t * 0.033) * 0.05, strength: 0.30)
                bloom(CompanionPalette.lit, x: 0.62 + sin(t * 0.029 + 2) * 0.04, y: 0.86 + cos(t * 0.035) * 0.04, strength: 0.18)

                // Holds the eye in the middle, where everything happens.
                RadialGradient(
                    colors: [.clear, (scheme == .dark ? Color.black : Color(red: 0.42, green: 0.45, blue: 0.56)).opacity(scheme == .dark ? 0.45 : 0.10)],
                    center: .center,
                    startRadius: 180,
                    endRadius: 760
                )
            }
            .ignoresSafeArea()
        }
    }

    private var base: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.055, green: 0.067, blue: 0.106), Color(red: 0.086, green: 0.082, blue: 0.133)]
                : [Color(red: 0.976, green: 0.984, blue: 0.996), Color(red: 0.957, green: 0.961, blue: 0.984)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func bloom(_ colour: Color, x: Double, y: Double, strength: Double) -> some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [colour.opacity(strength * (scheme == .dark ? 0.85 : 1)), colour.opacity(0)],
                center: UnitPoint(x: x, y: y),
                startRadius: 0,
                endRadius: max(proxy.size.width, proxy.size.height) * 0.58
            )
            .blendMode(scheme == .dark ? .plusLighter : .normal)
        }
    }
}
