import Foundation

/// What is written inside a package: the whole of what was exported, in the
/// app's own shapes.
///
/// The words, decks and languages are encoded as the library encodes them, so
/// nothing is lost in translation and nothing has to be kept in step by hand.
/// `format` is the promise: a reader checks it, and a package from a later
/// version says so rather than being read wrongly.
nonisolated struct PackageManifest: Codable, Sendable {

    var format: Int
    var createdAt: Date

    /// "Words 1.0.0" — for the person reading the file, and for a bug report.
    var createdBy: String

    /// Whether the cards carry a schedule and the reviews behind it.
    var includesProgress: Bool

    var profiles: [LanguageProfile]
    var decks: [Deck]
    var entries: [Entry]
    var reviews: [ReviewRecord]

    init(
        format: Int = WordsPackage.currentFormat,
        createdAt: Date = .now,
        createdBy: String,
        includesProgress: Bool,
        profiles: [LanguageProfile],
        decks: [Deck],
        entries: [Entry],
        reviews: [ReviewRecord] = []
    ) {
        self.format = format
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.includesProgress = includesProgress
        self.profiles = profiles
        self.decks = decks
        self.entries = entries
        self.reviews = reviews
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(Int.self, forKey: .format)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy) ?? "Words"
        includesProgress = try container.decodeIfPresent(Bool.self, forKey: .includesProgress) ?? false
        profiles = try container.decodeIfPresent([LanguageProfile].self, forKey: .profiles) ?? []
        decks = try container.decodeIfPresent([Deck].self, forKey: .decks) ?? []
        entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        reviews = try container.decodeIfPresent([ReviewRecord].self, forKey: .reviews) ?? []
    }
}

/// A `.wordspack`: a zip holding one JSON file and the media the words own.
///
/// A plain zip with readable names on purpose. A learner who has put a year
/// into a library should be able to open the file they exported, see their
/// words in a text editor and their photographs in a folder, and not have to
/// take this app's word for what is in there.
///
/// ```
/// words.json      every language, deck and word that was exported
/// Media/          the photographs, recordings and drawings they point at
/// README.txt      what this file is, for whoever opens it without the app
/// ```
nonisolated struct WordsPackage: Sendable {

    static let currentFormat = 1
    static let fileExtension = "wordspack"
    static let manifestName = "words.json"
    static let mediaFolder = "Media"
    static let readmeName = "README.txt"

    nonisolated enum Failure: LocalizedError {
        case notAPackage
        case tooNew(Int)
        case damaged(String)

        var errorDescription: String? {
            switch self {
            case .notAPackage:
                "This is not a Words package."
            case .tooNew(let format):
                "This package was written by a newer version of Words (format \(format)). Update Words to open it."
            case .damaged(let what):
                "The package is damaged: \(what)."
            }
        }
    }

    let manifest: PackageManifest
    private let archive: ZipArchive

    // MARK: - Writing

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Writes a package.
    ///
    /// - Parameters:
    ///   - mediaURL: where a file named in the library actually sits.
    ///   - progress: how far along, from nought to one, as each file goes in.
    /// A file that cannot be read is left out rather than failing the export:
    /// a missing photograph is not a reason to lose a thousand words.
    @discardableResult
    static func write(
        _ plan: ExportPlan,
        to url: URL,
        appVersion: String,
        mediaURL: (String) -> URL,
        progress: (Double) -> Void = { _ in }
    ) throws -> [String] {
        let manifest = PackageManifest(
            createdBy: appVersion,
            includesProgress: plan.includesProgress,
            profiles: plan.profiles,
            decks: plan.decks,
            entries: plan.entries,
            reviews: plan.reviews
        )

        let writer = try ZipWriter(creating: url)
        try writer.add(manifestName, data: try encoder.encode(manifest))
        try writer.add(readmeName, data: Data(readme(for: plan).utf8))

        var missing: [String] = []
        let total = max(1, plan.mediaFiles.count)
        for (index, file) in plan.mediaFiles.enumerated() {
            // Media is already compressed — a JPEG or an m4a deflates to very
            // slightly more than it started as — so it goes in as it is.
            do {
                try writer.add(file, contentsOf: mediaURL(file), deflate: false)
            } catch {
                missing.append(file)
            }
            progress(Double(index + 1) / Double(total))
        }

        try writer.finish()
        return missing
    }

    private static func readme(for plan: ExportPlan) -> String {
        var lines: [String] = []
        lines.append("This is a Words package.")
        lines.append("")
        lines.append("It holds \(plan.wordCount) \(plan.wordCount == 1 ? "word" : "words")"
            + " in \(plan.profiles.count) \(plan.profiles.count == 1 ? "language" : "languages")"
            + ", and \(plan.mediaFiles.count) media \(plan.mediaFiles.count == 1 ? "file" : "files").")
        lines.append("")
        lines.append("To use it: open Words, go to Add Words, choose From Words, and open this file.")
        lines.append("")
        lines.append("To read it without Words: it is an ordinary zip archive.")
        lines.append("  \(manifestName)  every language, deck and word, as JSON")
        lines.append("  \(mediaFolder)/      the photographs, recordings and drawings they point at")
        lines.append("")
        lines.append("Words — https://github.com/Ta2-me2/Words")
        return lines.joined(separator: "\n")
    }

    // MARK: - Reading

    init(reading url: URL) throws {
        let archive: ZipArchive
        do {
            archive = try ZipArchive(url: url)
        } catch {
            throw Failure.notAPackage
        }
        try self.init(archive: archive)
    }

    init(archive: ZipArchive) throws {
        guard archive.contains(Self.manifestName) else { throw Failure.notAPackage }
        let data: Data
        do {
            data = try archive.read(Self.manifestName)
        } catch {
            throw Failure.damaged("\(Self.manifestName) could not be read")
        }

        let manifest: PackageManifest
        do {
            manifest = try Self.decoder.decode(PackageManifest.self, from: data)
        } catch {
            throw Failure.damaged("\(Self.manifestName) is not readable")
        }
        guard manifest.format <= Self.currentFormat else { throw Failure.tooNew(manifest.format) }

        self.archive = archive
        self.manifest = manifest
    }

    /// One media file out of the package, or `nil` if it is not in there.
    func media(_ path: String) -> Data? {
        guard archive.contains(path) else { return nil }
        return try? archive.read(path)
    }

    /// Which of the files the words point at are actually in the package.
    var mediaFiles: Set<String> {
        Set(manifest.entries.flatMap(\.mediaFiles).filter { archive.contains($0) })
    }
}
