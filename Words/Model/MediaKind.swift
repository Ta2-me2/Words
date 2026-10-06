import Foundation

/// What a file is, told from its first bytes.
///
/// A file's name is a claim; its first few bytes are a fact. Imported decks
/// have been seen with pictures called `photo.jpg!d`, and a player or an image
/// view handed the wrong type does nothing at all.
nonisolated enum MediaKind: String, Hashable, Sendable {
    case mp3, m4a, wav, ogg, jpeg, png, gif, webp, other

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .other: "bin"
        default: rawValue
        }
    }

    var isPicture: Bool { [.jpeg, .png, .gif, .webp].contains(self) }
    var isSound: Bool { [.mp3, .m4a, .wav, .ogg].contains(self) }

    static func sniff(_ data: Data) -> MediaKind? {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 4 else { return nil }
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + prefix.count && Array(bytes[offset ..< offset + prefix.count]) == prefix
        }

        if starts([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return .png }
        if starts([0x47, 0x49, 0x46, 0x38]) { return .gif }
        if starts([0x52, 0x49, 0x46, 0x46]), starts([0x57, 0x45, 0x42, 0x50], at: 8) { return .webp }
        if starts([0x52, 0x49, 0x46, 0x46]), starts([0x57, 0x41, 0x56, 0x45], at: 8) { return .wav }
        if starts([0x4F, 0x67, 0x67, 0x53]) { return .ogg }
        if starts([0x49, 0x44, 0x33]) || bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0 { return .mp3 }
        if starts([0x66, 0x74, 0x79, 0x70], at: 4) { return .m4a }
        return nil
    }

    init(fileName: String) {
        let ext = fileName.split(separator: ".").last.map { String($0).lowercased().prefix { $0.isLetter || $0.isNumber } } ?? ""
        switch ext {
        case "mp3": self = .mp3
        case "m4a", "mp4", "aac": self = .m4a
        case "wav": self = .wav
        case "ogg", "oga": self = .ogg
        case "jpg", "jpeg": self = .jpeg
        case "png": self = .png
        case "gif": self = .gif
        case "webp": self = .webp
        default: self = .other
        }
    }
}
