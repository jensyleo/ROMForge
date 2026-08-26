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

/// Abstracts "where does the app's own bundled 7zz engine live, if any" so
/// tests can fake it without depending on `Bundle.main`, which has no
/// "Engine" resource at all when running under `swift test`/xctest.
protocol BundledSevenZipLocating {
    func bundledExecutableURL() -> URL?
}

/// The official `7zz` binary (universal x86_64+arm64), shipped verbatim at
/// `Contents/Resources/Engine/7zz`. `Bundle.main` here resolves to whichever
/// executable is actually running (the App, not this package), so this
/// works correctly even though the lookup is written in ROMForgeCore.
struct RealBundledSevenZipLocator: BundledSevenZipLocating {
    func bundledExecutableURL() -> URL? {
        Bundle.main.url(forResource: "7zz", withExtension: nil, subdirectory: "Engine")
    }
}

/// Finds the `7zz`/`7z` binary to use. First choice is the copy ROMForge
/// ships inside its own `.app` (see `RealBundledSevenZipLocator`) — no
/// install step, works out of the box, same as ZIP (handled entirely
/// in-process via ZIPFoundation). Only falls back to a system-installed copy
/// (Homebrew's `sevenzip` formula, or any other install on `PATH`) when the
/// bundled engine is missing for some reason (e.g. `romforge-cli`, the SPM
/// executable target, has no app bundle to carry one).
public enum SevenZipLocator {
    private static let candidatePaths = [
        "/opt/homebrew/bin/7zz",
        "/usr/local/bin/7zz",
        "/opt/homebrew/bin/7z",
        "/usr/local/bin/7z",
    ]

    public static func locate(fileManager: FileManager = .default) throws -> URL {
        try locate(checker: fileManager, validator: RealSevenZipBinaryValidator(), bundleLocator: RealBundledSevenZipLocator())
    }

    static func locate(checker: ExecutableFileChecking, validator: SevenZipBinaryValidating, bundleLocator: BundledSevenZipLocating = RealBundledSevenZipLocator()) throws -> URL {
        if let bundled = bundleLocator.bundledExecutableURL(),
           checker.isExecutableFile(atPath: bundled.path),
           validator.isOfficial7Zip(at: bundled) {
            return bundled
        }
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
