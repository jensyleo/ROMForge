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

private struct FakeValidator: SevenZipBinaryValidating {
    let officialPaths: Set<String>
    func isOfficial7Zip(at url: URL) -> Bool {
        officialPaths.contains(url.path)
    }
}

private struct FakeBundleLocator: BundledSevenZipLocating {
    let url: URL?
    func bundledExecutableURL() -> URL? { url }
}

@Suite("SevenZipLocator")
struct SevenZipLocatorTests {
    @Test("finds 7zz at the first known Homebrew path when it identifies as official")
    func findsBinaryAtKnownPath() throws {
        let checker = FakeExecutableChecker(executablePaths: ["/opt/homebrew/bin/7zz"])
        let validator = FakeValidator(officialPaths: ["/opt/homebrew/bin/7zz"])
        let url = try SevenZipLocator.locate(checker: checker, validator: validator)
        #expect(url.path == "/opt/homebrew/bin/7zz")
    }

    @Test("falls back to 7z when 7zz is not present")
    func fallsBackToPlain7z() throws {
        let checker = FakeExecutableChecker(executablePaths: ["/usr/local/bin/7z"])
        let validator = FakeValidator(officialPaths: ["/usr/local/bin/7z"])
        let url = try SevenZipLocator.locate(checker: checker, validator: validator)
        #expect(url.path == "/usr/local/bin/7z")
    }

    @Test("rejects a binary at a known path that does not identify as official 7-Zip")
    func rejectsUnofficialBinaryAtKnownPath() {
        // Something named 7zz exists at the well-known path, but it doesn't
        // pass the banner check — must not be accepted just because the name matches.
        let checker = FakeExecutableChecker(executablePaths: ["/opt/homebrew/bin/7zz"])
        let validator = FakeValidator(officialPaths: [])
        #expect(throws: SevenZipError.binaryNotFound) {
            try SevenZipLocator.locate(checker: checker, validator: validator)
        }
    }

    @Test("throws binaryNotFound with install instructions pointing to the official 7-zip.org build")
    func throwsWithInstallInstructionsWhenMissing() {
        let checker = FakeExecutableChecker(executablePaths: [])
        let validator = FakeValidator(officialPaths: [])
        #expect(throws: SevenZipError.binaryNotFound) {
            try SevenZipLocator.locate(checker: checker, validator: validator)
        }
        let message = SevenZipError.binaryNotFound.description
        #expect(message.contains("brew install sevenzip"))
        #expect(message.contains("https://www.7-zip.org"))
    }

    @Test("prefers the app's own bundled engine over any system install, when it validates as official")
    func prefersBundledEngineOverSystemInstall() throws {
        let bundled = URL(fileURLWithPath: "/Applications/ROMForge.app/Contents/Resources/Engine/7zz")
        let checker = FakeExecutableChecker(executablePaths: [bundled.path, "/opt/homebrew/bin/7zz"])
        let validator = FakeValidator(officialPaths: [bundled.path, "/opt/homebrew/bin/7zz"])
        let bundleLocator = FakeBundleLocator(url: bundled)
        let url = try SevenZipLocator.locate(checker: checker, validator: validator, bundleLocator: bundleLocator)
        #expect(url.path == bundled.path)
    }

    @Test("falls back to a system install when the bundled engine doesn't validate as official")
    func fallsBackWhenBundledEngineIsNotOfficial() throws {
        // e.g. a corrupted or tampered bundled binary — must not be trusted
        // just because it's the one shipped inside the app.
        let bundled = URL(fileURLWithPath: "/Applications/ROMForge.app/Contents/Resources/Engine/7zz")
        let checker = FakeExecutableChecker(executablePaths: [bundled.path, "/opt/homebrew/bin/7zz"])
        let validator = FakeValidator(officialPaths: ["/opt/homebrew/bin/7zz"])
        let bundleLocator = FakeBundleLocator(url: bundled)
        let url = try SevenZipLocator.locate(checker: checker, validator: validator, bundleLocator: bundleLocator)
        #expect(url.path == "/opt/homebrew/bin/7zz")
    }
}
