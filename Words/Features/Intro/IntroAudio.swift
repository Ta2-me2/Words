import AVFoundation
import SwiftUI

/// The sounds the introduction makes.
///
/// Every beat the companion has is named here, and each one plays a file from
/// the bundle if there is one. Until the files exist this does nothing at all,
/// quietly — which is the point: the scene can be built, watched and tuned
/// first, and the sounds dropped in afterwards without a line of this changing.
///
/// Kept deliberately small. A first launch that starts playing music at
/// somebody is a thing people complain about, so there is one switch, it is on
/// screen from the first frame, and what it last was is remembered.
@MainActor @Observable
final class IntroAudio {

    /// One sound per thing that happens.
    ///
    /// The file is the name with `.m4a` or `.wav` after it, in the app's
    /// resources.
    enum Cue: String, CaseIterable {
        /// The companion arrives.
        case arrive
        /// Somebody pressed Return.
        case ask
        /// It is working out what was typed. Loops until it stops.
        case thinking
        /// It knows, and is pleased.
        case delight
        /// It does not know.
        case puzzled
        /// A language was picked out of the two or three offered.
        case choose
        /// The body comes apart.
        case burst
        /// The word pulls itself together.
        case assemble
        /// The app opens behind it.
        case open
        /// The music, under everything, from the first frame to the last.
        case theme
    }

    /// Whether the introduction makes any sound. Remembered, because somebody
    /// who turned it off once has said what they think of it.
    var isOn: Bool {
        didSet {
            UserDefaults.standard.set(isOn, forKey: Self.key)
            if !isOn { silence() } else { start(.theme) }
        }
    }

    private static let key = "introSound"
    private static let looping: Set<Cue> = [.theme, .thinking]

    private var players: [Cue: AVAudioPlayer] = [:]

    init() {
        isOn = UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true
    }

    /// Plays a sound once. Does nothing if the file is not there, which is
    /// what every one of these is until somebody records them.
    func play(_ cue: Cue) {
        guard isOn, !Self.looping.contains(cue), let player = player(for: cue) else { return }
        player.currentTime = 0
        player.play()
    }

    /// Starts one of the sounds that keep going.
    func start(_ cue: Cue) {
        guard isOn, let player = player(for: cue), !player.isPlaying else { return }
        player.numberOfLoops = -1
        player.volume = cue == .theme ? 0 : 0.22
        player.play()
        if cue == .theme { fade(player, to: 0.34, over: 2.2) }
    }

    func stop(_ cue: Cue) {
        guard let player = players[cue], player.isPlaying else { return }
        if cue == .theme { fade(player, to: 0, over: 1.4) { player.stop() } } else { player.stop() }
    }

    /// Everything down, for leaving the screen.
    func bowOut() {
        stop(.thinking)
        stop(.theme)
    }

    private func silence() {
        for player in players.values { player.stop() }
    }

    private func player(for cue: Cue) -> AVAudioPlayer? {
        if let known = players[cue] { return known }
        let url = ["m4a", "wav", "aiff"]
            .lazy
            .compactMap { Bundle.main.url(forResource: "Intro-\(cue.rawValue)", withExtension: $0) }
            .first
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        player.volume = 0.3
        players[cue] = player
        return player
    }

    /// Ramped rather than switched, because a music bed that appears is a
    /// worse surprise than one that was always there.
    private func fade(_ player: AVAudioPlayer, to target: Float, over seconds: TimeInterval, then finish: (() -> Void)? = nil) {
        player.setVolume(target, fadeDuration: seconds)
        guard let finish else { return }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            finish()
        }
    }
}

/// The one control the introduction offers, in the corner, from the first
/// frame.
struct SoundSwitch: View {
    @Bindable var audio: IntroAudio

    var body: some View {
        Button {
            audio.isOn.toggle()
        } label: {
            Image(systemName: audio.isOn ? "speaker.wave.2" : "speaker.slash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 30, height: 30)
                .background {
                    Circle().fill(.quaternary.opacity(0.35))
                }
        }
        .buttonStyle(.plain)
        .help(audio.isOn ? "Turn the sound off" : "Turn the sound on")
        .accessibilityLabel(audio.isOn ? "Sound on" : "Sound off")
    }
}
