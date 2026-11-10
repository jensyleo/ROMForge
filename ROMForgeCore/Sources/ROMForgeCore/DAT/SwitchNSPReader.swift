// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Reads what a Nintendo Switch `.nsp` says about itself, from its unencrypted
/// PFS0 file table only — a few kilobytes, never the game data. The ticket
/// (`<title id><key generation>.tik`) names the title; the optional
/// `.cnmt.xml` also carries the version.
public enum SwitchNSPReader {
    public struct Info: Equatable, Sendable {
        public let titleID: String
        public let version: Int?
    }

    struct Entry: Equatable {
        let name: String
        let offset: UInt64
        let size: UInt64
    }

    private static let maxEntries = 4096
    private static let maxStringTable = 1 << 20
    private static let maxMetadataSize: UInt64 = 1 << 16

    public static func info(ofFileAt url: URL) -> Info? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 16), header.count == 16,
              let (count, stringTableSize) = parseHeader(header) else { return nil }
        let tableSize = 24 * count + stringTableSize
        guard let table = try? handle.read(upToCount: tableSize), table.count == tableSize,
              let entries = parseEntries(table, count: count, stringTableSize: stringTableSize) else { return nil }
        let dataStart = UInt64(16 + tableSize)

        var version: Int?
        var metadataTitleID: String?
        if let metadata = entries.first(where: { $0.name.lowercased().hasSuffix(".cnmt.xml") }), metadata.size <= maxMetadataSize,
           (try? handle.seek(toOffset: dataStart + metadata.offset)) != nil,
           let xml = try? handle.read(upToCount: Int(metadata.size)), let text = String(data: xml, encoding: .utf8) {
            metadataTitleID = firstMatch(in: text, pattern: #"<Id>0x([0-9A-Fa-f]{16})</Id>"#)?.uppercased()
            version = firstMatch(in: text, pattern: #"<Version>(\d+)</Version>"#).flatMap(Int.init)
        }
        guard let titleID = titleID(fromEntryNames: entries.map(\.name)) ?? metadataTitleID else { return nil }
        return Info(titleID: titleID, version: version)
    }

    /// `(entry count, string table size)` for a valid PFS0 header.
    static func parseHeader(_ header: Data) -> (Int, Int)? {
        guard header.count >= 16, header.prefix(4) == Data("PFS0".utf8) else { return nil }
        let count = Int(readUInt32(header, at: 4))
        let stringTableSize = Int(readUInt32(header, at: 8))
        guard count > 0, count <= maxEntries, stringTableSize > 0, stringTableSize <= maxStringTable else { return nil }
        return (count, stringTableSize)
    }

    static func parseEntries(_ table: Data, count: Int, stringTableSize: Int) -> [Entry]? {
        guard table.count >= 24 * count + stringTableSize else { return nil }
        let strings = table.subdata(in: table.startIndex + 24 * count..<table.startIndex + 24 * count + stringTableSize)
        var entries: [Entry] = []
        for index in 0..<count {
            let base = index * 24
            let nameOffset = Int(readUInt32(table, at: base + 16))
            guard nameOffset < strings.count else { return nil }
            let nameBytes = strings[strings.startIndex + nameOffset..<strings.endIndex].prefix { $0 != 0 }
            guard let name = String(data: Data(nameBytes), encoding: .utf8) else { return nil }
            entries.append(Entry(name: name, offset: readUInt64(table, at: base), size: readUInt64(table, at: base + 8)))
        }
        return entries
    }

    /// The ticket or certificate is named after the rights ID, whose first 16
    /// hex digits are the Title ID.
    static func titleID(fromEntryNames names: [String]) -> String? {
        for name in names {
            let lower = name.lowercased()
            guard lower.hasSuffix(".tik") || lower.hasSuffix(".cert") else { continue }
            let stem = lower.prefix { $0 != "." }
            guard stem.count == 32, stem.allSatisfy(\.isHexDigit), stem.hasPrefix("0100") else { continue }
            return String(stem.prefix(16)).uppercased()
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 { value |= UInt32(data[data.startIndex + offset + index]) << (8 * UInt32(index)) }
        return value
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 { value |= UInt64(data[data.startIndex + offset + index]) << (8 * UInt64(index)) }
        return value
    }
}
