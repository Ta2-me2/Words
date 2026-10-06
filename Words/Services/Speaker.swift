import AppKit
import AVFoundation
import Observation

/// Saying a word out loud.
///
/// One object for both ways of doing it: a word with a recording is played, and
/// a word without one is read by the system voice chosen for its language. The
/// interface asks for a word to be spoken and never has to know which happened.
///
/// Nothing is generated and stored. A voice can be changed at any time, and a
/// library full of files made by last month's voice would be a library that had
/// quietly gone out of date.
@Observable
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {

    /// The one synthesiser the application speaks with.
    ///
    /// Reached directly rather than through the environment: there is only ever
    /// one, every view that wants it wants the same one, and an environment
    /// value that fails to reach a toolbar menu or a table cell is a crash
    /// rather than a missing feature.
    static let shared = Speaker()

    /// The word being spoken, so its button can show it.
    private(set) var speakingEntryID: UUID?

    /// Replaceable, because it is the part that can get stuck.
    ///
    /// `AVSpeechSynthesizer` is a long-lived object talking to a system daemon,
    /// and a long run of start-and-interrupt can leave it accepting utterances
    /// it never speaks. Nothing in an application can prevent that; what it can
    /// do is notice and start again.
    private var synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    /// Whether the utterance just handed over has actually begun.
    private var hasStarted = false
    private var watchdog: Task<Void, Never>?

    /// What is still to be said, in order.
    ///
    /// The synthesiser keeps a queue of its own, and handing it two utterances
    /// at once looks like the obvious way to say a word and then its example.
    /// It is not: a synthesiser that has just been interrupted will accept the
    /// first utterance and never speak it, while the second arrives seconds
    /// later as though nothing had happened — which is exactly what a learner
    /// moving quickly through cards hears. One utterance at a time, ordered
    /// here, is the only arrangement that can be relied on.
    private var queue: [Utterance] = []

    /// One thing to hear: words for the voice to read, or a recording to play.
    /// Both go through the same queue, so a word read aloud and an example
    /// played from a file follow each other the same way two readings do.
    private struct Utterance {
        enum Sound {
            case voice(String, LanguageProfile)
            case recording(URL)
        }

        var sound: Sound
        var entryID: UUID?
    }

    /// Where a word's files are. The library for words in it; the package for a
    /// deck that is still being looked at before it is imported.
    typealias MediaLocator = (String) -> URL?

    /// What was last asked for, and when.
    ///
    /// A good voice takes up to a second to open its mouth, and every request
    /// starts by stopping whatever came before. Without this, a learner who
    /// presses the button again because they have not heard anything yet
    /// silences the very word they are waiting for — twice as many presses,
    /// half as much sound.
    private var lastRequest: (key: Request, at: Date)?

    private enum Request: Hashable {
        case word(UUID)
        case example(UUID)
    }

    private static let startupGrace: TimeInterval = 1.5

    private var isBusy: Bool {
        synthesizer.isSpeaking || player?.isPlaying == true
    }

    /// Whether this request would only interrupt itself.
    private func isRepeat(of key: Request) -> Bool {
        guard isBusy, let last = lastRequest, last.key == key else { return false }
        return Date.now.timeIntervalSince(last.at) < Self.startupGrace
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - The voices a Mac has

    /// Asking the system for its voices costs 45–100 ms — it is a trip out of
    /// the process, not a lookup. A word list that asked once per row spent
    /// seconds on it, so the answer is kept until there is reason to think it
    /// changed.
    private static var installed: [AVSpeechSynthesisVoice]?
    private static var byLanguage: [String: [AVSpeechSynthesisVoice]] = [:]
    private static var chosen: [String: AVSpeechSynthesisVoice?] = [:]

    static func allVoices() -> [AVSpeechSynthesisVoice] {
        if let installed { return installed }
        let voices = AVSpeechSynthesisVoice.speechVoices()
        installed = voices
        return voices
    }

    /// Every voice installed for a language, best quality first.
    static func voices(for languageCode: String) -> [AVSpeechSynthesisVoice] {
        if let cached = byLanguage[languageCode] { return cached }

        let list = allVoices()
            .filter { $0.language == languageCode || $0.language.hasPrefix("\(languageCode)-") }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue {
                    return $0.quality.rawValue > $1.quality.rawValue
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }

        byLanguage[languageCode] = list
        return list
    }

    static func hasVoice(for languageCode: String) -> Bool {
        !voices(for: languageCode).isEmpty
    }

    /// The voice a profile speaks with: the one it chose, or the best the Mac
    /// has for that language.
    static func voice(for profile: LanguageProfile) -> AVSpeechSynthesisVoice? {
        let key = profile.voiceIdentifier ?? "best:\(profile.learningCode)"
        if let cached = chosen[key] { return cached }

        let voice: AVSpeechSynthesisVoice?
        if let identifier = profile.voiceIdentifier {
            voice = allVoices().first { $0.identifier == identifier }
                ?? AVSpeechSynthesisVoice(identifier: identifier)
        } else {
            voice = voices(for: profile.learningCode).first
        }

        chosen[key] = voice
        return voice
    }

    /// Forgets what the Mac had, so a voice installed since is found.
    ///
    /// Called when the voice settings are opened — which is where a learner who
    /// has just been to System Settings arrives, and the one place where the
    /// list is worth the 50 ms it costs to ask for.
    static func refreshVoices() {
        installed = nil
        byLanguage = [:]
        chosen = [:]
    }

    /// Pays the price once, after the window is up, rather than during the
    /// first screen that asks.
    static func warmUp() {
        Task { @MainActor in _ = allVoices() }
    }

    /// Where the Mac keeps its voices, for the times there are none worth using.
    static func openVoiceSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent",
            "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent",
            "x-apple.systempreferences:com.apple.preference.universalaccess"
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - Speaking

    /// Speaks a word the best way it can be spoken.
    ///
    /// The article goes with it: "die Mutter" is the thing being learned, and a
    /// voice that says only "Mutter" leaves out the half that is hard.
    func speak(_ entry: Entry, in profile: LanguageProfile, store: LibraryStore, thenExample: Bool = false) {
        speak(entry, in: profile, media: { store.mediaURL(for: $0) }, thenExample: thenExample)
    }

    func speak(_ entry: Entry, in profile: LanguageProfile, media: MediaLocator, thenExample: Bool = false) {
        guard !isRepeat(of: .word(entry.id)) else { return }

        stop()
        lastRequest = (.word(entry.id), .now)

        queue = [wordSound(entry, in: profile, media: media)].compactMap { $0 }
        if thenExample, let example = exampleSound(entry, in: profile, media: media) {
            queue.append(example)
        }
        startNext()
    }

    /// The example sentence on its own: its recording if it has one, the voice
    /// if it has not.
    func speakExample(_ entry: Entry, in profile: LanguageProfile, store: LibraryStore) {
        speakExample(entry, in: profile, media: { store.mediaURL(for: $0) })
    }

    func speakExample(_ entry: Entry, in profile: LanguageProfile, media: MediaLocator) {
        guard !isRepeat(of: .example(entry.id)), let sound = exampleSound(entry, in: profile, media: media) else { return }

        stop()
        lastRequest = (.example(entry.id), .now)
        queue = [sound]
        startNext()
    }

    private func wordSound(_ entry: Entry, in profile: LanguageProfile, media: MediaLocator) -> Utterance? {
        if let clip = entry.audio, let url = media(clip.file) {
            return Utterance(sound: .recording(url), entryID: entry.id)
        }
        return Utterance(sound: .voice(entry.displayTerm(in: profile), profile), entryID: entry.id)
    }

    private func exampleSound(_ entry: Entry, in profile: LanguageProfile, media: MediaLocator) -> Utterance? {
        if let clip = entry.exampleAudio, let url = media(clip.file) {
            return Utterance(sound: .recording(url), entryID: entry.id)
        }
        let example = entry.example.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !example.isEmpty else { return nil }
        return Utterance(sound: .voice(example, profile), entryID: entry.id)
    }

    /// Reads text with a profile's voice. Used by the preview button beside the
    /// voice picker, and by anything else with something to say and no word to
    /// say it about.
    func speak(_ text: String, in profile: LanguageProfile, entryID: UUID? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()
        queue = [Utterance(sound: .voice(trimmed, profile), entryID: entryID)]
        startNext()
    }

    /// Hands the next utterance over, and nothing else until it is done.
    private func startNext(isRetry: Bool = false) {
        guard !queue.isEmpty else {
            speakingEntryID = nil
            return
        }

        let item = queue.removeFirst()

        let text: String
        let profile: LanguageProfile
        switch item.sound {
        case .recording(let url):
            // A recording that will not open is skipped rather than allowed to
            // stall whatever was queued behind it.
            if !play(url, entryID: item.entryID) { startNext() }
            return
        case .voice(let words, let owner):
            text = words
            profile = owner
        }

        guard let voice = Self.voice(for: profile) else {
            // No voice for this language: skip it rather than stall the rest.
            startNext()
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Float(profile.speechRate)
        // A single word read at full tilt is a noise; a beat either side of it
        // is the difference between hearing it and catching it.
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.1

        speakingEntryID = item.entryID
        hasStarted = false
        synthesizer.speak(utterance)
        watchForStart(item, isRetry: isRetry)
    }

    /// A synthesiser that has taken an utterance and said nothing for two
    /// seconds is not thinking, it is stuck: it is replaced and asked again,
    /// once. Twice would be a loop, and a loop is worse than silence.
    private func watchForStart(_ item: Utterance, isRetry: Bool) {
        watchdog?.cancel()
        watchdog = nil
        guard !isRetry else { return }

        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, !self.hasStarted else { return }

            self.renewSynthesizer()
            self.queue.insert(item, at: 0)
            self.startNext(isRetry: true)
        }
    }

    private func renewSynthesizer() {
        synthesizer.delegate = nil
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
    }

    @discardableResult
    func play(_ url: URL, entryID: UUID? = nil) -> Bool {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            self.player = player
            speakingEntryID = entryID
            return player.play()
        } catch {
            // A recording that will not open is not worth an alert in the
            // middle of a review; the button simply does nothing.
            speakingEntryID = nil
            return false
        }
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        queue = []
        lastRequest = nil

        // A synthesiser interrupted mid-word is replaced rather than told to
        // stop and then reused. Asking one to speak while it is still tearing
        // down the utterance it was told to abandon is how a word goes missing:
        // the request is accepted and never heard. A new one has nothing to
        // tear down.
        if synthesizer.isSpeaking { renewSynthesizer() }

        player?.stop()
        player = nil
        speakingEntryID = nil
    }

    // MARK: - Finishing

    private func finished() {
        watchdog?.cancel()
        watchdog = nil
        startNext()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.hasStarted = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finished() }
    }
}
