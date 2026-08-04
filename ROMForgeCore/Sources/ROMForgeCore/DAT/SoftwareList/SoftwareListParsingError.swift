// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

public enum SoftwareListParsingError: Error, Equatable, CustomStringConvertible {
    case malformedXML(underlying: String)
    case missingRootElement

    public var description: String {
        switch self {
        case .malformedXML(let underlying):
            return "The software list is not well-formed XML: \(underlying)"
        case .missingRootElement:
            return "The listing has no <softwarelist> root element"
        }
    }
}
