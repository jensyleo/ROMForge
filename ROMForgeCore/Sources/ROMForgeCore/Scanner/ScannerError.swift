// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public enum ScannerError: Error, Equatable, CustomStringConvertible {
    case folderNotFound(URL)
    case notADirectory(URL)
    /// The folder being scanned nests deeper than `FolderScanner.maxSubfolderDepth`
    /// allows — jensyleo's own request (2026-08-05): pointing ROMForge at
    /// something far too broad (a whole drive, a home folder) must not
    /// silently try to enumerate everything underneath it. `foundAt` is the
    /// specific subfolder that first exceeded the limit, so the message can
    /// name exactly where to look rather than a bare "too deep" complaint.
    case folderTooDeep(root: URL, foundAt: URL, maxDepth: Int)

    public var description: String {
        switch self {
        case .folderNotFound(let url):
            return "No folder exists at \(url.path)"
        case .notADirectory(let url):
            return "\(url.path) is not a folder"
        case .folderTooDeep(let root, let foundAt, let maxDepth):
            // Shows the full relative chain from `root` down to the
            // offending item, rather than guessing which ONE folder in that
            // chain is "the extra one" — with two nested folders between
            // root and a file (e.g. a `BATOCERA`-style extra subfolder
            // sitting above the real per-game folder), depth alone can't
            // tell which is legitimate and which should be flattened away;
            // only the user looking at the actual names can.
            let relativeComponents = foundAt.standardizedFileURL.pathComponents.dropFirst(root.standardizedFileURL.pathComponents.count)
            let relativePath = relativeComponents.joined(separator: "/")
            return """
            "\(root.lastPathComponent)" has subfolders nested deeper than ROMForge scans (max \(maxDepth) level\(maxDepth == 1 ? "" : "s") of subfolders) — found "\(relativePath)".
            Point ROMForge at a folder shaped like <system>/<game>/<file>, not something with extra nesting underneath — flatten or remove whichever folder in that path isn't a real per-game folder.
            """
        }
    }
}
