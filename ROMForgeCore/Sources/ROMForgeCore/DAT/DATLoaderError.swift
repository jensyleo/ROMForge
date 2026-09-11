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
public enum DATLoaderError: Error, Equatable, CustomStringConvertible, LocalizedError {
    /// None of the three supported dialects (Logiqx/ClrMamePro, MAME
    /// `-listxml`, MAME software list) could make sense of the file.
    case unrecognizedFormat(logiqxError: String, mameError: String, softwareListError: String)

    public var description: String {
        switch self {
        case .unrecognizedFormat(let logiqxError, let mameError, let softwareListError):
            return """
            Not a recognized DAT format.
            As Logiqx/ClrMamePro XML: \(logiqxError)
            As MAME -listxml: \(mameError)
            As MAME software list: \(softwareListError)
            """
        }
    }

    public var errorDescription: String? { description }
}
