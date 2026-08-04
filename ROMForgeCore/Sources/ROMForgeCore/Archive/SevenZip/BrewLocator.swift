// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Finds the Homebrew executable itself, so `SevenZipInstaller` can shell
/// out to it. Only used to run the hardcoded `install sevenzip` command —
/// never anything else.
enum BrewLocator {
    private static let candidatePaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    static func locate(fileManager: FileManager = .default) throws -> URL {
        try locate(checker: fileManager)
    }

    static func locate(checker: ExecutableFileChecking) throws -> URL {
        for path in candidatePaths where checker.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let resolved = PathEnvironmentResolver.resolve(name: "brew", checker: checker) {
            return resolved
        }
        throw SevenZipError.homebrewNotFound
    }
}
