// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public enum RebuildError: Error, Equatable, CustomStringConvertible {
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
}
