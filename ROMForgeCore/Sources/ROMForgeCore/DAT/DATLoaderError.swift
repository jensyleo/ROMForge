// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

public enum DATLoaderError: Error, Equatable, CustomStringConvertible {
    /// None of the three supported dialects (Logiqx/ClrMamePro, MAME
    /// `-listxml`, MAME software list) could make sense of the file.
    case unrecognizedFormat(logiqxError: String, mameError: String, softwareListError: String)

    public var description: String {
        switch self {
        case .unrecognizedFormat(let logiqxError, let mameError, let softwareListError):
            return """
            Not a recognized DAT format.
            As Logiqx/ClrMamePro XML: \(logiqxError)
            As MAME -listxml: \(mameError)
            As MAME software list: \(softwareListError)
            """
        }
    }
}
