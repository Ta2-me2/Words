import SwiftUI
import UniformTypeIdentifiers

/// The audio a word has, and the two ways of giving it some.
///
/// Recording is one button: press, say the word, press again. Nothing is kept
/// until it is recorded, and what was there before is only replaced once the
/// new file is safely in the library.
struct AudioEditor: View {
    let entry: Entry
    let profile: LanguageProfile

    @Environment(LibraryStore.self) private var store
    private let speaker = Speaker.shared
    private let recorder = Recorder.shared

    @State private var isChoosingFile = false
    @State private var isMicrophoneDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            current
            controls
        }
        .fileImporter(
            isPresented: $isChoosingFile,
            allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio, .aiff],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            attach(url, kind: .imported)
        }
        .alert("Words cannot hear the microphone", isPresented: $isMicrophoneDenied) {
            Button("Open System Settings…") { openMicrophoneSettings() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Give Words access to the microphone in Privacy & Security to record a word in your own voice.")
        }
    }

    // MARK: - What it has now

    @ViewBuilder
    private var current: some View {
        HStack(spacing: 10) {
            if let clip = entry.audio {
                Button("Play", systemImage: isSpeaking ? "speaker.wave.2.fill" : "play.circle") {
                    speaker.speak(entry, in: profile, store: store)
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .imageScale(.large)

                Text(description(of: clip))
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)

                Spacer(minLength: 0)

                Button("Remove") { store.removeAudio(from: entry.id) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.secondaryText)

            } else if Speaker.voice(for: profile) != nil {
                Button("Listen", systemImage: isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2") {
                    speaker.speak(entry, in: profile, store: store)
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .imageScale(.large)

                Text("Read by \(Speaker.voice(for: profile)?.name ?? "the system voice")")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)

                Spacer(minLength: 0)

            } else {
                // Two different facts, and telling them apart is the difference
                // between "go and install one" and "record it yourself":
                // macOS has no voice for Georgian and never offers one.
                Text(VoiceCatalog.voices(for: profile.learningCode).isEmpty
                     ? "macOS has no voice for \(LanguageCatalog.name(for: profile.learningCode)). Record the word, or write how it sounds under it."
                     : "No voice installed for \(LanguageCatalog.name(for: profile.learningCode)).")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
    }

    private var isSpeaking: Bool { speaker.speakingEntryID == entry.id }

    private func description(of clip: AudioClip) -> String {
        var parts = [clip.source.title]
        if let seconds = clip.seconds, seconds > 0 {
            parts.append(String(format: "%.1f s", seconds))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Giving it some

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                toggleRecording()
            } label: {
                Label(
                    recorder.isRecording ? "Stop" : (entry.audio == nil ? "Record" : "Record Again"),
                    systemImage: recorder.isRecording ? "stop.fill" : "mic"
                )
            }
            .buttonStyle(.bordered)

            if recorder.isRecording {
                // Red is the one thing on this screen that means "now": the
                // microphone is open and it is being written down.
                Circle()
                    .fill(Palette.critical)
                    .frame(width: 7, height: 7)

                Text(String(format: "%.1f s", recorder.seconds))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)

                Capsule()
                    .fill(Palette.subtleFill)
                    .frame(width: 54, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Palette.secondaryText)
                            .frame(width: 54 * recorder.level, height: 4)
                    }
                    .animation(.easeOut(duration: 0.08), value: recorder.level)
            }

            Spacer(minLength: 0)

            Button("Choose File…") { isChoosingFile = true }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            guard let result = recorder.stop() else { return }
            attach(result.url, kind: .recorded, seconds: result.seconds, thenRemoveSource: true)
        } else {
            Task {
                guard await recorder.requestAccess() else {
                    isMicrophoneDenied = true
                    return
                }
                speaker.stop()
                _ = recorder.start(to: store.scratchURL())
            }
        }
    }

    private func attach(_ url: URL, kind: AudioClip.Source, seconds: Double? = nil, thenRemoveSource: Bool = false) {
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            await store.attachAudio(from: url, to: entry.id, kind: kind, seconds: seconds)
            if thenRemoveSource { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}
