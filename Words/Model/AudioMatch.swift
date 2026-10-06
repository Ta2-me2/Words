import Foundation

/// One audio file lined up against the word it belongs to.
nonisolated struct AudioMatch: Identifiable, Hashable, Sendable {
    var id = UUID()
    var filename: String
    var entryID: UUID
    var term: String
    /// Whether the word already has a clip that this one would replace.
    var replacesExisting: Bool
}

/// What matching a folder of recordings against a vocabulary would do.
nonisolated struct AudioMatchPlan: Hashable, Sendable {
    var matches: [AudioMatch] = []
    var unmatched: [String] = []

    var isEmpty: Bool { matches.isEmpty && unmatched.isEmpty }
}

/// Lining up a pile of audio files with the words they were recorded for.
///
/// By filename, because that is what people actually have: a folder of
/// `Mutter.m4a`, `der Berg.mp3`, `Straße.wav`. No manifest, no naming rules to
/// read first — and anything that does not line up is reported rather than
/// guessed at.
nonisolated enum AudioMatcher {

    static func plan(filenames: [String], entries: [Entry], language: String) -> AudioMatchPlan {
        var byKey: [String: Entry] = [:]
        for entry in entries {
            byKey[key(entry.term)] = entry
        }

        var plan = AudioMatchPlan()

        for filename in filenames {
            let stem = (filename as NSString).deletingPathExtension
            // A file named the way the word is written down, article and all.
            let (bare, _) = LanguageGenders.split(term: stem, language: language)

            if let entry = byKey[key(stem)] ?? byKey[key(bare)] {
                plan.matches.append(
                    AudioMatch(
                        filename: filename,
                        entryID: entry.id,
                        term: entry.term,
                        replacesExisting: entry.audio != nil
                    )
                )
            } else {
                plan.unmatched.append(filename)
            }
        }

        return plan
    }

    /// Words are the same word whatever the case, and whatever a file system
    /// did to the accents on the way.
    static func key(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
