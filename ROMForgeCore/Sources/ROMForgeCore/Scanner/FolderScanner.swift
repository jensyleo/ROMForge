// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Recursively walks a folder and lists its loose (uncompressed) files.
/// Archive scanning (ZIP/7z/CHD) is handled by dedicated scanners added later.
public enum FolderScanner {
    /// How many levels of subfolder ROMForge will descend into below the
    /// folder a system actually configures — jensyleo's own request
    /// (2026-08-05): pointing this at something far too broad (a whole
    /// drive, `~`) must never silently try to enumerate everything
    /// underneath it. `1` covers every real convention already in use in
    /// this project's own testing (`<system>/<game>/<file>` — one game
    /// subfolder per archive/CHD) without covering "the entire disk".
    ///
    /// A folder nesting deeper than this (e.g. an extra `BATOCERA`-style
    /// subfolder above the game level) does NOT abort the whole scan —
    /// jensyleo's own correction (2026-08-05) after trying the stricter,
    /// throw-and-refuse-everything behavior live: that made an otherwise
    /// perfectly scannable folder (only ONE subtree inside it happened to
    /// nest too deep) completely unusable until reorganized. `onSkippedTooDeep`
    /// (below) is called once per offending subfolder instead — its
    /// contents are simply never looked at, everything else in the folder
    /// still scans normally.
    public static let maxSubfolderDepth = 1

    /// - Parameter onFileFound: reports the running count of regular files
    ///   found so far, throttled to roughly every 200 files (plus always a
    ///   final call) — directory enumeration doesn't know its total ahead of
    ///   time, so unlike hashing's completed/total progress this is just a
    ///   live count, but it's still the only feedback available during what
    ///   can otherwise be a long silent pause for a folder with tens of
    ///   thousands of entries before hashing even starts.
    /// - Parameter onSkippedTooDeep: called once per subfolder whose own
    ///   contents sit deeper than `maxSubfolderDepth` allows — its
    ///   descendants are never enumerated at all (not merely filtered out
    ///   afterward), so a folder shaped like a whole drive doesn't pay the
    ///   cost of walking it just to discard the result. The path passed is
    ///   the exact subfolder whose contents got skipped (relative depth
    ///   `maxSubfolderDepth`), not a guess at which ancestor is "the real
    ///   extra one" — depth alone can't tell that when more than one
    ///   folder is nested between the scan root and it.
    public static func scan(folder url: URL, onFileFound: (@Sendable (Int) -> Void)? = nil, onSkippedTooDeep: (@Sendable (URL) -> Void)? = nil) throws -> [ScannedFile] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ScannerError.folderNotFound(url)
        }
        guard isDirectory.boolValue else {
            throw ScannerError.notADirectory(url)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        // Counted in path components below `url` itself — a direct child
        // (loose file OR game subfolder) is depth 0; that subfolder's own
        // contents are depth 1. `maxSubfolderDepth` (1) means "one level of
        // subfolder is fine" (the common `<game>/<file>` convention), not
        // "one level total".
        let rootComponentCount = url.standardizedFileURL.pathComponents.count

        var files: [ScannedFile] = []
        for case let itemURL as URL in enumerator {
            let depth = itemURL.standardizedFileURL.pathComponents.count - rootComponentCount - 1
            let values = try itemURL.resourceValues(
                forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]
            )
            // jensyleo's own report (2026-08-26, security audit): `.isRegularFileKey`/
            // `.isDirectoryKey` follow a symlink to whatever it points at (matching
            // POSIX `stat()`, not `lstat()`), so a symlink planted inside a scanned
            // ROM folder — e.g. from an untrusted downloaded "ROM set" archive —
            // used to be silently followed: its target's content got hashed and its
            // size/hash surfaced in the audit UI/exported reports, regardless of
            // where on disk that target actually lives. `.isSymbolicLinkKey` is the
            // one resource value that reports on the link itself rather than its
            // target, so it's checked first and unconditionally skipped — for a
            // symlinked directory, before ever descending into whatever it points
            // at, exactly like the too-deep case right below it.
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            // A directory sitting exactly at `maxSubfolderDepth` is itself
            // fine (it's the allowed subfolder level), but its own contents
            // would be one level too deep — skipped here, before ever
            // descending into it, rather than filtering out each of
            // possibly many files inside it one at a time afterward.
            if values.isDirectory == true, depth == maxSubfolderDepth {
                onSkippedTooDeep?(itemURL)
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            files.append(
                ScannedFile(
                    url: itemURL,
                    name: itemURL.lastPathComponent,
                    size: Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
                )
            )
            if files.count % 200 == 0 {
                try Task.checkCancellation()
                onFileFound?(files.count)
            }
        }
        try Task.checkCancellation()
        onFileFound?(files.count)
        return files
    }

    /// Scans several folders and concatenates their loose files — a
    /// collection split across multiple folders (different drives, region
    /// subfolders, etc.) is common. `onFileFound` reports one continuous
    /// running count across all folders, not one that resets per folder.
    public static func scan(folders urls: [URL], onFileFound: (@Sendable (Int) -> Void)? = nil, onSkippedTooDeep: (@Sendable (URL) -> Void)? = nil) throws -> [ScannedFile] {
        var all: [ScannedFile] = []
        for url in urls {
            let alreadyFound = all.count
            let files = try scan(folder: url, onFileFound: { count in onFileFound?(alreadyFound + count) }, onSkippedTooDeep: onSkippedTooDeep)
            all.append(contentsOf: files)
        }
        return all
    }

    /// A single loose file's `ScannedFile` record — same shape a folder
    /// walk would have produced for it, just for one file directly rather
    /// than everything underneath a directory. Lets a caller re-scan one
    /// specific archive/file (e.g. "just this one game's zip" from a
    /// right-click) without having to re-walk its entire containing folder.
    public static func scanSingleFile(_ url: URL) throws -> ScannedFile {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ScannerError.folderNotFound(url)
        }
        guard !isDirectory.boolValue else {
            throw ScannerError.notADirectory(url)
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        return ScannedFile(
            url: url,
            name: url.lastPathComponent,
            size: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        )
    }

    /// Like `scan(folders:)`, but each path may be either a whole folder
    /// (walked recursively, as before) or a single file (scanned directly,
    /// via `scanSingleFile`) — lets one rescan mix "this whole folder" and
    /// "just this one archive" scopes together rather than requiring
    /// everything passed in to be a directory.
    ///
    /// - Parameter onFolderStarted: called once per top-level `url` in
    ///   `urls`, right before it starts being walked — jensyleo's own
    ///   request (2026-08-12): a multi-folder scan ("Scan All Folders")
    ///   used to report only a running file COUNT across every folder
    ///   combined, with no way to tell which folder that count was even
    ///   coming from. Fires for a single-file entry too (immediately, since
    ///   there's nothing to "walk"), so the caller's own progress display
    ///   can treat every entry in `urls` uniformly.
    public static func scan(
        paths urls: [URL], onFileFound: (@Sendable (Int) -> Void)? = nil, onSkippedTooDeep: (@Sendable (URL) -> Void)? = nil,
        onFolderStarted: (@Sendable (URL) -> Void)? = nil
    ) throws -> [ScannedFile] {
        var all: [ScannedFile] = []
        for url in urls {
            onFolderStarted?(url)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw ScannerError.folderNotFound(url)
            }
            if isDirectory.boolValue {
                let alreadyFound = all.count
                let files = try scan(folder: url, onFileFound: { count in onFileFound?(alreadyFound + count) }, onSkippedTooDeep: onSkippedTooDeep)
                all.append(contentsOf: files)
            } else {
                all.append(try scanSingleFile(url))
                onFileFound?(all.count)
            }
        }
        return all
    }
}
