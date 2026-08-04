// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// Groups hashed local files by content identity, surfacing every set of
/// two or more files that share identical content.
public enum DuplicateDetector {
    public static func find(in hashedFiles: [HashedFile]) -> [DuplicateGroup] {
        var order: [String] = []
        var buckets: [String: [HashedFile]] = [:]

        for file in hashedFiles {
            guard let key = identityKey(for: file.hash) else { continue }
            if buckets[key] == nil {
                order.append(key)
            }
            buckets[key, default: []].append(file)
        }

        return order.compactMap { key in
            guard let files = buckets[key], files.count > 1 else { return nil }
            return DuplicateGroup(sha1: key, files: files)
        }
    }

    /// Prefers SHA1 (strongest, and what this grouping was originally keyed
    /// on) but falls back to whichever hash was actually computed —
    /// `HashAlgorithms` may have skipped SHA1 for speed. A single scan
    /// always computes the same algorithm set for every file, so this never
    /// mixes different algorithms' values across files within one grouping.
    /// A file with no hash at all can't happen in practice (`HashAlgorithms`
    /// always keeps at least one algorithm enabled) but is excluded
    /// defensively rather than crashing.
    private static func identityKey(for hash: FileHash) -> String? {
        hash.sha1 ?? hash.md5 ?? hash.crc32
    }
}
