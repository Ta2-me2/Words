import AVFoundation

@MainActor
final class GameAudio {
    private var voices: [String: AVAudioPlayer] = [:]
    private var slide: AVAudioPlayer?
    init() {
        let embedded = Bundle.main.resourceURL?.appendingPathComponent("WortfallKit_WortfallKit.bundle")
        let resources = embedded.flatMap { Bundle(url: $0) } ?? Bundle.module
        for name in ["correct", "heal", "bump", "finish", "slide"] {
            if let url = resources.url(forResource: name, withExtension: "wav"), let player = try? AVAudioPlayer(contentsOf: url) {
                player.prepareToPlay()
                if name == "slide" { player.numberOfLoops = -1; player.volume = 0; slide = player }
                else { player.volume = 0.3; voices[name] = player }
            }
        }
    }
    func play(_ name: String, enabled: Bool) {
        guard enabled, let player = voices[name] else { return }
        player.currentTime = 0; player.play()
    }
    func update(enabled: Bool, sliding: Bool, speed: Float) {
        guard enabled else { stop(); return }
        if sliding { if slide?.isPlaying != true { slide?.play() }; slide?.volume = 0.035 + (speed - 6) * 0.008 }
        else { slide?.pause() }
    }
    func stop() { slide?.stop(); for player in voices.values { player.stop() } }
}
