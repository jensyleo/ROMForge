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
        }
    }

    /// Removes one entry from an EXISTING `.zip` — see
    /// `RebuildOperation.removeEntryFromZip`'s own doc comment.
    private static func removeEntryFromZip(
        archive archiveURL: URL,
        entryName: String,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw RebuildError.sourceMissing(archiveURL)
        }
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .update)
        } catch {
            throw RebuildError.underlying("Could not open ZIP archive for update at \(archiveURL.path)")
        }
        guard let entry = archive[entryName] else {
            throw RebuildError.sourceMissing(archiveURL.appendingPathComponent(entryName))
        }
        do {
            try archive.remove(entry)
        } catch {
            throw RebuildError.underlying(error.localizedDescription)
        }
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
        do {
            _ = try archive.extract(entry, to: destination)
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
        var data = Data()
        do {
            _ = try archive.extract(zipEntry) { data.append($0) }
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
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw RebuildError.destinationExists(destination)
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
