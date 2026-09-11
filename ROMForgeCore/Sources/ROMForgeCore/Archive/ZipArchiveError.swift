// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

// jensyleo's own instruction (2026-09-10) to review the app's whole
// logging for coherence — same systemic gap as `RebuildError`/`ScannerError`
// (see their own doc comments): this type only conformed to
// `CustomStringConvertible`, so any `error.localizedDescription` call
// would silently fall back to Foundation's generic bridged text instead of
// the specific `description` below. `errorDescription` fixes it at the
// source.
public enum ZipArchiveError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case cannotOpenArchive(URL)
    case entryNotFound(entryPath: String, archiveURL: URL)
    case extractionFailed(String)
    case creationFailed(String)
    /// The entry decompressed to far more bytes than its own declared
    /// (attacker-controlled) size claimed — a zip-bomb guard, not a normal
    /// extraction failure. See `ZipArchiveHasher`.
    case suspectedZipBomb(entryPath: String, declaredSize: Int64)

    public var description: String {
        switch self {
        case .cannotOpenArchive(let url):
            return "Could not open ZIP archive at \(url.path)"
        case .entryNotFound(let entryPath, let archiveURL):
            return "Entry \"\(entryPath)\" not found in \(archiveURL.path)"
        case .extractionFailed(let message):
            return "Failed to extract entry: \(message)"
        case .creationFailed(let message):
            return "Failed to create ZIP archive: \(message)"
        case .suspectedZipBomb(let entryPath, let declaredSize):
            return "Entry \"\(entryPath)\" decompressed to far more than its declared size (\(declaredSize) bytes) — aborted as a suspected zip bomb"
        }
    }

    public var errorDescription: String? { description }
}
