// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A persisted (size, modification date) → hash mapping, keyed by file
/// path — re-scanning a collection only needs to rehash a file whose size
/// or mtime disagree with what's cached, not every file every time. This
/// mirrors RomVault's own documented approach (see ROADMAP.md's research
/// notes): "only rehash if new or timestamps changed."
///
/// Keying: a loose file's key is its own path. A zip-entry-shaped
/// `HashedFile` (see `CollectionHasher`) reuses the containing archive's
/// `url` for every entry, so entries are keyed by `"<archivePath>::<entry
/// name>"` instead — `ScannedFile.modificationDate` for those is the
/// *archive's* mtime (an entry has none of its own), so the cache is
/// invalidated for every entry at once if the archive itself changes.
public struct ScanCacheEntry: Equatable, Sendable, Codable {
    public let size: Int64
    public let modificationDate: Date
    public let hash: FileHash
    public let headerStripped: HeaderStrippedHash?

    public init(size: Int64, modificationDate: Date, hash: FileHash, headerStripped: HeaderStrippedHash?) {
        self.size = size
        self.modificationDate = modificationDate
        self.hash = hash
        self.headerStripped = headerStripped
    }
}

public struct ScanCache: Sendable, Codable, Equatable {
    private var entries: [String: ScanCacheEntry]

    public init(entries: [String: ScanCacheEntry] = [:]) {
        self.entries = entries
    }

    /// Returns a previously-hashed result for `file` if the cache has an
    /// entry for its key whose size and modification date still match, *and*
    /// whose hash already covers every algorithm `algorithms` wants — a
    /// cache built while, say, only CRC32 was enabled can't satisfy a later
    /// lookup that also wants MD5, even for an unchanged file; that's
    /// treated as a miss so the file gets rehashed with the fuller set,
    /// rather than silently missing an algorithm it was never asked to
    /// compute the first time. `nil` (a cache miss) otherwise means the
    /// file is new or has changed since.
    public func lookup(for file: ScannedFile, algorithms: HashAlgorithms = .all) -> HashedFile? {
        lookup(key: Self.key(for: file), size: file.size, modificationDate: file.modificationDate, algorithms: algorithms).map {
            HashedFile(file: file, hash: $0.hash, headerStripped: $0.headerStripped)
        }
    }

    /// Lower-level lookup for zip entries, whose cache key/validity is
    /// derived from the containing archive rather than from a
    /// already-constructed `ScannedFile`.
    public func lookup(key: String, size: Int64, modificationDate: Date, algorithms: HashAlgorithms = .all) -> ScanCacheEntry? {
        guard let entry = entries[key], entry.size == size, entry.modificationDate == modificationDate,
              satisfies(entry.hash, algorithms)
        else {
            return nil
        }
        return entry
    }

    private func satisfies(_ hash: FileHash, _ algorithms: HashAlgorithms) -> Bool {
        if algorithms.contains(.crc32), hash.crc32 == nil { return false }
        if algorithms.contains(.md5), hash.md5 == nil { return false }
        if algorithms.contains(.sha1), hash.sha1 == nil { return false }
        return true
    }

    public static func key(for file: ScannedFile) -> String {
        // A zip entry's ScannedFile reuses the archive's url with a
        // different name — the same test CollectionHasher's docs already
        // establish for "this came from inside an archive."
        file.url.lastPathComponent == file.name ? file.url.path : "\(file.url.path)::\(file.name)"
    }

    /// Builds a fresh cache from a completed scan's results, ready to
    /// persist for the next one.
    public static func build(from hashedFiles: [HashedFile]) -> ScanCache {
        var entries: [String: ScanCacheEntry] = [:]
        for hashedFile in hashedFiles {
            entries[key(for: hashedFile.file)] = ScanCacheEntry(
                size: hashedFile.file.size,
                modificationDate: hashedFile.file.modificationDate,
                hash: hashedFile.hash,
                headerStripped: hashedFile.headerStripped
            )
        }
        return ScanCache(entries: entries)
    }

    public static func load(contentsOf url: URL) throws -> ScanCache {
        try JSONDecoder().decode(ScanCache.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public init(from decoder: Decoder) throws {
        entries = try decoder.singleValueContainer().decode([String: ScanCacheEntry].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries)
    }
}
