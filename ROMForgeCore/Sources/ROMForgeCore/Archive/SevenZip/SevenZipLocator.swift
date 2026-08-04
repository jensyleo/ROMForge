// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Abstracts "is this path an executable file" so tests can fake it without
/// depending on what's actually installed on the machine running them.
protocol ExecutableFileChecking {
    func isExecutableFile(atPath path: String) -> Bool
}

extension FileManager: ExecutableFileChecking {}

/// Confirms a candidate binary is genuinely the official 7-Zip
/// (https://www.7-zip.org) — not merely a file that happens to be named
/// `7zz`/`7z`.
protocol SevenZipBinaryValidating {
    func isOfficial7Zip(at url: URL) -> Bool
}

/// Runs the candidate with no arguments and checks its banner. The official
/// build always prints a line like
/// "7-Zip 26.02 (arm64) : Copyright (c) 1999-2026 Igor Pavlov : 2026-01-01",
/// which a same-named but unrelated binary would not produce.
struct RealSevenZipBinaryValidator: SevenZipBinaryValidating {
    func isOfficial7Zip(at url: URL) -> Bool {
        guard let output = SevenZipRunner.captureOutputIgnoringExitCode(executableURL: url, arguments: []),
              let banner = String(data: output, encoding: .utf8) else {
            return false
        }
        return banner.contains("7-Zip") && banner.contains("Igor Pavlov")
    }
}

/// Finds the system's `7zz`/`7z` binary. ROMForge does not bundle 7-Zip —
/// unlike ZIP (handled entirely in-process via ZIPFoundation), 7z support
/// depends on the user having the official 7-Zip (https://www.7-zip.org)
/// installed, and only the official build is accepted.
public enum SevenZipLocator {
    private static let candidatePaths = [
        "/opt/homebrew/bin/7zz",
        "/usr/local/bin/7zz",
        "/opt/homebrew/bin/7z",
        "/usr/local/bin/7z",
    ]

    public static func locate(fileManager: FileManager = .default) throws -> URL {
        try locate(checker: fileManager, validator: RealSevenZipBinaryValidator())
    }

    static func locate(checker: ExecutableFileChecking, validator: SevenZipBinaryValidating) throws -> URL {
        for path in candidatePaths where checker.isExecutableFile(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if validator.isOfficial7Zip(at: url) {
                return url
            }
        }
        for name in ["7zz", "7z"] {
            if let resolved = PathEnvironmentResolver.resolve(name: name, checker: checker), validator.isOfficial7Zip(at: resolved) {
                return resolved
            }
        }
        throw SevenZipError.binaryNotFound
    }
}
