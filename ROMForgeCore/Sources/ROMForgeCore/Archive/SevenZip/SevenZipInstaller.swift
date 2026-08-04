// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Installs the official 7-Zip via Homebrew, for callers (the future UI)
/// that want to offer a one-click install instead of just showing
/// instructions. The formula name is hardcoded and never built from user
/// input, so this can only ever install Homebrew's `sevenzip` — the formula
/// confirmed to build from the official https://www.7-zip.org source — and
/// nothing else. Runs synchronously; callers should invoke off the main
/// thread and gate it behind explicit user confirmation, since it changes
/// system state.
public enum SevenZipInstaller {
    public static func installViaHomebrew(fileManager: FileManager = .default) throws -> URL {
        let brew = try BrewLocator.locate(fileManager: fileManager)
        do {
            _ = try SevenZipRunner.run(executableURL: brew, arguments: ["install", "sevenzip"])
        } catch let error as SevenZipError {
            if case .processFailed(let message) = error {
                throw SevenZipError.installationFailed(message)
            }
            throw error
        }
        return try SevenZipLocator.locate(fileManager: fileManager)
    }
}
