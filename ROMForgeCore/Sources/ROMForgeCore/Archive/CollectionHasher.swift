// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Hashes a scanned collection for matching: loose files are hashed
/// directly, but `.zip` archives are expanded and their entries hashed
/// individually instead of the archive as a whole — most ROM sets ship one
/// ZIP per game, so the DAT's per-ROM entries live inside the archive, not
/// as the archive's own file.
///
/// A ZIP entry's `HashedFile.file.name` is the entry's own name, while
/// `.file.url` points at the *containing* archive (there's no standalone
/// file for a single entry). Callers that plan filesystem operations from a
/// match (e.g. renaming a misnamed ROM) must check
/// `file.url.lastPathComponent == file.name` before doing so — when it
/// doesn't hold, the match came from inside an archive, and the same
/// rename/move logic used for loose files would incorrectly target the
/// archive itself.
public enum CollectionHasher {
    /// One not-yet-hashed zip entry, paired with the loose-file-shaped
    /// `ScannedFile` `CollectionHasher`/`HashedFile` represent it as.
    private struct PendingZipEntry: Sendable {
        let entryFile: ScannedFile
        let archivedFile: ArchivedFile
    }

    /// A `cache` hit — unchanged size/mtime since a previous scan, for a
    /// loose file, or an unchanged containing archive for a zip entry —
    /// skips re-hashing/re-extracting that file entirely.
    /// - Parameter onProgress: reports one continuous completed/total count
    ///   across both loose-file and zip-entry hashing (whichever order they
    ///   run in) — throttled internally by `ScanProgressCounter`, so this is
    ///   cheap to pass even for a huge collection.
    /// - Parameter onArchiveListed: reports (archivesRead, totalArchives) as
    ///   each zip's central directory is read, before any hashing starts —
    ///   this pass is sequential and, for a collection with many/large
    ///   archives, can itself take long enough to otherwise look like a
    ///   silent hang between "files found on disk" and the first hashing
    ///   progress update.
    public static func hash(scannedFiles: [ScannedFile], cache: ScanCache = ScanCache(), algorithms: HashAlgorithms = .all, onProgress: (@Sendable (ScanProgress) -> Void)? = nil, onArchiveListed: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [HashedFile] {
        let zipFiles = scannedFiles.filter { $0.url.pathExtension.lowercased() == "zip" }
        // `.chd` files are excluded here, not just from "surplus" reporting
        // downstream — a CHD's own whole-file hash has no relationship to
        // any `DATRom`'s CRC/MD5/SHA1 (it's compressed hunks of raw disk
        // data, not a rom), so hashing it here would only ever waste time
        // computing a hash `ROMMatcher` can never use. `DiskAuditor` audits
        // these separately, by each CHD's own *header* SHA1 (`CHDMatcher`).
        let looseFiles = scannedFiles.filter {
            let ext = $0.url.pathExtension.lowercased()
            return ext != "zip" && ext != "chd"
        }

        // Scanning each zip's central directory is cheap (no decompression
        // yet) and stays sequential; only the actual per-entry
        // decompression+hashing below is worth parallelizing. Doing this
        // pass before hashing anything also lets the total (for `onProgress`)
        // include every zip entry up front, not just loose files.
        var hashedFiles: [HashedFile] = []
        var pending: [PendingZipEntry] = []
        var zipEntryCount = 0
        for (archiveIndex, zipFile) in zipFiles.enumerated() {
            try Task.checkCancellation()
            let entries = try ZipArchiveScanner.scan(archive: zipFile.url)
            onArchiveListed?(archiveIndex + 1, zipFiles.count)
            for entry in entries {
                zipEntryCount += 1
                let entryFile = ScannedFile(url: zipFile.url, name: entry.name, size: entry.size, modificationDate: zipFile.modificationDate)
                if let cached = cache.lookup(for: entryFile, algorithms: algorithms) {
                    hashedFiles.append(cached)
                    continue
                }
                pending.append(PendingZipEntry(entryFile: entryFile, archivedFile: entry))
            }
        }

        let total = max(looseFiles.count + zipEntryCount, 1)
        let progress = onProgress.map { ScanProgressCounter(total: total, onProgress: $0) }
        // Zip entries already served from cache above were never routed
        // through the counter — report them as already-done now, so the
        // total the caller sees still adds up to `total`.
        for _ in 0..<(zipEntryCount - pending.count) { progress?.increment() }

        hashedFiles.append(contentsOf: try await FileHasher.hash(files: looseFiles, cache: cache, algorithms: algorithms, progress: progress))
        hashedFiles.append(contentsOf: try await hashPending(pending, algorithms: algorithms, progress: progress))
        return hashedFiles
    }

    /// Hashes zip entries concurrently, bounded to the number of available
    /// cores — a large collection can have entries spread across many
    /// archives (or many entries in a handful of huge ones), and each
    /// `ZipArchiveHasher.hash` call reopens its own `Archive` handle, so
    /// entries are safe to decompress in parallel just like loose files
    /// already are in `FileHasher`.
    private static func hashPending(_ pending: [PendingZipEntry], algorithms: HashAlgorithms, progress: ScanProgressCounter?) async throws -> [HashedFile] {
        guard pending.count > 1 else {
            return try pending.map { item in
                try Task.checkCancellation()
                let (hash, headerStripped) = try ZipArchiveHasher.hash(item.archivedFile, algorithms: algorithms)
                progress?.increment()
                return HashedFile(file: item.entryFile, hash: hash, headerStripped: headerStripped)
            }
        }

        let workerCount = HashingConcurrency.workerCount(for: pending.count)
        let chunks = chunked(pending, into: workerCount)

        let chunkResults = try await withThrowingTaskGroup(of: (Int, [HashedFile]).self) { group in
            for (index, chunk) in chunks.enumerated() {
                group.addTask {
                    var hashed: [HashedFile] = []
                    hashed.reserveCapacity(chunk.count)
                    for item in chunk {
                        try Task.checkCancellation()
                        let (hash, headerStripped) = try ZipArchiveHasher.hash(item.archivedFile, algorithms: algorithms)
                        hashed.append(HashedFile(file: item.entryFile, hash: hash, headerStripped: headerStripped))
                        progress?.increment()
                    }
                    return (index, hashed)
                }
            }
            var ordered = [[HashedFile]](repeating: [], count: chunks.count)
            for try await (index, hashed) in group {
                ordered[index] = hashed
            }
            return ordered
        }
        return chunkResults.flatMap { $0 }
    }

    private static func chunked(_ items: [PendingZipEntry], into count: Int) -> [[PendingZipEntry]] {
        guard count > 1 else { return [items] }
        let size = (items.count + count - 1) / count
        return stride(from: 0, to: items.count, by: size).map {
            Array(items[$0..<min($0 + size, items.count)])
        }
    }
}
