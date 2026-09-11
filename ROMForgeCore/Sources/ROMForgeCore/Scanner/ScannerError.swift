// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

// jensyleo's own instruction (2026-09-10) to review the app's whole
// logging for coherence surfaced a real, systemic gap: this type only
// conformed to `CustomStringConvertible`, never `LocalizedError` — so
// EVERY `error.localizedDescription` call anywhere in the app, on any
// error that turned out to be a `ScannerError`, silently fell back to
// Foundation's generic bridged text ("The operation couldn't be
// completed...") instead of the actual, helpful `description` written
// below. `LocalizedError.errorDescription` is exactly what
// `.localizedDescription` consults FIRST for a plain Swift error — adding
// it (mirroring `description`) fixes every existing and future call site
// at the source, rather than patching each one to remember to call
// `description`/`String(describing:)` instead.
public enum ScannerError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case folderNotFound(URL)
    case notADirectory(URL)

    public var description: String {
        switch self {
        case .folderNotFound(let url):
            return "No folder exists at \(url.path)"
        case .notADirectory(let url):
            return "\(url.path) is not a folder"
        }
    }

    public var errorDescription: String? { description }
}
