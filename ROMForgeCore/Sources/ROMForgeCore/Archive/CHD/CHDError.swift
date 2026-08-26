// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public enum CHDError: Error, Equatable, CustomStringConvertible {
    case cannotOpenFile(URL)
    case notAValidCHD(URL)
    case unsupportedVersion(UInt32, URL)

    public var description: String {
        switch self {
        case .cannotOpenFile(let url):
            return "Could not open \(url.path) for reading"
        case .notAValidCHD(let url):
            return "\(url.path) is not a CHD file (missing or truncated \"MComprHD\" header)"
        case .unsupportedVersion(let version, let url):
            return "\(url.path) is CHD header version \(version) — only version 5 is supported"
        }
    }
}
