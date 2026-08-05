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

    /// Same matching logic, for the general-purpose `DATDisk` model
    /// (`DATGame.disks`) that `AuditReporter`'s own scan pipeline actually
    /// works with — `MAMEDisk` only exists on the `-listxml`-parsing side
    /// and never reaches the audit pipeline itself.
    public static func match(disk: DATDisk, chdFiles: [URL]) -> CHDDiskStatus {
        match(diskName: disk.name, diskSHA1: disk.sha1, chdFiles: chdFiles)
    }

    public static func match(diskName: String, diskSHA1: String?, chdFiles: [URL]) -> CHDDiskStatus {
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

        for chdURL in chdFiles {
            guard let header = try? CHDHeaderReader.read(contentsOf: chdURL) else { continue }
            if header.sha1 == expectedSHA1 {
                return .correct(chdURL)
            }
        }

        if let chdURL = chdFiles.first(where: { $0.deletingPathExtension().lastPathComponent == diskName }) {
            return .incorrect(chdURL)
        }
        return .missing
    }
}
