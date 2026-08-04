// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("DiskAuditor")
struct DiskAuditorTests {
    private func header() -> DATHeader { DATHeader(name: "Test", description: "Test", version: "1", author: "ROMForge") }

    /// jensyleo's own report (2026-07-30): several clones of the same game
    /// sharing one unmodified physical disk (MAME's own `cloneof`
    /// hierarchy — a region/revision variant, program rom changed, CD/HD
    /// image untouched) each declare a `<disk>` with the identical
    /// name+sha1, and used to produce one audit row *per clone*, not one
    /// per actual distinct disk — four rows all named "cap-sf3-3.chd" for
    /// four different Street Fighter III 3rd Strike clones, in the real
    /// case that surfaced this.
    @Test("multiple clones declaring the identical disk (same name+sha1) produce only one audit entry")
    func dedupesIdenticalDiskAcrossClones() {
        let sharedDisk = DATDisk(name: "cap-sf3-3", sha1: "1111111111111111111111111111111111111111")
        let dat = DATFile(
            header: header(),
            games: [
                DATGame(name: "sfiii", description: "Street Fighter III: New Generation (parent)", cloneOf: nil, romOf: nil, roms: [], disks: [sharedDisk]),
                DATGame(name: "sfiiij", description: "Street Fighter III: New Generation (Japan)", cloneOf: "sfiii", romOf: "sfiii", roms: [], disks: [sharedDisk]),
                DATGame(name: "sfiiiu", description: "Street Fighter III: New Generation (US)", cloneOf: "sfiii", romOf: "sfiii", roms: [], disks: [sharedDisk]),
            ]
        )

        let entries = DiskAuditor.audit(dat: dat, chdFiles: [])
        #expect(entries.count == 1)
        #expect(entries[0].game == "sfiii")
        #expect(entries[0].status == .missing)
    }

    @Test("clones that declare genuinely different disks (different sha1) each get their own entry")
    func doesNotDedupeGenuinelyDifferentDisks() {
        let dat = DATFile(
            header: header(),
            games: [
                DATGame(
                    name: "sfiii3", description: "3rd Strike (rev A)", cloneOf: nil, romOf: nil, roms: [],
                    disks: [DATDisk(name: "cap-33s-1", sha1: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")]
                ),
                DATGame(
                    name: "sfiii3a", description: "3rd Strike (rev B)", cloneOf: "sfiii3", romOf: "sfiii3", roms: [],
                    disks: [DATDisk(name: "cap-33s-2", sha1: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")]
                ),
            ]
        )

        let entries = DiskAuditor.audit(dat: dat, chdFiles: [])
        #expect(entries.count == 2)
        #expect(Set(entries.map(\.name)) == ["cap-33s-1", "cap-33s-2"])
    }

    @Test("every disk entry is marked isDisk")
    func marksEveryEntryAsDisk() {
        let dat = DATFile(
            header: header(),
            games: [DATGame(name: "g", description: "G", cloneOf: nil, romOf: nil, roms: [], disks: [DATDisk(name: "g", sha1: nil)])]
        )
        let entries = DiskAuditor.audit(dat: dat, chdFiles: [])
        #expect(entries.allSatisfy { $0.isDisk })
    }
}
