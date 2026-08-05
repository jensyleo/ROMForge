// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public enum ScannerError: Error, Equatable, CustomStringConvertible {
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
}
