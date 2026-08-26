// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Computes CRC32/MD5/SHA1 (whichever `algorithms` selects) for a file or an
/// in-memory buffer, streaming file reads in fixed-size chunks so large
/// ROMs don't need to be loaded whole.
public enum FileHasher {
    public static func hash(data: Data, algorithms: HashAlgorithms = .all) -> FileHash {
        var hasher = StreamingHasher(algorithms: algorithms)
        hasher.update(data)
        return hasher.finalize()
    }

    public static func hash(contentsOf url: URL, chunkSize: Int = 1_048_576, algorithms: HashAlgorithms = .all) throws -> FileHash {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw HasherError.cannotOpenFile(url)
        }
        defer { try? handle.close() }

        var hasher = StreamingHasher(algorithms: algorithms)
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(chunk)
        }
        return hasher.finalize()
    }

    /// Hashes many files concurrently, bounded to the number of available
    /// cores, preserving `files`' order in the result — hashing a large
    /// collection sequentially leaves most of a multi-core Mac idle. A
    /// `cache` hit (unchanged size/mtime since a previous scan, *and*
    /// already covering every algorithm `algorithms` wants — see
    /// `ScanCache.lookup`) skips re-hashing that file entirely.
    public static func hash(files: [ScannedFile], cache: ScanCache = ScanCache(), algorithms: HashAlgorithms = .all, progress: ScanProgressCounter? = nil) async throws -> [HashedFile] {
        guard files.count > 1 else {
            return try files.map { file in
                try Task.checkCancellation()
                let result = try cache.lookup(for: file, algorithms: algorithms) ?? hashedFile(for: file, algorithms: algorithms)
                progress?.increment()
                return result
            }
        }

        let workerCount = HashingConcurrency.workerCount(for: files.count)
        let chunks = chunked(files, into: workerCount)

        let chunkResults = try await withThrowingTaskGroup(of: (Int, [HashedFile]).self) { group in
            for (index, chunk) in chunks.enumerated() {
                group.addTask {
                    var hashed: [HashedFile] = []
                    hashed.reserveCapacity(chunk.count)
                    for file in chunk {
                        try Task.checkCancellation()
                        hashed.append(try cache.lookup(for: file, algorithms: algorithms) ?? hashedFile(for: file, algorithms: algorithms))
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

    /// Hashes a file's full contents and, if a known copier-header
    /// signature is detected (`HeaderSkipRule`), also hashes the
    /// header-stripped contents — so a headered console dump can still
    /// match a headerless DAT entry via `HashedFile.headerStripped`.
    private static func hashedFile(for file: ScannedFile, algorithms: HashAlgorithms) throws -> HashedFile {
        HashedFile(file: file, hash: try hash(contentsOf: file.url, algorithms: algorithms), headerStripped: try headerStrippedHash(for: file, algorithms: algorithms))
    }

    private static func headerStrippedHash(for file: ScannedFile, algorithms: HashAlgorithms) throws -> HeaderStrippedHash? {
        guard let handle = FileHandle(forReadingAtPath: file.url.path) else {
            throw HasherError.cannotOpenFile(file.url)
        }
        defer { try? handle.close() }

        // Genesis .smd is a block interleave, not a leading header — needs
        // the whole (small) file in memory and a reordering pass, so it's
        // handled separately before the generic skip-N-bytes rules below.
        if file.url.pathExtension.lowercased() == "smd", GenesisSMDConverter.isSMDInterleaved(fileSize: file.size) {
            let fullData = try handle.readToEnd() ?? Data()
            guard let deinterleaved = GenesisSMDConverter.deinterleave(fullData) else { return nil }
            return HeaderStrippedHash(rule: .genesisSMD, size: Int64(deinterleaved.count), hash: hash(data: deinterleaved, algorithms: algorithms))
        }

        let headBytes = try handle.read(upToCount: 64) ?? Data()
        guard let (rule, headerLength) = HeaderSkipRule.detect(fileSize: file.size, headBytes: headBytes) else {
            return nil
        }

        try handle.seek(toOffset: UInt64(headerLength))
        var hasher = StreamingHasher(algorithms: algorithms)
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(chunk)
        }
        return HeaderStrippedHash(rule: rule, size: file.size - Int64(headerLength), hash: hasher.finalize())
    }

    private static func chunked(_ files: [ScannedFile], into count: Int) -> [[ScannedFile]] {
        guard count > 1 else { return [files] }
        let size = (files.count + count - 1) / count
        return stride(from: 0, to: files.count, by: size).map {
            Array(files[$0..<min($0 + size, files.count)])
        }
    }
}
