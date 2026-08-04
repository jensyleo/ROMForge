// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A persisted, already-parsed `DATFile`, alongside the source DAT's own
/// (size, modification date) and the settings it was parsed under — re-
/// parsing a real MAME `-listxml` dump (hundreds of MB of XML) can take
/// over a minute in an unoptimized build, and `LibraryViewModel`'s in-memory
/// cache already avoided doing that more than once *within* a session, but
/// every fresh app launch started from nothing, silently paying that same
/// cost again even though nothing about the DAT or its settings had
/// actually changed since last time.
///
/// Keyed by the source file's own size/mtime (not a hash — hashing a
/// hundreds-of-MB file just to decide whether to re-parse it would defeat
/// half the point) plus `mergeMode`/`biosMergeMode`, since both change what
/// `DATLoader.load` actually produces from the same bytes.
public struct DATFileCache: Sendable, Codable, Equatable {
    /// Bumped whenever `MAMESetLayoutPlanner`/`DATLoader`/`ROMMatcher`'s own
    /// DAT-parsing/matching *logic* changes in a way that would produce a
    /// different `DATFile` from the exact same source bytes and mode
    /// settings — real bug found live by jensyleo (2026-08-04): `isValid`
    /// below only ever compared the source file's (size, mtime) and the
    /// chosen merge modes, with no way to know the *code* that transforms
    /// one into the other had changed. Fixing a real bug in
    /// `MAMESetLayoutPlanner.mergedGame`/`ROMMatcher.strictOwnArchiveOnly`
    /// (both 2026-08-03) silently kept serving the *old*, pre-fix cached
    /// `DATFile` for any (DAT file, mode) combination a user had already
    /// visited before updating — the fix was real and correct, but stayed
    /// invisible for exactly that combination until something else (the
    /// DAT file changing, or manually clearing the cache) happened to
    /// invalidate it. A plain incrementing integer, bumped by hand each
    /// time such logic changes, forces every existing cache entry to miss
    /// exactly once after an update like that, rather than silently
    /// serving stale results indefinitely.
    private static let currentFormatVersion = 1
    public let sourceSize: Int64
    public let sourceModificationDate: Date
    public let mergeMode: SetMergeMode
    public let biosMergeMode: SetMergeMode
    public let dat: DATFile
    private let formatVersion: Int

    public init(sourceSize: Int64, sourceModificationDate: Date, mergeMode: SetMergeMode, biosMergeMode: SetMergeMode, dat: DATFile) {
        self.sourceSize = sourceSize
        self.sourceModificationDate = sourceModificationDate
        self.mergeMode = mergeMode
        self.biosMergeMode = biosMergeMode
        self.dat = dat
        self.formatVersion = Self.currentFormatVersion
    }

    private enum CodingKeys: String, CodingKey {
        case sourceSize, sourceModificationDate, mergeMode, biosMergeMode, dat, formatVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceSize = try container.decode(Int64.self, forKey: .sourceSize)
        sourceModificationDate = try container.decode(Date.self, forKey: .sourceModificationDate)
        mergeMode = try container.decode(SetMergeMode.self, forKey: .mergeMode)
        biosMergeMode = try container.decode(SetMergeMode.self, forKey: .biosMergeMode)
        dat = try container.decode(DATFile.self, forKey: .dat)
        // A cache file written before this field existed decodes as `0` —
        // guaranteed to mismatch `currentFormatVersion` (starting at `1`)
        // and correctly treated as stale by `isValid` below, rather than
        // failing to decode at all.
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceSize, forKey: .sourceSize)
        try container.encode(sourceModificationDate, forKey: .sourceModificationDate)
        try container.encode(mergeMode, forKey: .mergeMode)
        try container.encode(biosMergeMode, forKey: .biosMergeMode)
        try container.encode(dat, forKey: .dat)
        try container.encode(formatVersion, forKey: .formatVersion)
    }

    /// Whether this cached entry still matches a DAT file's current
    /// (size, mtime), the settings it would be parsed under, and the
    /// parsing/matching logic's own current version — `false` means the
    /// source file changed since this was cached, the caller wants a
    /// different merge mode/BIOS merge mode than what was cached, or the
    /// code that produces a `DATFile` from these inputs has changed since.
    public func isValid(sourceSize: Int64, sourceModificationDate: Date, mergeMode: SetMergeMode, biosMergeMode: SetMergeMode) -> Bool {
        formatVersion == Self.currentFormatVersion
            && self.sourceSize == sourceSize
            && self.sourceModificationDate == sourceModificationDate
            && self.mergeMode == mergeMode
            && self.biosMergeMode == biosMergeMode
    }

    public static func load(contentsOf url: URL) throws -> DATFileCache {
        try JSONDecoder().decode(DATFileCache.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
