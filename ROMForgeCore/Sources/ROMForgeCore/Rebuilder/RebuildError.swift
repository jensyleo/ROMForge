// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

// jensyleo's own instruction (2026-09-10) to review the app's whole
// logging for coherence surfaced a real, systemic gap — see
// `ScannerError`'s own doc comment for the full explanation: this type
// only conformed to `CustomStringConvertible`, so every `error
// .localizedDescription` call anywhere in the app (this is the error
// EVERY write action's own `failureLines` catches) silently produced
// Foundation's generic bridged text instead of the specific reason
// below. Every one of those "Could not rename X: ..." log lines added
// (2026-09-10) to fix the earlier swallowed-error bug would otherwise
// have shown a useless message in place of the real one, defeating the
// whole point of that fix.
public enum RebuildError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case sourceMissing(URL)
    case destinationExists(URL)
    case underlying(String)

    public var description: String {
        switch self {
        case .sourceMissing(let url):
            return "Source file does not exist: \(url.path)"
        case .destinationExists(let url):
            return "Refusing to overwrite existing file: \(url.path)"
        case .underlying(let message):
            return message
        }
    }

    public var errorDescription: String? { description }
}
