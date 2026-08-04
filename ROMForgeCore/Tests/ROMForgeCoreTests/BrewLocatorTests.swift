// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

private struct FakeExecutableChecker: ExecutableFileChecking {
    let executablePaths: Set<String>
    func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }
}

@Suite("BrewLocator")
struct BrewLocatorTests {
    @Test("finds brew at the first known path")
    func findsBrewAtKnownPath() throws {
        let checker = FakeExecutableChecker(executablePaths: ["/opt/homebrew/bin/brew"])
        #expect(try BrewLocator.locate(checker: checker).path == "/opt/homebrew/bin/brew")
    }

    @Test("throws homebrewNotFound with instructions when brew is not installed")
    func throwsWhenBrewMissing() {
        let checker = FakeExecutableChecker(executablePaths: [])
        #expect(throws: SevenZipError.homebrewNotFound) {
            try BrewLocator.locate(checker: checker)
        }
        #expect(SevenZipError.homebrewNotFound.description.contains("brew.sh"))
    }
}
