import Foundation

/// A voice macOS can install but has not.
nonisolated struct DownloadableVoice: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var language: String
    var gender: String?
    var bytes: Int?

    /// "487 MB", or nothing when the catalogue does not say.
    var size: String? {
        guard let bytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// The voices a Mac could install, as the Mac itself lists them.
///
/// `AVSpeechSynthesisVoice.speechVoices()` returns what is installed and
/// nothing else, which leaves a learner guessing what a download would even
/// offer them. macOS does publish the answer — the asset catalogue its own
/// settings read — so this reads that rather than carrying a list of names that
/// would go stale with the next system update.
///
/// Everything here degrades to nothing: a catalogue that has moved, changed
/// shape or gone away leaves the list empty, and the interface simply says
/// less.
nonisolated enum VoiceCatalog {

    /// The system's catalogue of downloadable speech voices.
    static let systemCatalogue = URL(fileURLWithPath:
        "/System/Library/AssetsV2/com_apple_MobileAsset_VoiceServices_CombinedVocalizerVoices"
        + "/com_apple_MobileAsset_VoiceServices_CombinedVocalizerVoices.xml")

    /// Everything the catalogue lists for a language, by name.
    static func voices(for languageCode: String, in catalogue: URL = systemCatalogue) -> [DownloadableVoice] {
        all(in: catalogue)
            .filter { $0.language == languageCode || $0.language.hasPrefix("\(languageCode)-") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func all(in catalogue: URL = systemCatalogue) -> [DownloadableVoice] {
        if let cached = cache[catalogue] { return cached }
        let parsed = parse(catalogue)
        cache[catalogue] = parsed
        return parsed
    }

    /// Reading and parsing costs a few milliseconds; doing it once costs none.
    private nonisolated(unsafe) static var cache: [URL: [DownloadableVoice]] = [:]

    private static func parse(_ url: URL) -> [DownloadableVoice] {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any],
              let assets = root["Assets"] as? [[String: Any]]
        else { return [] }

        return assets.compactMap { asset in
            guard let name = asset["Name"] as? String,
                  let languages = asset["Languages"] as? [String],
                  let language = languages.first
            else { return nil }

            return DownloadableVoice(
                id: (asset["VoiceId"] as? String) ?? "\(name)-\(language)",
                name: name,
                language: language,
                gender: asset["Gender"] as? String,
                bytes: asset["_DownloadSize"] as? Int
            )
        }
    }
}
