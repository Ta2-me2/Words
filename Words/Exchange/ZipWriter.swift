import Compression
import Foundation

/// Just enough of a zip writer to pack a deck.
///
/// The other half of `ZipArchive`, and written for the same reason: Foundation
/// has no zip API on the Mac, and a dependency to lay out three record types is
/// a dependency for a page of arithmetic.
///
/// Entries are written one after another as they are added, so the archive is
/// never held in memory as a whole — a library with four hundred photographs in
/// it is four hundred files read and let go of, not half a gigabyte.
nonisolated final class ZipWriter {

    /// One entry, remembered only so that the directory at the end can be
    /// written: zip repeats every header twice, and the second copy is what a
    /// reader actually looks at.
    private struct Written {
        var name: String
        var method: UInt16
        var crc: UInt32
        var compressedSize: Int
        var size: Int
        var offset: Int
        var modified: Date
    }

    private let handle: FileHandle
    private var written: [Written] = []
    private var offset = 0

    init(creating url: URL) throws {
        let manager = FileManager.default
        try? manager.removeItem(at: url)
        guard manager.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
    }

    /// Adds one entry.
    ///
    /// - Parameter deflate: whether to compress. Worth it for text, not for a
    ///   photograph or a recording, which arrive compressed already: deflating
    ///   a JPEG spends time to make it very slightly bigger.
    func add(_ name: String, data: Data, deflate: Bool = true, modified: Date = .now) throws {
        let crc = CRC32.of(data)
        var method: UInt16 = 0
        var payload = data

        if deflate, !data.isEmpty, let squeezed = Self.deflate(data), squeezed.count < data.count {
            method = 8
            payload = squeezed
        }

        let entry = Written(
            name: name,
            method: method,
            crc: crc,
            compressedSize: payload.count,
            size: data.count,
            offset: offset,
            modified: modified
        )

        var header = Data()
        header.append(uint32: 0x0403_4B50)
        header.append(uint16: 20)
        header.append(uint16: 0x0800)       // the name is UTF-8
        header.append(uint16: method)
        header.append(uint16: entry.modified.dosTime)
        header.append(uint16: entry.modified.dosDate)
        header.append(uint32: crc)
        header.append(uint32: UInt32(payload.count))
        header.append(uint32: UInt32(data.count))
        let nameBytes = Data(name.utf8)
        header.append(uint16: UInt16(nameBytes.count))
        header.append(uint16: 0)
        header.append(nameBytes)

        try handle.write(contentsOf: header)
        try handle.write(contentsOf: payload)
        offset += header.count + payload.count
        written.append(entry)
    }

    /// Adds a file from disk, read once and let go of.
    func add(_ name: String, contentsOf url: URL, deflate: Bool = false) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        try add(name, data: data, deflate: deflate, modified: modified)
    }

    /// Writes the central directory and closes the file. Nothing may be added
    /// after it.
    func finish() throws {
        var directory = Data()
        for entry in written {
            let nameBytes = Data(entry.name.utf8)
            directory.append(uint32: 0x0201_4B50)
            directory.append(uint16: 20)    // written by
            directory.append(uint16: 20)    // needed to read
            directory.append(uint16: 0x0800)
            directory.append(uint16: entry.method)
            directory.append(uint16: entry.modified.dosTime)
            directory.append(uint16: entry.modified.dosDate)
            directory.append(uint32: entry.crc)
            directory.append(uint32: UInt32(entry.compressedSize))
            directory.append(uint32: UInt32(entry.size))
            directory.append(uint16: UInt16(nameBytes.count))
            directory.append(uint16: 0)     // extra
            directory.append(uint16: 0)     // comment
            directory.append(uint16: 0)     // first disk
            directory.append(uint16: 0)     // internal attributes
            directory.append(uint32: 0)     // external attributes
            directory.append(uint32: UInt32(entry.offset))
            directory.append(nameBytes)
        }

        var end = Data()
        end.append(uint32: 0x0605_4B50)
        end.append(uint16: 0)
        end.append(uint16: 0)
        end.append(uint16: UInt16(written.count))
        end.append(uint16: UInt16(written.count))
        end.append(uint32: UInt32(directory.count))
        end.append(uint32: UInt32(offset))
        end.append(uint16: 0)

        try handle.write(contentsOf: directory)
        try handle.write(contentsOf: end)
        try handle.close()
    }

    /// Raw deflate, which is what zip's method 8 means and what
    /// `COMPRESSION_ZLIB` produces.
    private static func deflate(_ input: Data) -> Data? {
        // Deflate can grow incompressible input a little; the margin is for a
        // buffer, not for the result, which is discarded if it is not smaller.
        let capacity = input.count + input.count / 100 + 64
        var output = Data(count: capacity)
        let count = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard count > 0 else { return nil }
        output.removeSubrange(count...)
        return output
    }
}

/// The checksum zip puts on every entry, which a reader checks and refuses the
/// file without.
nonisolated enum CRC32 {

    private static let table: [UInt32] = (0 ..< 256).map { index in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func of(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    nonisolated mutating func append(uint16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8 & 0xFF))
    }

    nonisolated mutating func append(uint32 value: UInt32) {
        append(uint16: UInt16(value & 0xFFFF))
        append(uint16: UInt16(value >> 16 & 0xFFFF))
    }
}

private extension Date {
    /// MS-DOS time and date, which is what zip has carried since 1989: seconds
    /// in steps of two, and a year counted from 1980.
    nonisolated var dosTime: UInt16 {
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: self)
        let hour = UInt16(parts.hour ?? 0)
        let minute = UInt16(parts.minute ?? 0)
        let second = UInt16((parts.second ?? 0) / 2)
        return hour << 11 | minute << 5 | second
    }

    nonisolated var dosDate: UInt16 {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: self)
        let year = UInt16(max(0, (parts.year ?? 1980) - 1980))
        let month = UInt16(parts.month ?? 1)
        let day = UInt16(parts.day ?? 1)
        return year << 9 | month << 5 | day
    }
}
