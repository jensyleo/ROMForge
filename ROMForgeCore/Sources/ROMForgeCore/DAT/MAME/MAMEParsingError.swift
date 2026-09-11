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
public enum MAMEParsingError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case malformedXML(underlying: String)
    case missingRootElement
    case missingRomAttribute(machine: String, attribute: String)

    public var description: String {
        switch self {
        case .malformedXML(let underlying):
            return "The MAME listing is not well-formed XML: \(underlying)"
        case .missingRootElement:
            return "The listing has no <mame> root element"
        case .missingRomAttribute(let machine, let attribute):
            return "Machine \"\(machine)\" has a <rom> missing required attribute \"\(attribute)\""
        }
    }

    public var errorDescription: String? { description }
}
