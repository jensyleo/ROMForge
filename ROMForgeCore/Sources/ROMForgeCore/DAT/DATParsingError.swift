// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public enum DATParsingError: Error, Equatable, CustomStringConvertible {
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
}
