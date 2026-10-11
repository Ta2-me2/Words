import Compression
import Foundation

/// Just enough of a zip reader to open an Anki package.
///
/// Foundation has no zip API on the Mac, and bringing in a library to read two
/// kinds of entry would be a dependency for a page of code. Anki packages hold
/// entries that are either stored as they are (the media) or deflated (the
/// database), and the system's Compression framework already decodes deflate.
/// Anything else — encryption, zip64, the other compression methods — is
/// refused with a reason rather than read wrongly.
nonisolated struct ZipArchive: Sendable {

    nonisolated struct Entry: Hashable, Sendable {
        var name: String
        var method: UInt16
        var compressedSize: Int
        var size: Int
        var localHeaderOffset: Int
    }

    nonisolated enum Failure: LocalizedError {
        case notAZip
        case unsupported(String)
        case damaged(String)

        var errorDescription: String? {
            switch self {
            case .notAZip: "This is not an Anki package — it is not a zip archive."
            case .unsupported(let what): "The package uses \(what), which Words cannot read."
            case .damaged(let what): "The package is damaged: \(what)."
            }
        }
    }

    private let data: Data
    let entries: [String: Entry]

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readDirectory(data)
    }

    var names: [String] { Array(entries.keys) }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    /// The bytes of one entry, uncompressed.
    func read(_ name: String) throws -> Data {
        guard let entry = entries[name] else { throw Failure.damaged("\(name) is missing") }

        // The local header repeats the name and may carry its own extra field,
        // so the data starts wherever that header says it does.
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, data.uint32(at: header) == 0x0403_4B50 else {
            throw Failure.damaged("the header of \(name) is not where the directory says")
        }
        let start = header + 30 + Int(data.uint16(at: header + 26)) + Int(data.uint16(at: header + 28))
        guard start + entry.compressedSize <= data.count else {
            throw Failure.damaged("\(name) runs past the end of the file")
        }
        let slice = data.subdata(in: start ..< start + entry.compressedSize)

        switch entry.method {
        case 0:
            return slice
        case 8:
            return try Self.inflate(slice, size: entry.size)
        default:
            throw Failure.unsupported("compression method \(entry.method)")
        }
    }

    // MARK: - The directory

    private static func readDirectory(_ data: Data) throws -> [String: Entry] {
        // The end-of-directory record sits in the last 22 bytes plus however
        // long a comment the writer left, which is at most 65 535 bytes.
        guard data.count >= 22 else { throw Failure.notAZip }
        let floor = max(0, data.count - 22 - 65_535)
        var end = -1
        var position = data.count - 22
        while position >= floor {
            if data.uint32(at: position) == 0x0605_4B50 { end = position; break }
            position -= 1
        }
        guard end >= 0 else { throw Failure.notAZip }

        let count = Int(data.uint16(at: end + 10))
        let directorySize = Int(data.uint32(at: end + 12))
        let directoryOffset = Int(data.uint32(at: end + 16))
        guard directoryOffset != 0xFFFF_FFFF, count != 0xFFFF else { throw Failure.unsupported("zip64") }
        guard directoryOffset + directorySize <= data.count else { throw Failure.damaged("the directory is truncated") }

        var entries: [String: Entry] = [:]
        var cursor = directoryOffset
        for _ in 0 ..< count {
            guard cursor + 46 <= data.count, data.uint32(at: cursor) == 0x0201_4B50 else {
                throw Failure.damaged("an entry in the directory is unreadable")
            }
            let flags = data.uint16(at: cursor + 8)
            let method = data.uint16(at: cursor + 10)
            let compressed = Int(data.uint32(at: cursor + 20))
            let size = Int(data.uint32(at: cursor + 24))
            let nameLength = Int(data.uint16(at: cursor + 28))
            let extraLength = Int(data.uint16(at: cursor + 30))
            let commentLength = Int(data.uint16(at: cursor + 32))
            let offset = Int(data.uint32(at: cursor + 42))

            guard flags & 0x1 == 0 else { throw Failure.unsupported("encryption") }
            guard cursor + 46 + nameLength <= data.count else { throw Failure.damaged("a name is truncated") }

            let nameBytes = data.subdata(in: cursor + 46 ..< cursor + 46 + nameLength)
            let name = String(decoding: nameBytes, as: UTF8.self)
            entries[name] = Entry(name: name, method: method, compressedSize: compressed, size: size, localHeaderOffset: offset)

            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// Raw deflate, which is what zip stores and what `COMPRESSION_ZLIB` means.
    private static func inflate(_ input: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, size,
                    source.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { throw Failure.damaged("an entry did not decompress to its stated size") }
        return output
    }
}

private extension Data {
    nonisolated func uint16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    nonisolated func uint32(at offset: Int) -> UInt32 {
        UInt32(uint16(at: offset)) | UInt32(uint16(at: offset + 2)) << 16
    }
}
