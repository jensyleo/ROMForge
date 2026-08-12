// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Outcome of matching one expected `MAMEDisk` against scanned `.chd` files.
public enum CHDDiskStatus: Equatable, Sendable {
    /// A CHD's header SHA1 matches the disk's expected SHA1.
    case correct(URL)
    /// A CHD exists at the expected filename, but its header SHA1 doesn't match.
    case incorrect(URL)
    case missing
    /// The DAT declares this disk with no `sha1` at all — real hardware
    /// media MAME knows exists but nobody has successfully dumped/verified
    /// (the disk-level equivalent of a `nodump` rom, see `RomMatchStatus.nodump`'s
    /// own doc comment) — and a `.chd` file exists at the expected filename.
    /// There's nothing to verify its content against by design, so it can
    /// never be `.correct`, but a same-named file existing at all is exactly
    /// what a real reference tool (RomCenter/ClrMamePro) recognizes for this
    /// case rather than reporting a false `.missing`.
    case unverifiable(URL)
}

/// Matches an expected `MAMEDisk` (from a MAME `-listxml` machine) against a
/// pool of scanned `.chd` files, using each CHD's own header SHA1 — never by
/// decompressing hunks, and never by filename alone.
public enum CHDMatcher {
    public static func match(disk: MAMEDisk, chdFiles: [URL]) -> CHDDiskStatus {
        match(diskName: disk.name, diskSHA1: disk.sha1, chdFiles: chdFiles)
    }

    /// `MAMEDisk` overload of the `headerIndex:`-accepting fast path.
    public static func match(disk: MAMEDisk, chdFiles: [URL], headerIndex: CHDHeaderIndex) -> CHDDiskStatus {
        match(diskName: disk.name, diskSHA1: disk.sha1, chdFiles: chdFiles, headerIndex: headerIndex)
    }

    /// Same matching logic, for the general-purpose `DATDisk` model
    /// (`DATGame.disks`) that `AuditReporter`'s own scan pipeline actually
    /// works with — `MAMEDisk` only exists on the `-listxml`-parsing side
    /// and never reaches the audit pipeline itself.
    public static func match(disk: DATDisk, chdFiles: [URL]) -> CHDDiskStatus {
        match(diskName: disk.name, diskSHA1: disk.sha1, chdFiles: chdFiles)
    }

    /// `DATDisk` overload of the `headerIndex:`-accepting fast path —
    /// `DiskAuditor.audit`'s own hot loop.
    public static func match(disk: DATDisk, chdFiles: [URL], headerIndex: CHDHeaderIndex) -> CHDDiskStatus {
        match(diskName: disk.name, diskSHA1: disk.sha1, chdFiles: chdFiles, headerIndex: headerIndex)
    }

    /// Builds a `CHDHeaderIndex` from `chdFiles` on every call — fine for a
    /// one-off lookup (tests, a single disk), but `DiskAuditor.audit` calls
    /// this once per `<disk>` a whole DAT declares, so it uses the
    /// `headerIndex:` overload below with one index built up front instead.
    public static func match(diskName: String, diskSHA1: String?, chdFiles: [URL]) -> CHDDiskStatus {
        match(diskName: diskName, diskSHA1: diskSHA1, chdFiles: chdFiles, headerIndex: CHDHeaderIndex(chdFiles: chdFiles))
    }

    /// Same matching logic as the `chdFiles`-only overload, but reads every
    /// candidate's header from a precomputed `CHDHeaderIndex` instead of
    /// re-opening and re-reading each `.chd` file's header from disk on
    /// every call — see that type's own doc comment for the real O(disks ×
    /// CHD files) hot path this fixes.
    public static func match(diskName: String, diskSHA1: String?, chdFiles: [URL], headerIndex: CHDHeaderIndex) -> CHDDiskStatus {
        guard let expectedSHA1 = diskSHA1 else {
            // Real case found live by jensyleo (2026-08-04): 184 `<disk>`
            // entries in a real MAME 0.288 dump declare no `sha1` at all —
            // undumped media, same real-world pattern as a `nodump` rom.
            // Only findable by name, same reasoning as the rom-side fix.
            if let chdURL = chdFiles.first(where: { $0.deletingPathExtension().lastPathComponent == diskName }) {
                return .unverifiable(chdURL)
            }
            return .missing
        }

        if let chdURL = headerIndex.urls(withSHA1: expectedSHA1).first {
            return .correct(chdURL)
        }

        if let chdURL = chdFiles.first(where: { $0.deletingPathExtension().lastPathComponent == diskName }) {
            return .incorrect(chdURL)
        }
        return .missing
    }
}
