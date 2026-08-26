// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Shared `$PATH`-scanning logic used by `SevenZipLocator`.
enum PathEnvironmentResolver {
    static func resolve(name: String, checker: ExecutableFileChecking) -> URL? {
        guard let pathVariable = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for directory in pathVariable.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if checker.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
