import AVFoundation
import Observation

/// Recording a word in the learner's own voice.
///
/// The shortest possible path: press, say the word, press again. What comes out
/// is an m4a in a temporary file, which the library takes a copy of only if the
/// recording is kept.
@Observable
@MainActor
final class Recorder: NSObject, AVAudioRecorderDelegate {

    /// The one microphone. Reached directly, for the same reason as `Speaker`.
    static let shared = Recorder()

    private(set) var isRecording = false

    /// How long the current recording has been going, for the button to show.
    private(set) var seconds: Double = 0

    /// Loudness from 0 to 1, so the button can show that the microphone is
    /// hearing something. A recording with no meter is a recording nobody
    /// trusts until they play it back.
    private(set) var level: Double = 0

    private var recorder: AVAudioRecorder?
    private var meter: Task<Void, Never>?
    private var startedAt = Date.now

    /// A word is a word; anything longer is a mistake nobody meant to keep.
    private let limit: Double = 20

    /// Asks the Mac for the microphone, once, the first time it is needed.
    func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    var isDenied: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .denied
    }

    @discardableResult
    func start(to url: URL) -> Bool {
        stopEverything()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else { return false }

            self.recorder = recorder
            isRecording = true
            startedAt = .now
            seconds = 0
            level = 0
            startMetering()
            return true
        } catch {
            return false
        }
    }

    /// Stops and hands back what was recorded, or `nil` if it was too short to
    /// be a word.
    @discardableResult
    func stop() -> (url: URL, seconds: Double)? {
        guard let recorder, isRecording else { return nil }
        let url = recorder.url
        let length = Date.now.timeIntervalSince(startedAt)
        stopEverything()
        guard length >= 0.25 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (url, length)
    }

    func cancel() {
        guard let recorder else { return }
        let url = recorder.url
        stopEverything()
        try? FileManager.default.removeItem(at: url)
    }

    private func stopEverything() {
        meter?.cancel()
        meter = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        level = 0
    }

    private func startMetering() {
        meter = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                guard let self, let recorder = self.recorder, self.isRecording else { return }

                recorder.updateMeters()
                // Decibels are logarithmic and mostly silence; the useful part
                // of the scale is the top 50 of them.
                let power = Double(recorder.averagePower(forChannel: 0))
                self.level = max(0, min(1, (power + 50) / 50))
                self.seconds = Date.now.timeIntervalSince(self.startedAt)

                if self.seconds >= self.limit { _ = self.stop() }
            }
        }
    }
}
