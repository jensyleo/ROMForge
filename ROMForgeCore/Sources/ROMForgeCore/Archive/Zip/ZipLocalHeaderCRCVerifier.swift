// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public enum ZipLocalHeaderCRCVerifierError: Error, Equatable {
    case cannotReadArchive(URL)
    case malformedArchive(URL)
}

/// One entry's central-directory CRC32 cross-checked against its own
/// local-header CRC32.
public struct ZipEntryCRCConsistency: Equatable, Sendable {
    public let entryName: String
    /// `false` when the two copies genuinely disagree; `nil` when this
    /// entry couldn't be checked at all (streamed/data-descriptor writing —
    /// see `dataDescriptorFlag`'s own doc comment), never a false mismatch.
    public let matches: Bool?
}

/// A ZIP stores each entry's CRC32 twice — once in its own local header,
/// immediately before its compressed bytes, and again in the archive's
/// central directory at the end of the file. Every other CRC-reading path in
/// this app (`ZipArchiveScanner`/`ZipArchiveHasher`'s fast path, and hence
/// every DAT-vs-hash `AuditEntry.status`) only ever reads the central
/// directory's copy — the one a single seek-to-the-end lookup gets you,
/// without walking every entry's own local header first. A real ZIP writer
/// keeps both copies identical; if they disagree, something touched one
/// copy and not the other — truncation, a careless hex edit, a broken
/// re-pack tool — genuine structural damage the normal hash-vs-DAT audit
/// can never see, since it never reads this second copy at all.
///
/// Implemented as a small standalone binary parser rather than reaching into
/// ZIPFoundation's own `Entry` — its local-header offset/CRC fields are
/// `internal` to that package (`Entry.localFileHeader`, `Entry.dataOffset`),
/// not part of its public API, so there's no supported way to read them
/// through it at all.
///
/// Deliberately NOT run as part of `AuditReporter.generate`/every scan (see
/// `ZipIntegrityAuditor`'s own doc comment for the on-demand decision this
/// motivates) — this file only provides the raw per-archive check; nothing
/// in it touches `AuditReport` itself.
///
/// Not ZIP64-aware: a `ZIP64` archive's real offsets/sizes live in an extra
/// field this parser doesn't decode, so its 32-bit central-directory offset
/// field (`0xFFFFFFFF` sentinel) would misdirect the local-header read. Out
/// of scope for the ROM/CHD-sized archives this app actually deals with
/// (real MAME/TOSEC zips are overwhelmingly well under 4GB); a ZIP64
/// archive is detected by that sentinel and simply skipped per-entry rather
/// than risk reading garbage.
public enum ZipLocalHeaderCRCVerifier {
    /// General-purpose bit flag bit 3 (0x0008): the writer streamed the
    /// entry out before it knew the final CRC32/sizes, so the local header's
    /// own CRC32 field is a placeholder zero — the real value lives in a
    /// "data descriptor" written after the compressed bytes instead (whose
    /// own signature is optional per spec, so reliably relocating it needs
    /// more than this lightweight structural check is built for). Entries
    /// using it are reported unable to verify, never as a false mismatch.
    private static let dataDescriptorFlag: UInt16 = 0x0008
    private static let zip64Sentinel: UInt32 = 0xFFFF_FFFF

    /// Cross-checks every entry in `archiveURL` in one pass (one full file
    /// read, one central-directory walk) rather than per-entry, since the
    /// central directory has to be located and parsed once regardless of how
    /// many entries are being checked.
    public static func verify(_ archiveURL: URL) throws -> [ZipEntryCRCConsistency] {
        guard let data = FileManager.default.contents(atPath: archiveURL.path) else {
            throw ZipLocalHeaderCRCVerifierError.cannotReadArchive(archiveURL)
        }
        let records = try centralDirectoryRecords(in: data, archiveURL: archiveURL)

        return records.map { record in
            guard !record.usesDataDescriptor, record.localHeaderOffset != zip64Sentinel,
                  let localCRC = localHeaderCRC32(in: data, at: record.localHeaderOffset) else {
                return ZipEntryCRCConsistency(entryName: record.name, matches: nil)
            }
            return ZipEntryCRCConsistency(entryName: record.name, matches: localCRC == record.crc32)
        }
    }

    private struct CentralDirectoryRecord {
        let name: String
        let crc32: UInt32
        let localHeaderOffset: UInt32
        let usesDataDescriptor: Bool
    }

    private static func centralDirectoryRecords(in data: Data, archiveURL: URL) throws -> [CentralDirectoryRecord] {
        guard let eocdOffset = findEndOfCentralDirectory(in: data) else {
            throw ZipLocalHeaderCRCVerifierError.malformedArchive(archiveURL)
        }
        let entryCount = Int(readUInt16LE(data, eocdOffset + 10))
        let centralDirOffset = Int(readUInt32LE(data, eocdOffset + 16))

        var records: [CentralDirectoryRecord] = []
        var offset = centralDirOffset
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, readUInt32LE(data, offset) == 0x0201_4b50 else {
                throw ZipLocalHeaderCRCVerifierError.malformedArchive(archiveURL)
            }
            let flag = readUInt16LE(data, offset + 8)
            let crc = readUInt32LE(data, offset + 16)
            let nameLength = Int(readUInt16LE(data, offset + 28))
            let extraLength = Int(readUInt16LE(data, offset + 30))
            let commentLength = Int(readUInt16LE(data, offset + 32))
            let localOffset = readUInt32LE(data, offset + 42)
            let nameStart = offset + 46
            guard nameStart + nameLength <= data.count else {
                throw ZipLocalHeaderCRCVerifierError.malformedArchive(archiveURL)
            }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? ""
            records.append(CentralDirectoryRecord(name: name, crc32: crc, localHeaderOffset: localOffset, usesDataDescriptor: flag & dataDescriptorFlag != 0))
            offset = nameStart + nameLength + extraLength + commentLength
        }
        return records
    }

    private static func localHeaderCRC32(in data: Data, at offset: UInt32) -> UInt32? {
        let start = Int(offset)
        guard start >= 0, start + 30 <= data.count, readUInt32LE(data, start) == 0x0403_4b50 else { return nil }
        return readUInt32LE(data, start + 14)
    }

    /// Searches backward from the end of the file, same direction a real
    /// unzip has to — the only thing that reliably marks where the central
    /// directory ends is this record's own fixed signature, and a ZIP
    /// comment (also fixed-length-bounded, ≤65535 bytes) can sit after it,
    /// so it's never at a known fixed offset from either end.
    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        let minSize = 22
        guard data.count >= minSize else { return nil }
        let searchStart = max(0, data.count - minSize - 65535)
        var i = data.count - minSize
        while i >= searchStart {
            if readUInt32LE(data, i) == 0x0605_4b50 { return i }
            i -= 1
        }
        return nil
    }

    private static func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
        let base = data.startIndex + offset
        return UInt16(data[base]) | (UInt16(data[base + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        return UInt32(data[base]) | (UInt32(data[base + 1]) << 8) | (UInt32(data[base + 2]) << 16) | (UInt32(data[base + 3]) << 24)
    }
}
