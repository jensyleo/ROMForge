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
public enum DATParsingError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case malformedXML(underlying: String)
    case missingRootElement
    case missingHeader
    case missingRomAttribute(game: String, attribute: String)

    public var description: String {
        switch self {
        case .malformedXML(let underlying):
            return "The DAT is not well-formed XML: \(underlying)"
        case .missingRootElement:
            return "The DAT has no <datafile> root element"
        case .missingHeader:
            return "The DAT has no <header> element"
        case .missingRomAttribute(let game, let attribute):
            return "Game \"\(game)\" has a <rom> missing required attribute \"\(attribute)\""
        }
    }

    public var errorDescription: String? { description }
}
