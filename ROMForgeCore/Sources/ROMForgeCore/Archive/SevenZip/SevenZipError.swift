// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public enum SevenZipError: Error, Equatable, CustomStringConvertible {
    /// No binary identifying itself as the official 7-Zip
    /// (https://www.7-zip.org) was found on this system — either nothing was
    /// there, or something else was found under that name and rejected.
    /// Unlike ZIP, 7z support depends on the official 7-Zip being installed;
    /// ROMForge does not bundle it and does not accept unofficial forks.
    case binaryNotFound
    case cannotOpenArchive(URL)
    case entryNotFound(entryPath: String, archiveURL: URL)
    case processFailed(String)
    case malformedListing(String)

    public var description: String {
        switch self {
        case .binaryNotFound:
            return """
            The official 7-Zip (https://www.7-zip.org) was not found on this \
            system. ROMForge needs its "7zz" (or "7z") command-line tool to \
            read .7z archives, and only accepts the official build — not an \
            unofficial fork.

            Install it with Homebrew (the "sevenzip" formula builds from the \
            official 7-zip.org source):
                brew install sevenzip

            Or download it directly from the 7-Zip website:
                https://www.7-zip.org/download.html
            ("7-Zip for MacOS: console version")

            Then try again.
            """
        case .cannotOpenArchive(let url):
            return "Could not open 7z archive at \(url.path)"
        case .entryNotFound(let entryPath, let archiveURL):
            return "Entry \"\(entryPath)\" not found in \(archiveURL.path)"
        case .processFailed(let message):
            return "7-Zip failed: \(message)"
        case .malformedListing(let message):
            return "Could not parse 7-Zip listing output: \(message)"
        }
    }
}
