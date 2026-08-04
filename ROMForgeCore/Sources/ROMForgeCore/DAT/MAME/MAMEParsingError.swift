// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

public enum MAMEParsingError: Error, Equatable, CustomStringConvertible {
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
}
