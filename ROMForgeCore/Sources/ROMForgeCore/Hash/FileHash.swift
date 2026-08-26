// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// The hashes DAT tools compare against, all lowercase hex — `nil` for
/// whichever algorithm `HashAlgorithms` said not to bother computing, not
/// for "unknown"/an error: every file gets at least one non-nil field
/// (`HashAlgorithms` always keeps at least one algorithm enabled).
public struct FileHash: Equatable, Sendable, Codable {
    public let crc32: String?
    public let md5: String?
    public let sha1: String?

    public init(crc32: String?, md5: String?, sha1: String?) {
        self.crc32 = crc32
        self.md5 = md5
        self.sha1 = sha1
    }
}

public enum HasherError: Error, Equatable, CustomStringConvertible {
    case cannotOpenFile(URL)

    public var description: String {
        switch self {
        case .cannotOpenFile(let url):
            return "Could not open \(url.path) for reading"
        }
    }
}
