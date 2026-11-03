// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import ZIPFoundation

/// The plain-text part of a Nintendo 3DS cartridge dump (`.3ds`/`.cci`): its
/// product code ("CTR-P-ASVP"), the full image size the cartridge declares,
/// and whether the main partition is encrypted. All of it sits in headers that
/// are readable without any key, so reading it never touches the content.
public struct NintendoCTRHeader: Equatable, Sendable {
    public let productCode: String
    /// Size of the complete cartridge image; a trimmed dump file is smaller.
    public let imageSize: Int64
    public let state: ContentState

    /// What the dump really contains versus what its header declares. Emulators
    /// trust the header flag, so a decrypted dump whose flag was never set is
    /// rejected exactly like an encrypted one.
    public enum ContentState: String, Codable, Sendable {
        /// The partition's content is still ciphertext.
        case encrypted
        /// Plain content, and the header says so.
        case decrypted
        /// Plain content, but the header does not say so.
        case decryptedFlagMissing
    }

    public var isEncrypted: Bool { state == .encrypted }
    /// `true` when an emulator that trusts the header will refuse the file.
    public var isRejectedByEmulators: Bool { state != .decrypted }

    private static let mediaUnit = 0x200

    /// `exeFSStart`/`romFSStart` are the first bytes of the partition's ExeFS and RomFS,
    /// read only when the header does not already declare the content decrypted.
    public static func parse(_ data: Data, exeFSStart: Data? = nil, romFSStart: Data? = nil) -> NintendoCTRHeader? {
        func u32(_ offset: Int) -> Int? {
            guard data.count >= offset + 4 else { return nil }
            let base = data.startIndex + offset
            return Int(data[base]) | Int(data[base + 1]) << 8 | Int(data[base + 2]) << 16 | Int(data[base + 3]) << 24
        }
        guard data.count >= 0x200, data[data.startIndex + 0x100 ..< data.startIndex + 0x104].elementsEqual("NCSD".utf8),
              let imageUnits = u32(0x104), let partitionUnits = u32(0x120) else { return nil }
        let ncch = partitionUnits * mediaUnit
        guard ncch >= 0x200, data.count >= ncch + 0x190,
              data[data.startIndex + ncch + 0x100 ..< data.startIndex + ncch + 0x104].elementsEqual("NCCH".utf8) else { return nil }
        let codeBytes = data[data.startIndex + ncch + 0x150 ..< data.startIndex + ncch + 0x160].prefix { $0 != 0 }
        guard let code = String(bytes: codeBytes, encoding: .ascii), code.hasPrefix("CTR-") else { return nil }
        let flags7 = data[data.startIndex + ncch + 0x188 + 7]
        let state: ContentState
        if flags7 & 0x04 != 0 {
            state = .decrypted
        } else if let exeFSStart, exeFSStart.starts(with: ".code".utf8), romFSStart.map({ $0.starts(with: "IVFC".utf8) }) ?? true {
            state = .decryptedFlagMissing
        } else {
            state = .encrypted
        }
        return NintendoCTRHeader(productCode: code, imageSize: Int64(imageUnits) * Int64(mediaUnit), state: state)
    }

    public static func read(url: URL) -> NintendoCTRHeader? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 0x200), head.count == 0x200,
              head[head.startIndex + 0x100 ..< head.startIndex + 0x104].elementsEqual("NCSD".utf8) else { return nil }
        let base = head.startIndex + 0x120
        let units = Int(head[base]) | Int(head[base + 1]) << 8 | Int(head[base + 2]) << 16 | Int(head[base + 3]) << 24
        let ncch = units * mediaUnit
        // The first partition normally sits at 0x4000; anything absurd is not a cartridge image.
        guard ncch >= 0x200, ncch <= 0x100000 else { return nil }
        guard (try? handle.seek(toOffset: UInt64(ncch))) != nil, let part = try? handle.read(upToCount: 0x200), part.count == 0x200 else { return nil }
        var data = head
        data.append(Data(count: ncch - 0x200))
        data.append(part)
        guard let parsed = parse(data), parsed.state == .encrypted else { return parse(data) }
        // The flag is not set: look at the content itself.
        func word(_ offset: Int) -> Int {
            let b = part.startIndex + offset
            return Int(part[b]) | Int(part[b + 1]) << 8 | Int(part[b + 2]) << 16 | Int(part[b + 3]) << 24
        }
        func probe(unitsAt offset: Int, count: Int) -> Data? {
            let start = UInt64(ncch + word(offset) * mediaUnit)
            guard word(offset) > 0, (try? handle.seek(toOffset: start)) != nil else { return nil }
            return try? handle.read(upToCount: count)
        }
        return parse(data, exeFSStart: probe(unitsAt: 0x1A0, count: 8), romFSStart: probe(unitsAt: 0x1B0, count: 4))
    }

    /// Bytes read from a zip entry: the headers and the start of ExeFS all sit well inside 1 MiB.
    private static let archivePrefixBytes = 1 << 20

    /// A dump loose on disk, or one entry of a `.zip`.
    public static func read(url: URL, entryName: String?) -> NintendoCTRHeader? {
        guard url.pathExtension.lowercased() == "zip" else { return read(url: url) }
        guard let entryName, let prefix = try? ROMPrefixReader.read(url: url, entryName: entryName, maxBytes: archivePrefixBytes) else { return nil }
        return parse(prefix: prefix)
    }

    /// The first cartridge dump inside a `.zip`, if it holds one.
    public static func readFirstCartridge(inZip url: URL) -> NintendoCTRHeader? {
        guard let archive = try? Archive(url: url, accessMode: .read),
              let entry = archive.first(where: { isCartridgeDump(URL(fileURLWithPath: $0.path)) }) else { return nil }
        return read(url: url, entryName: entry.path)
    }

    static func parse(prefix: Data) -> NintendoCTRHeader? {
        guard let flagOnly = parse(prefix), flagOnly.state == .encrypted else { return parse(prefix) }
        func word(_ offset: Int) -> Int? {
            guard prefix.count >= offset + 4 else { return nil }
            let b = prefix.startIndex + offset
            return Int(prefix[b]) | Int(prefix[b + 1]) << 8 | Int(prefix[b + 2]) << 16 | Int(prefix[b + 3]) << 24
        }
        guard let units = word(0x120) else { return flagOnly }
        let ncch = units * mediaUnit
        guard let exeFSUnits = word(ncch + 0x1A0), exeFSUnits > 0 else { return flagOnly }
        let exeFS = ncch + exeFSUnits * mediaUnit
        guard prefix.count >= exeFS + 8 else { return flagOnly }
        let exeFSStart = prefix[(prefix.startIndex + exeFS)..<(prefix.startIndex + exeFS + 8)]
        return parse(prefix, exeFSStart: Data(exeFSStart), romFSStart: nil)
    }

    public static func isCartridgeDump(_ url: URL) -> Bool {
        ["3ds", "cci"].contains(url.pathExtension.lowercased())
    }
}
