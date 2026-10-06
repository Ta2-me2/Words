import AVFoundation
import SwiftUI

/// Choosing the voice that reads a language's words — and seeing which better
/// ones the Mac could still be asked for.
///
/// Two lists, because a learner cannot choose what they cannot see: the voices
/// that are here, and the voices macOS publishes as available. Words cannot
/// install one itself — no application can — so the second list leads to the
/// place that can.
struct VoiceSettings: View {
    let learningCode: String
    let sampleWord: String

    @Binding var voiceIdentifier: String?
    @Binding var speechRate: Double
    @Binding var speaksOnReveal: Bool
    @Binding var speaksExampleOnReveal: Bool

    private let speaker = Speaker.shared

    var body: some View {
        let installed = installed

        Section("Voice") {
            if installed.isEmpty {
                LabeledContent("Voice") {
                    Text(hasNoVoiceAtAll ? "None" : "None installed")
                        .foregroundStyle(Palette.secondaryText)
                }
            } else {
                Picker("Voice", selection: $voiceIdentifier) {
                    Text("Best available").tag(String?.none)

                    // Grouped by how good they sound, best first: the difference
                    // between a premium voice and a compact one is the
                    // difference between a word worth hearing and a word worth
                    // guessing at.
                    ForEach(Self.tiers, id: \.title) { tier in
                        let matching = installed.filter { $0.quality == tier.quality }
                        if !matching.isEmpty {
                            Section(tier.title) {
                                ForEach(matching, id: \.identifier) { voice in
                                    Text(label(for: voice)).tag(Optional(voice.identifier))
                                }
                            }
                        }
                    }
                }

                LabeledContent("Speed") {
                    HStack(spacing: 10) {
                        Slider(value: $speechRate, in: 0.3...0.6)
                            .frame(maxWidth: 160)

                        Button("Listen", systemImage: "play.circle") { preview() }
                            .buttonStyle(.borderless)
                            .labelStyle(.iconOnly)
                            .imageScale(.large)
                            .help("Hear “\(sampleWord)”")
                    }
                }

                Toggle("Speak the word when the answer is shown", isOn: $speaksOnReveal)
                // Its own sentence, not "too": either switch works without the
                // other, and the label has to say so.
                Toggle("Speak the example sentence when the answer is shown", isOn: $speaksExampleOnReveal)
            }
        }

        Section {
            if missing.isEmpty {
                // Not offered where there is nothing to go and find: System
                // Settings has no voice for Georgian either.
                if !hasNoVoiceAtAll {
                    Button("More Voices in System Settings…") { Speaker.openVoiceSettings() }
                        .buttonStyle(.link)
                }
            } else {
                ForEach(missing) { voice in
                    LabeledContent {
                        Button("Install…") { Speaker.openVoiceSettings() }
                            .buttonStyle(.link)
                    } label: {
                        HStack(spacing: 8) {
                            Text(voice.name)
                            if let size = voice.size {
                                Text(size)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.secondaryText)
                            }
                        }
                    }
                }
            }
        } header: {
            // Headed only where it leads somewhere. With no voice to be had it
            // is one sentence explaining the row above, not a section of its own.
            if !hasNoVoiceAtAll {
                Text(missing.isEmpty ? "More Voices" : "Available to Install")
            }
        } footer: {
            Text(footer)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - What there is

    private static let tiers: [(title: String, quality: AVSpeechSynthesisVoiceQuality)] = [
        ("Premium", .premium),
        ("Enhanced", .enhanced),
        ("Basic", .default)
    ]

    private var installed: [AVSpeechSynthesisVoice] {
        Speaker.voices(for: learningCode)
    }

    /// What the system's catalogue offers that is not already here.
    ///
    /// Matched by name and language rather than by identifier: an installed
    /// voice and its catalogue entry are the same voice under two different
    /// naming schemes, and the name is the part that does not change — except
    /// that macOS renames a downloaded voice "Petra (Premium)", so the name is
    /// compared without what is in brackets.
    private var missing: [DownloadableVoice] {
        let here = Set(installed.map { Self.baseName($0.name) })
        return VoiceCatalog.voices(for: learningCode).filter { !here.contains(Self.baseName($0.name)) }
    }

    private static func baseName(_ name: String) -> String {
        (name.split(separator: "(").first.map(String.init) ?? name)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    /// A language macOS has no voice for and never will offer one for.
    private var hasNoVoiceAtAll: Bool {
        installed.isEmpty && VoiceCatalog.voices(for: learningCode).isEmpty
    }

    private var footer: String {
        // Nothing installed and nothing to install is not "none installed": it
        // is a language macOS has no voice for at all, and saying so saves a
        // trip to System Settings to look for one that was never there.
        if hasNoVoiceAtAll {
            return "macOS has no voice for \(LanguageCatalog.name(for: learningCode)). Words are heard from your own recordings; write how one sounds under it and the card will show that instead."
        }

        let counted = Self.tiers.compactMap { tier -> String? in
            let count = installed.count { $0.quality == tier.quality }
            return count > 0 ? "\(count) \(tier.title.lowercased())" : nil
        }

        var sentence = counted.isEmpty
            ? "No voice for this language is installed."
            : "Installed: \(counted.joined(separator: ", "))."

        if !missing.isEmpty {
            sentence += " The rest are installed by macOS itself — System Settings ▸ Accessibility ▸ Spoken Content ▸ System Voice ▸ Manage Voices."
        }

        sentence += " Siri's own voices are not offered to applications."
        return sentence
    }

    /// "Anna — German (Germany)", with a word about quality when there is one
    /// worth having.
    private func label(for voice: AVSpeechSynthesisVoice) -> String {
        var text = voice.name
        if let region = Locale.current.localizedString(forIdentifier: voice.language) {
            text += " — \(region)"
        }
        return text
    }

    private func preview() {
        // A voice is judged on a word, not on a description of itself.
        let sample = LanguageProfile(
            name: "Preview",
            learningCode: learningCode,
            nativeCode: learningCode,
            voiceIdentifier: voiceIdentifier,
            speechRate: speechRate
        )
        speaker.speak(sampleWord, in: sample)
    }
}
