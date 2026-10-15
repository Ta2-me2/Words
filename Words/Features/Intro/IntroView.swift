import SwiftUI

/// The first thing anybody sees.
///
/// One scene rather than a sequence of screens, and — this is the whole of it —
/// **one companion**. It is created once, at the top of this view, and from
/// then on only moves: to the middle to be talked to, to the side to watch the
/// tour, back to the middle to come apart. Everything else arrives and leaves
/// around it.
///
/// That matters more than it sounds. A second `CompanionView` built for the
/// tour would be a different view with its own state, so it would appear at the
/// new place rather than travel there — and the creature would blink out of
/// existence and back in somewhere else, which is the one thing that destroys
/// the illusion that anybody is there.
///
/// Everything it says is in a bubble pointing at it. Text in the middle of a
/// screen is the app talking; a bubble with a tail is somebody talking.
struct IntroView: View {

    /// Called once, with the language that was settled on.
    let onFinished: (IntroChoice) -> Void

    @State private var model = IntroModel()
    @State private var audio = IntroAudio()
    @State private var listing = false
    @State private var naming = false
    @State private var arrived = false
    @FocusState private var typing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stage: IntroStage { model.stage }

    /// One curve for everything that moves, so nothing in the scene travels at
    /// a different speed from anything else. A little bounce, not much: this
    /// is a soft creature, not a rubber ball.
    private var move: Animation {
        reduceMotion ? .easeInOut(duration: 0.3) : .spring(duration: 0.75, bounce: 0.16)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                IntroBackdrop()

                film(in: geo)
                burst(in: geo)
                creature(in: geo)
                column(in: geo)
            }
            // Every stage change is animated from one place. Without this the
            // model's own changes arrive unannounced and the scene snaps.
            .animation(move, value: stage)
            .animation(move, value: arrived)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            SoundSwitch(audio: audio)
                .padding(20)
        }
        .toolbar(.hidden, for: .windowToolbar)
        .modifier(Choosers(listing: $listing, naming: $naming, pick: pick))
        .task {
            arrived = true
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

    // MARK: - The companion

    private func creature(in geo: GeometryProxy) -> some View {
        CompanionView(mood: stage.mood, size: 190, attention: attention)
            .scaleEffect(arrived ? companionScale : 0.45)
            .opacity(arrived ? companionOpacity : 0)
            .position(
                x: geo.size.width * companionPlace.x,
                y: geo.size.height * companionPlace.y
            )
    }

    /// Where it stands, as a fraction of the window.
    private var companionPlace: CGPoint {
        switch stage {
        case .touring: CGPoint(x: 0.145, y: 0.5)
        case .becoming, .done: CGPoint(x: 0.5, y: 0.47)
        default: CGPoint(x: 0.5, y: 0.30)
        }
    }

    private var companionScale: Double {
        if case .touring = stage { return 0.68 }
        return 1
    }

    /// It goes as the specks come out of it. The burst does not draw it any
    /// more — there is only ever the one, and this is where it fades.
    private var companionOpacity: Double {
        switch stage {
        case .becoming, .done: 0
        default: 1
        }
    }

    /// Where it is looking, over and above its mood: down at the field while
    /// somebody is typing into it, so it is watching them work.
    private var attention: CGSize {
        guard case .asking = stage, typing else { return .zero }
        return CGSize(width: 0, height: 0.18)
    }

    // MARK: - What it says, and what you do

    /// The bubble and the controls under it, hung from a line below the
    /// companion's chin so they move when it does.
    private func column(in geo: GeometryProxy) -> some View {
        VStack(spacing: 20) {
            if hasSpeech {
                SpeechBubble { speech }
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }

            controls
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, geo.size.height * companionPlace.y + 104)
        .opacity(columnShows ? 1 : 0)
        .allowsHitTesting(columnShows)
    }

    /// Whether it has anything to say at this moment. An empty bubble is a
    /// bubble that failed to load.
    private var hasSpeech: Bool {
        switch stage {
        case .asking, .thinking, .choosing, .lost, .greeting: true
        default: false
        }
    }

    private var columnShows: Bool {
        switch stage {
        case .waking, .touring, .becoming, .done: false
        default: true
        }
    }

    @ViewBuilder
    private var speech: some View {
        switch stage {
        case .asking:
            VStack(spacing: 6) {
                Text("Hello.")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text("Write “hello” in the language you want to learn.")
                    .font(.title3)
                    .foregroundStyle(Palette.secondaryText)
            }
            .transition(.blurReplace)

        case .thinking:
            ThinkingDots()
                .transition(.blurReplace)

        case .choosing:
            VStack(spacing: 6) {
                Text("“\(model.typed)”")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("A few languages say it that way. Which is yours?")
                    .font(.title3)
                    .foregroundStyle(Palette.secondaryText)
            }
            .transition(.blurReplace)

        case .lost:
            VStack(spacing: 6) {
                Text("I don’t know that one.")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Show me which language you mean.")
                    .font(.title3)
                    .foregroundStyle(Palette.secondaryText)
            }
            .transition(.blurReplace)

        case .greeting(let choice):
            VStack(spacing: 10) {
                Text(choice.reply ?? choice.displayName)
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .reads(choice.code ?? "en")

                HStack(spacing: 8) {
                    Text(choice.flag).font(.title2)
                    Text("\(choice.displayName) it is.")
                        .font(.title3)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .transition(.blurReplace)

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch stage {
        case .asking:
            asking

        case .choosing(let codes):
            choosing(codes)

        case .lost:
            lost

        default:
            Color.clear.frame(height: 1)
        }
    }

    private var asking: some View {
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
                    .transition(.opacity)
            }

            quiet("or choose from a list") { listing = true }
        }
    }

    private func choosing(_ codes: [String]) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ForEach(codes, id: \.self) { code in
                    Button {
                        audio.play(.choose)
                        model.choose(.known(code))
                    } label: {
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

            quiet("none of these") { model.askAgain() }
        }
    }

    private var lost: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Button("Choose from a list") { listing = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                Button("Make my own") { naming = true }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            quiet("let me type it again") { model.askAgain() }
        }
    }

    private func quiet(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(Palette.secondaryText)
    }

    private func pick(_ choice: IntroChoice) {
        listing = false
        naming = false
        audio.play(.choose)
        model.choose(choice)
    }

    // MARK: - The tour

    @ViewBuilder
    private func film(in geo: GeometryProxy) -> some View {
        if case .touring = stage {
            let width = min(geo.size.width * 0.70, 900)

            VStack(alignment: .trailing, spacing: 12) {
                TourFilm(onEnd: model.endTour)
                    .frame(width: width)

                quiet("Skip") { model.endTour() }
            }
            .position(x: geo.size.width * 0.60, y: geo.size.height * 0.5)
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
        }
    }

    // MARK: - The wordmark

    @ViewBuilder
    private func burst(in geo: GeometryProxy) -> some View {
        switch stage {
        case .becoming, .done:
            WordmarkBurst(onDone: { model.finish() }, onAssemble: { audio.play(.assemble) })
                .position(x: geo.size.width * 0.5, y: geo.size.height * 0.47)
                .transition(.opacity)
        default:
            EmptyView()
        }
    }

    // MARK: - Sound

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
/// Not the window's usual background, and not private to the introduction
/// either: it is also what is shown while the library is still being read, so
/// that the first frame anybody sees is this and not the frame of an app they
/// have not set up yet.
struct IntroBackdrop: View {

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
