// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import ZIPFoundation

/// Executes a `RebuildOperation` plan against the real filesystem. Never
/// overwrites an existing destination — a collision is always an error, not
/// a silent clobber.
public enum RebuildExecutor {
    /// Same zip-bomb guard as `ZipArchiveHasher`'s own
    /// `maxOverDeclaredSizeFactor`/`overageLimit` — the central directory's
    /// declared `uncompressedSize` is attacker-controlled, so extraction
    /// here (a real file write during rebuild/repair, not just hashing) must
    /// abort once the actual decompressed byte count runs far past what the
    /// entry claims, rather than trusting it as a hard cap (real ROM/CD
    /// dumps can legitimately be many GB). Found during a 2026-09-30 code
    /// audit: the hashing path (`ZipArchiveHasher`/`SevenZipArchiveHasher`)
    /// already had this guard, but these two extraction call sites didn't —
    /// a crafted zip could still be decompressed unbounded here even though
    /// it would have been rejected as a suspected bomb if it were ever
    /// hashed first.
    private static func zipBombOverageLimit(for declaredSize: UInt64) -> UInt64 {
        max(1_048_576, declaredSize * 10)
    }


    public static func execute(_ operations: [RebuildOperation], fileManager: FileManager = .default) throws {
        for operation in operations {
            try perform(operation, fileManager: fileManager)
        }
    }

    private static func perform(_ operation: RebuildOperation, fileManager: FileManager) throws {
        switch operation {
        case .rename(let source, let destination), .move(let source, let destination):
            try relocate(from: source, to: destination, fileManager: fileManager) {
                try fileManager.moveItem(at: source, to: destination)
            }
        case .copy(let source, let destination):
            try relocate(from: source, to: destination, fileManager: fileManager) {
                try fileManager.copyItem(at: source, to: destination)
            }
        case .extractZipEntry(let archiveURL, let entryName, let destination):
            try extractZipEntry(archive: archiveURL, entryName: entryName, to: destination, fileManager: fileManager)
        case .createArchive(let entries, let destination):
            try createArchive(entries: entries, at: destination, fileManager: fileManager)
        case .createTorrentZipArchive(let entries, let destination):
            try createTorrentZipArchive(entries: entries, at: destination, fileManager: fileManager)
        case .delete(let target):
            guard fileManager.fileExists(atPath: target.path) else {
                throw RebuildError.sourceMissing(target)
            }
            try fileManager.removeItem(at: target)
        case .addEntryToZip(let targetArchive, let entryName, let source):
            try addEntryToZip(targetArchive: targetArchive, entryName: entryName, source: source, fileManager: fileManager)
        case .removeEntryFromZip(let archiveURL, let entryName):
            try removeEntryFromZip(archive: archiveURL, entryName: entryName, fileManager: fileManager)
        case .createDummyFile(let url, let size):
            try createDummyFile(at: url, size: size, fileManager: fileManager)
        case .createDummyZipEntry(let targetArchive, let entryName, let size):
            try createDummyZipEntry(targetArchive: targetArchive, entryName: entryName, size: size, fileManager: fileManager)
        case .clearZipComment(let archiveURL):
            try clearZipComment(at: archiveURL, fileManager: fileManager)
        }
    }

    /// Hard ceiling on a dummy placeholder's size — a malformed/malicious
    /// DAT declaring an absurd `size` for a `nodump` rom must never turn
    /// "Create Dummy ROMs" into an accidental multi-gigabyte write. 64 MiB
    /// comfortably covers every real nodump placeholder found in practice
    /// (an undumped PAL/GAL is a tiny marker, not real ROM content).
    private static let maxDummyFileSize: Int64 = 64 * 1024 * 1024

    private static func dummyData(size: Int64) -> Data {
        Data(count: Int(max(0, min(size, maxDummyFileSize))))
    }

    /// Creates a placeholder LOOSE file — see `RebuildOperation
    /// .createDummyFile`'s own doc comment.
    private static func createDummyFile(at url: URL, size: Int64, fileManager: FileManager) throws {
        guard !fileManager.fileExists(atPath: url.path) else {
            throw RebuildError.destinationExists(url)
        }
        let parent = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        do {
            try dummyData(size: size).write(to: url, options: .atomic)
        } catch {
            throw RebuildError.underlying(error.localizedDescription)
        }
    }

    /// Adds a placeholder ZIP entry — see `RebuildOperation
    /// .createDummyZipEntry`'s own doc comment. Same "add one new entry,
    /// leave every other one untouched" shape as `addEntryToZip` above.
    private static func createDummyZipEntry(targetArchive: URL, entryName: String, size: Int64, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: targetArchive.path) else {
            throw RebuildError.sourceMissing(targetArchive)
        }
        let data = dummyData(size: size)
        let archive: Archive
        do {
            archive = try Archive(url: targetArchive, accessMode: .update)
        } catch {
            throw RebuildError.underlying("Could not open ZIP archive for update at \(targetArchive.path)")
        }
        guard archive[entryName] == nil else {
            throw RebuildError.destinationExists(targetArchive.appendingPathComponent(entryName))
        }
        do {
            try archive.addEntry(with: entryName, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        } catch {
            throw RebuildError.underlying(error.localizedDescription)
        }
    }

    /// Strips a `.zip`'s own trailing comment field, in place — see
    /// `RebuildOperation.clearZipComment`'s own doc comment. Locates the
    /// End-Of-Central-Directory record's fixed 22-byte header by scanning
    /// BACKWARD from the end of the file for its signature — the comment
    /// (if any) is always the very last thing in a ZIP, so this never has
    /// to parse a single entry or the central directory itself. `65535` is
    /// the ZIP format's own hard maximum comment length (a 2-byte length
    /// field), so the backward search window is always bounded regardless
    /// of how large the archive itself is.
    private static func clearZipComment(at url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw RebuildError.sourceMissing(url)
        }
        var data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RebuildError.underlying(error.localizedDescription)
        }
        let signature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let eocdFixedSize = 22
        guard data.count >= eocdFixedSize else {
            throw RebuildError.underlying("Not a valid ZIP archive (too small): \(url.path)")
        }
        let searchFloor = max(0, data.count - eocdFixedSize - 65535)
        var eocdOffset: Int?
        var i = data.count - eocdFixedSize
        while i >= searchFloor {
            if data[i] == signature[0], data[i + 1] == signature[1], data[i + 2] == signature[2], data[i + 3] == signature[3] {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard let offset = eocdOffset else {
            throw RebuildError.underlying("Could not find the ZIP End-Of-Central-Directory record: \(url.path)")
        }
        // The comment-length field sits at bytes [offset+20, offset+22) of
        // the EOCD record (a 2-byte little-endian count) — already zero
        // means there's genuinely no comment to remove, a harmless no-op
        // rather than an error.
        let commentLengthOffset = offset + 20
        guard data[commentLengthOffset] != 0 || data[commentLengthOffset + 1] != 0 else { return }
        data[commentLengthOffset] = 0
        data[commentLengthOffset + 1] = 0
        data.removeSubrange((offset + eocdFixedSize)...)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RebuildError.underlying(error.localizedDescription)
        }
    }

    /// Removes one entry from an EXISTING `.zip` — see
    /// `RebuildOperation.removeEntryFromZip`'s own doc comment.
    ///
    /// **Does NOT use `ZIPFoundation.Archive.remove(_:)`** — real crash
    /// found live by jensyleo (2026-09-14): that function rewrites the
    /// archive in place, computing each remaining entry's new offset as
    /// `entryStart - offset` in **unsigned** (`UInt64`) arithmetic, where
    /// `offset` comes from the REMOVED entry's own local-header size field.
    /// A corrupted/inconsistent entry (exactly the kind this gets called
    /// on — `RebuildPlanner.planReplaceCorruptedRoms`'s whole reason to
    /// exist is a `.hashMismatch` rom) can carry a local-header size that
    /// doesn't match its real position in the file, making that
    /// subtraction underflow — an instant, uncatchable `SIGTRAP` (Swift
    /// traps on unsigned overflow; no Swift `do`/`catch` around
    /// `archive.remove` can prevent the crash, confirmed live).
    ///
    /// Instead, this rebuilds the archive from scratch: read EVERY OTHER
    /// entry's own real bytes (`createArchive`, below — the same "read
    /// each entry, write it into a brand-new `.zip`" path `createArchive`
    /// already used for a `.createArchive` operation), write them into a
    /// fresh temporary archive, then atomically swap it in for the
    /// original (via a backup-then-restore-on-failure dance, never a
    /// straight delete-then-move that could lose the original if the move
    /// fails). This never touches the removed entry's own possibly-bad
    /// metadata at all — every KEPT entry's bytes are read directly by
    /// name and re-added fresh, so nothing here depends on whatever made
    /// the removed entry's own header inconsistent in the first place.
    private static func removeEntryFromZip(
        archive archiveURL: URL,
        entryName: String,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw RebuildError.sourceMissing(archiveURL)
        }
        let sourceArchive: Archive
        do {
            sourceArchive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            throw RebuildError.underlying("Could not open ZIP archive at \(archiveURL.path)")
        }
        guard sourceArchive[entryName] != nil else {
            throw RebuildError.sourceMissing(archiveURL.appendingPathComponent(entryName))
        }
        let remainingEntries = sourceArchive
            .map(\.path)
            .filter { $0 != entryName }
            .map { ArchiveEntrySource(source: archiveURL, entryName: $0, sourceArchiveEntryName: $0) }

        let tempURL = archiveURL.deletingLastPathComponent()
            .appendingPathComponent(".romforge-rebuild-\(UUID().uuidString)")
            .appendingPathExtension("zip")
        try createArchive(entries: remainingEntries, at: tempURL, fileManager: fileManager)

        let backupURL = archiveURL.appendingPathExtension("romforge-bak-\(UUID().uuidString)")
        do {
            try fileManager.moveItem(at: archiveURL, to: backupURL)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw RebuildError.underlying("Could not back up \(archiveURL.path) before rebuilding it: \(error.localizedDescription)")
        }
        do {
            try fileManager.moveItem(at: tempURL, to: archiveURL)
        } catch {
            // Restore the original untouched — never leave the real
            // archive missing just because the rebuilt replacement
            // couldn't be moved into place.
            try? fileManager.removeItem(at: archiveURL)
            try? fileManager.moveItem(at: backupURL, to: archiveURL)
            try? fileManager.removeItem(at: tempURL)
            throw RebuildError.underlying("Could not replace \(archiveURL.path) with its rebuilt copy: \(error.localizedDescription)")
        }
        try? fileManager.removeItem(at: backupURL)
    }

    /// Adds one entry to an EXISTING `.zip`, leaving every other entry in it
    /// untouched — see `RebuildOperation.addEntryToZip`'s own doc comment.
    private static func addEntryToZip(
        targetArchive: URL,
        entryName: String,
        source: ArchiveEntrySource,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: targetArchive.path) else {
            throw RebuildError.sourceMissing(targetArchive)
        }
        let data = try readEntryData(source)
        let archive: Archive
        do {
            archive = try Archive(url: targetArchive, accessMode: .update)
        } catch {
            throw RebuildError.underlying("Could not open ZIP archive for update at \(targetArchive.path)")
        }
        guard archive[entryName] == nil else {
            throw RebuildError.destinationExists(targetArchive.appendingPathComponent(entryName))
        }
        do {
            try archive.addEntry(with: entryName, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        } catch {
            throw RebuildError.underlying(error.localizedDescription)
        }
    }

    /// Pulls one named entry out of a `.zip` onto disk as its own standalone
    /// file — see `RebuildOperation.extractZipEntry`'s own doc comment for
    /// why a plain `fileManager.copyItem`/`.moveItem` on the containing
    /// archive's own URL would be wrong here.
    private static func extractZipEntry(
        archive archiveURL: URL,
        entryName: String,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw RebuildError.sourceMissing(archiveURL)
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw RebuildError.destinationExists(destination)
        }
        let parent = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            throw RebuildError.underlying("Could not open ZIP archive at \(archiveURL.path)")
        }
        guard let entry = archive[entryName] else {
            throw RebuildError.sourceMissing(archiveURL.appendingPathComponent(entryName))
        }
        let limit = zipBombOverageLimit(for: entry.uncompressedSize)
        fileManager.createFile(atPath: destination.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: destination.path) else {
            throw RebuildError.underlying("Could not open \(destination.path) for writing.")
        }
        defer { try? handle.close() }
        var extracted: UInt64 = 0
        do {
            _ = try archive.extract(entry) { chunk in
                extracted += UInt64(chunk.count)
                guard extracted <= limit else {
                    throw RebuildError.underlying("Refusing to extract \(entryName): decompressed size exceeds \(limit) bytes, more than 10x its declared size — suspected zip bomb.")
                }
                handle.write(chunk)
            }
        } catch let error as RebuildError {
            try? handle.close()
            try? fileManager.removeItem(at: destination)
            throw error
        } catch {
            throw RebuildError.underlying(error.localizedDescription)
        }
    }

    /// Reads one `ArchiveEntrySource`'s actual bytes — straight off disk for
    /// a loose file, or extracted from inside its containing `.zip` when
    /// `sourceArchiveEntryName` says this source is an archive entry, not a
    /// standalone file (same distinction `extractZipEntry` exists for).
    private static func readEntryData(_ entry: ArchiveEntrySource) throws -> Data {
        guard let innerEntryName = entry.sourceArchiveEntryName else {
            return try Data(contentsOf: entry.source)
        }
        let archive: Archive
        do {
            archive = try Archive(url: entry.source, accessMode: .read)
        } catch {
            throw RebuildError.underlying("Could not open ZIP archive at \(entry.source.path)")
        }
        guard let zipEntry = archive[innerEntryName] else {
            throw RebuildError.sourceMissing(entry.source.appendingPathComponent(innerEntryName))
        }
        let limit = zipBombOverageLimit(for: zipEntry.uncompressedSize)
        var data = Data()
        do {
            _ = try archive.extract(zipEntry) { chunk in
                guard UInt64(data.count + chunk.count) <= limit else {
                    throw RebuildError.underlying("Refusing to read \(innerEntryName): decompressed size exceeds \(limit) bytes, more than 10x its declared size — suspected zip bomb.")
                }
                data.append(chunk)
            }
        } catch let error as RebuildError {
            throw error
        } catch {
            throw RebuildError.underlying(error.localizedDescription)
        }
        return data
    }

    private static func createArchive(
        entries: [ArchiveEntrySource],
        at destination: URL,
        fileManager: FileManager
    ) throws {
        for entry in entries {
            guard fileManager.fileExists(atPath: entry.source.path) else {
                throw RebuildError.sourceMissing(entry.source)
            }
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw RebuildError.destinationExists(destination)
        }
        let parent = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        // `Archive(url:accessMode:preferredEncoding:)` (failable, deprecated)
        // → `Archive(url:accessMode:pathEncoding:)` (throwing) — 2026-08-13
        // cleanup pass, no behavior change.
        let archive: Archive
        do {
            archive = try Archive(url: destination, accessMode: .create)
        } catch {
            throw RebuildError.underlying("Could not create ZIP archive at \(destination.path)")
        }
        do {
            for entry in entries {
                if entry.sourceArchiveEntryName != nil {
                    let data = try readEntryData(entry)
                    try archive.addEntry(with: entry.entryName, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                        data.subdata(in: Int(position)..<Int(position) + size)
                    }
                } else {
                    try archive.addEntry(with: entry.entryName, fileURL: entry.source, compressionMethod: .deflate)
                }
            }
        } catch {
            throw RebuildError.underlying(error.localizedDescription)
        }
    }

    /// Writes entries as a TorrentZip-compliant archive — Fase 2 Step 2.
    /// Like `createArchive()` but conforms to TorrentZip spec for rebuilds
    /// that need byte-for-byte reproducibility (checksums match across tools).
    private static func createTorrentZipArchive(
        entries: [ArchiveEntrySource],
        at destination: URL,
        fileManager: FileManager
    ) throws {
        for entry in entries {
            guard fileManager.fileExists(atPath: entry.source.path) else {
                throw RebuildError.sourceMissing(entry.source)
            }
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw RebuildError.destinationExists(destination)
        }
        let parent = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        var torrentEntries: [TorrentZipEntry] = []
        for entry in entries {
            let data = try readEntryData(entry)
            torrentEntries.append(TorrentZipEntry(name: entry.entryName, data: data))
        }
        try TorrentZipWriter.write(torrentEntries, to: destination)
    }

    private static func relocate(
        from source: URL,
        to destination: URL,
        fileManager: FileManager,
        _ perform: () throws -> Void
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            throw RebuildError.sourceMissing(source)
        }
        // A rename that only changes CASE (e.g. Fase 2 Step 9's "Sets
        // case"/"Roms case" set to Uppercase/Lowercase) targets the exact
        // same path on the case-insensitive-but-case-preserving default
        // macOS volume (APFS) — `source` and `destination` are literally
        // the same file there, so `fileManager.fileExists(atPath:
        // destination.path)` below would find "the destination" (really
        // just the source, under its current case) and wrongly refuse
        // the rename as a collision. jensyleo's own report (2026-09-01),
        // caught by the test suite before any real-ROM testing: without
        // this exemption, every real Mac user's own "Uppercase"/
        // "Lowercase" case-policy run would fail on every single rename.
        // A genuine cross-file collision (different actual path) still
        // gets rejected exactly as before.
        let isCaseOnlyRename = source.path.lowercased() == destination.path.lowercased() && source.path != destination.path
        if !isCaseOnlyRename {
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw RebuildError.destinationExists(destination)
            }
        }
        let parent = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        do {
            try perform()
        } catch let error as RebuildError {
            throw error
        } catch {
            throw RebuildError.underlying(error.localizedDescription)
        }
    }
}
