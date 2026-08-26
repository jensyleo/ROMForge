// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Reads every scanned `.chd` file's header exactly once and indexes it by
/// SHA1 and by URL — added 2026-08-13 (performance audit, "Ciclo A") to fix
/// a real O(disks × CHD files) hot path: `CHDMatcher.match` used to
/// linear-scan `chdFiles` and re-read each candidate's header from disk for
/// *every* `<disk>` the DAT declares, so the same file's header got opened
/// and read again and again — once per disk lookup that reached it — for a
/// MAME set with many CHD-based games. Same "build a hash index once"
/// pattern `ROMMatcher` already uses for regular roms, just never applied
/// to disks.
///
/// Headers that fail to read (corrupt/truncated file) are simply absent
/// from the index — `CHDMatcher`/`DiskAuditor` already treat a missing
/// header as "no match", the same behavior a per-call `try?` had before.
public struct CHDHeaderIndex: Sendable {
    private let headersByURL: [URL: CHDHeader]
    private let urlsBySHA1: [String: [URL]]

    public init(chdFiles: [URL]) {
        var headers: [URL: CHDHeader] = [:]
        var bySHA1: [String: [URL]] = [:]
        for url in chdFiles {
            guard let header = try? CHDHeaderReader.read(contentsOf: url) else { continue }
            headers[url] = header
            bySHA1[header.sha1, default: []].append(url)
        }
        headersByURL = headers
        urlsBySHA1 = bySHA1
    }

    public func header(for url: URL) -> CHDHeader? {
        headersByURL[url]
    }

    /// Every scanned CHD whose header SHA1 equals `sha1` — a list, not a
    /// single URL, since the same physical disk content can legitimately
    /// exist in more than one place (e.g. a duplicate folder mirroring
    /// part of a collection).
    public func urls(withSHA1 sha1: String) -> [URL] {
        urlsBySHA1[sha1] ?? []
    }
}
