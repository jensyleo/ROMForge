// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("SurplusArchiveKey")
struct SurplusArchiveKeyTests {
    @Test("a full path is used as the key when the entry has one")
    func keyPrefersFullPath() {
        let entry = AuditEntry(status: .unknownFile, game: nil, name: "extra.bin", path: URL(fileURLWithPath: "/roms/neogeo/extra.zip"))
        #expect(SurplusArchiveKey.key(for: entry) == "/roms/neogeo/extra.zip")
    }

    @Test("the entry's own name is used as the key when it has no path")
    func keyFallsBackToName() {
        let entry = AuditEntry(status: .unknownFile, game: nil, name: "extra.bin", path: nil)
        #expect(SurplusArchiveKey.key(for: entry) == "extra.bin")
    }

    @Test("displayName strips a full path down to just its filename")
    func displayNameStripsPath() {
        #expect(SurplusArchiveKey.displayName(forKey: "/roms/neogeo/extra.zip") == "extra.zip")
        #expect(SurplusArchiveKey.displayName(forKey: "extra.bin") == "extra.bin")
    }
}
