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

    /// Paths of `.chd` files seen by a scan, kept DELIBERATELY OUTSIDE
    /// `entries` — jensyleo's own instruction (2026-09-10) to verify Fase
    /// 1's read path survived the scan-scoping work intact, which is how
    /// this was found.
    ///
    /// `CollectionHasher.hash` excludes `.chd` on purpose (a CHD's
    /// whole-file hash has no relationship to any `DATRom`'s, so hashing
    /// one only ever wastes time — `DiskAuditor` audits them separately by
    /// each CHD's own header SHA1). So a CHD never appears in a
    /// `[HashedFile]`, and therefore never in `entries` either. Once
    /// scoping made the folder walk itself scoped, deriving the CHD list
    /// from `[HashedFile]` made it unconditionally EMPTY, silently killing
    /// disk auditing outright: every disk in the DAT reported Missing.
    ///
    /// A plain path list, not a `ScanCacheEntry`: there is no hash to
    /// record, and inventing a placeholder one would be actively dangerous
    /// — `entries` feeds `reconstructedHashedFiles()`, whose output goes
    /// straight into `ROMMatcher`, which would then try to match a CHD as
    /// if it were a rom.
    private var chdPaths: Set<String>

    public init(entries: [String: ScanCacheEntry] = [:], chdPaths: Set<String> = []) {
        self.entries = entries
        self.chdPaths = chdPaths
    }

    /// Every `.chd` this cache knows about, as real URLs — the disk-audit
    /// counterpart to `reconstructedHashedFiles()`, and for the same
    /// reason: a scoped scan walks only its own scope, so every OTHER
    /// folder's CHDs have to come from what was already known or
    /// `DiskAuditor` wrongly reports them all missing.
    public func reconstructedCHDPaths() -> [URL] {
        chdPaths.map { URL(fileURLWithPath: $0) }
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
        //
        // jensyleo's own live report (2026-09-10) of a File-level case-only
        // rename not refreshing on screen led to trying `.resolvingSymlinksInPath()`
        // here — confirmed by direct reproduction to be the wrong fix: it
        // resolves a path to whatever it CURRENTLY, ACTUALLY points to on
        // disk right now, so querying the OLD (pre-rename) scope path
        // AFTER a rename already happened resolves it to the NEW name —
        // creating a mismatch against this cache's entries, which are
        // keyed by whatever name was current AT SCAN TIME, in the OTHER
        // direction. Plain `.path` (no resolution) is what keeps a scan's
        // own written key and a same-scan eviction lookup consistent with
        // each other, confirmed correct by that same reproduction.
        file.url.lastPathComponent == file.name ? file.url.path : "\(file.url.path)::\(file.name)"
    }

    /// Builds a fresh cache from a completed scan's results, ready to
    /// persist for the next one.
    /// `chdPaths` is passed in separately because a CHD never appears in
    /// `hashedFiles` at all (see that property's own doc comment) — the
    /// caller that did the folder walk is the only place that knows them.
    public static func build(from hashedFiles: [HashedFile], chdPaths: [URL] = []) -> ScanCache {
        var entries: [String: ScanCacheEntry] = [:]
        for hashedFile in hashedFiles {
            entries[key(for: hashedFile.file)] = ScanCacheEntry(
                size: hashedFile.file.size,
                modificationDate: hashedFile.file.modificationDate,
                hash: hashedFile.hash,
                headerStripped: hashedFile.headerStripped
            )
        }
        return ScanCache(entries: entries, chdPaths: Set(chdPaths.map(\.path)))
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
        // `chdPaths` is dropped for the scope too, and for the same reason
        // the hash entries are: the scope is being genuinely re-read, so
        // whatever the walk finds there is the truth. Keeping them would
        // make a CHD deleted from a rescanned folder survive in the cache
        // forever, still reported present by `DiskAuditor`.
        return ScanCache(
            entries: entries.filter { key, _ in
                !prefixes.contains { Self.key(key, isUnder: $0) }
            },
            chdPaths: chdPaths.filter { path in
                !prefixes.contains { Self.key(path, isUnder: $0) }
            }
        )
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

    /// Reconstructs every entry as a real `HashedFile`, entirely from what
    /// was already persisted here — no disk access at all. jensyleo's own
    /// request (2026-09-11) to genuinely separate "Scan Folder"/"Scan
    /// File" from "Scan All Folders" (after weighing, and then explicitly
    /// setting aside, the 2026-08-06 always-walk-everything call —
    /// `removingEntries(under:)`'s own doc comment tells that history):
    /// a scoped scan can now walk ONLY the folder/file actually asked
    /// for, then reconstruct every OTHER folder's own files straight from
    /// this cache instead of re-listing them from disk — combined, the
    /// matcher still sees every folder at once (the real fix the
    /// always-walk change was for), while disk access itself stays
    /// genuinely scoped.
    ///
    /// A loose file's key IS its own path (`file.name` is its own last
    /// path component); a zip entry's key is `"<archivePath>::<entry
    /// name>"` (see `key(for:)`) — split back apart here. Malformed keys
    /// (shouldn't exist — nothing else ever writes to this cache) are
    /// skipped rather than crashing on a force-unwrap.
    ///
    /// Sorted by cache key, NOT left in `entries`' own order. `entries` is
    /// a `Dictionary`, whose iteration order is unspecified and genuinely
    /// varies between runs (Swift seeds its hashing per process) — and this
    /// output feeds `ROMMatcher`, which resolves a rom to `scopedCandidates
    /// .first(where: { !consumed[$0] && matches(...) })`. Order therefore
    /// DECIDES which of two byte-identical archives becomes the game's own
    /// claimed set and which is reported as the surplus duplicate.
    /// jensyleo's own report (2026-09-10), a folder holding both `nss.7z`
    /// and `nss.zip`: unsorted, that verdict flipped from scan to scan for
    /// no reason the user could see.
    public func reconstructedHashedFiles() -> [HashedFile] {
        entries.sorted { $0.key < $1.key }.compactMap { key, entry in
            let url: URL
            let name: String
            if let separatorRange = key.range(of: "::") {
                url = URL(fileURLWithPath: String(key[key.startIndex..<separatorRange.lowerBound]))
                name = String(key[separatorRange.upperBound...])
            } else {
                url = URL(fileURLWithPath: key)
                name = url.lastPathComponent
            }
            let file = ScannedFile(url: url, name: name, size: entry.size, modificationDate: entry.modificationDate)
            return HashedFile(file: file, hash: entry.hash, headerStripped: entry.headerStripped)
        }
    }

    public static func load(contentsOf url: URL) throws -> ScanCache {
        try JSONDecoder().decode(ScanCache.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    private enum CodingKeys: String, CodingKey {
        case entries
        case chdPaths
    }

    /// Decodes BOTH the current keyed shape and the legacy one, which was a
    /// bare `[String: ScanCacheEntry]` dictionary at the top level (a
    /// `singleValueContainer`). Every cache already on a user's disk is in
    /// that legacy shape — refusing it would throw, `LibraryViewModel.scan`
    /// would swallow that into an empty cache, and the next scan would be a
    /// full cold rehash of the entire collection. A legacy cache simply has
    /// no CHD list yet; it refills on the next scan that walks those folders.
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let decodedEntries = try? container.decode([String: ScanCacheEntry].self, forKey: .entries) {
            entries = decodedEntries
            chdPaths = try container.decodeIfPresent(Set<String>.self, forKey: .chdPaths) ?? []
            return
        }
        entries = try decoder.singleValueContainer().decode([String: ScanCacheEntry].self)
        chdPaths = []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encode(chdPaths, forKey: .chdPaths)
    }
}
