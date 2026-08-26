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

    /// A copy with every entry under any of `paths` dropped, so those files
    /// get genuinely rehashed on the next scan instead of served from here.
    ///
    /// Exists for an explicit user-driven "rescan this folder/file" — added
    /// 2026-08-06, when scanning was changed to always feed the matcher every
    /// folder's files (so cross-folder duplicates are always visible; see
    /// `LibraryViewModel.scan`'s own doc comment). With that change the
    /// selected scope no longer limits *what gets matched*, only *what gets
    /// re-read from disk* — and an ordinary size+mtime cache hit would
    /// otherwise make "Rescan This File" a silent no-op on a file whose
    /// content was replaced without its size or mtime changing (some copy
    /// tools preserve both), which is exactly the case a user reaches for
    /// that command to resolve.
    ///
    /// Matched by path prefix, since a cache key is either a loose file's own
    /// path or `"<archive path>::<entry name>"` for a zip entry (see
    /// `key(for:)`) — both start with the real file's path, so one prefix
    /// test covers an archive and every entry inside it.
    public func removingEntries(under paths: [URL]) -> ScanCache {
        guard !paths.isEmpty else { return self }
        let prefixes = paths.map(\.path)
        return ScanCache(entries: entries.filter { key, _ in
            !prefixes.contains { Self.key(key, isUnder: $0) }
        })
    }

    /// A cache `key` (a loose file's own path, or `"<archivePath>::<entry
    /// name>"`) is "under" `path` only if `key` names that exact file/
    /// archive, or genuinely lives inside it as a folder — never merely
    /// because `path` is a string prefix of `key`. A bare `key.hasPrefix`
    /// check would also match an unrelated *sibling* whose name happens to
    /// start with `path`'s (e.g. a folder named "CPS1" wrongly sweeping up
    /// "CPS10"'s entries too) — the exact bug already found and fixed once
    /// for this same comparison in `LibraryViewModel.removeFolder`, but
    /// missed here since this is a different call site.
    static func key(_ key: String, isUnder path: String) -> Bool {
        key == path || key.hasPrefix(path + "/") || key.hasPrefix(path + "::")
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
