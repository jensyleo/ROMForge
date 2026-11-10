// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// What a Nintendo Switch file is, read from the Title ID its name carries
/// (`[0100000000010800]` or `(0100000000010800)`): the ID ends in `000` for
/// the base game, `800` for an update, and anything else is add-on content.
public enum SwitchTitleKind: Equatable, Sendable {
    case base
    /// `version` is the raw `[v…]` number from the name, when there is one.
    case update(version: Int?)
    /// `name` is the add-on's own name when the file name states one.
    case dlc(name: String?)

    public init?(fileName: String) {
        guard let titleID = Self.titleID(in: fileName) else { return nil }
        if titleID.hasSuffix("000") {
            self = .base
        } else if titleID.hasSuffix("800") {
            self = .update(version: Self.version(in: fileName, excluding: titleID))
        } else {
            self = .dlc(name: Self.dlcName(in: fileName, excluding: titleID))
        }
    }

    /// Base first, then the update, then add-on content.
    public var sortRank: Int {
        switch self {
        case .base: return 0
        case .update: return 1
        case .dlc: return 2
        }
    }

    /// "Base", "Update 6" (the 6th update: Switch versions count in steps of
    /// 65536), "Update v123" for a number outside that scheme, or "DLC".
    public var label: String {
        switch self {
        case .base: return "Base"
        case .dlc(let name): return name.map { "DLC: \($0)" } ?? "DLC"
        case .update(let version):
            guard let version, version > 0 else { return "Update" }
            return version % 65536 == 0 ? "Update \(version / 65536)" : "Update v\(version)"
        }
    }

    /// The 16-hex-digit Title ID inside brackets or parentheses, uppercased.
    static func titleID(in fileName: String) -> String? {
        guard let match = fileName.range(of: #"[\[(]0100[0-9A-Fa-f]{12}[\])]"#, options: .regularExpression) else { return nil }
        return String(fileName[match].dropFirst().dropLast()).uppercased()
    }

    /// The add-on's name from the bracket that describes it, e.g. `[DLC Pack 1]`
    /// or `[Game Name Season Pass]`, without the game's own name or a "DLC" tag.
    static func dlcName(in fileName: String, excluding titleID: String) -> String? {
        let game = fileName.prefix { $0 != "[" && $0 != "(" }.trimmingCharacters(in: .whitespaces)
        var best: String?
        var searchRange = fileName.startIndex..<fileName.endIndex
        while let match = fileName.range(of: #"\[[^\]]+\]"#, options: .regularExpression, range: searchRange) {
            searchRange = match.upperBound..<fileName.endIndex
            var text = String(fileName[match].dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            guard text.caseInsensitiveCompare(titleID) != .orderedSame,
                  text.range(of: #"^(v?\d+|[A-Z]{2,3}|base|upd.*|app|dlc|nsp|eshop|cr-\d+|\d+dlc|[\d.]+a?)$"#, options: [.regularExpression, .caseInsensitive]) == nil,
                  text.range(of: "nsw2u|taodung|switch-xci", options: [.regularExpression, .caseInsensitive]) == nil else { continue }
            if !game.isEmpty, text.lowercased().hasPrefix(game.lowercased()) { text = String(text.dropFirst(game.count)) }
            text = text.replacingOccurrences(of: #"^[\s:-]*(DLC\s+)?"#, with: "", options: [.regularExpression, .caseInsensitive])
            text = text.replacingOccurrences(of: #"\s+DLC$"#, with: "", options: [.regularExpression, .caseInsensitive])
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: " -:"))
            if !text.isEmpty, text.count > (best?.count ?? 0) { best = text }
        }
        return best
    }

    /// The largest `[v123]`/`[123]`/`(v123)` number in the name, ignoring the Title ID itself.
    static func version(in fileName: String, excluding titleID: String) -> Int? {
        let rest = fileName.replacingOccurrences(of: titleID, with: "", options: .caseInsensitive)
        var best: Int?
        var searchRange = rest.startIndex..<rest.endIndex
        while let match = rest.range(of: #"[\[(]v?\d+[\])]"#, options: .regularExpression, range: searchRange) {
            let digits = rest[match].filter(\.isNumber)
            if let value = Int(digits) { best = max(best ?? 0, value) }
            searchRange = match.upperBound..<rest.endIndex
        }
        return best
    }
}

/// One line about a Switch game for the Games table: which update it has,
/// whether a newer one is published, and how many DLC files it holds.
public enum SwitchGameSummary {
    /// `files` are the game's roms as the DAT lists them; `isPresent` is false
    /// for one the collection lacks. Nil when there is nothing to say.
    public static func text(files: [(name: String, isPresent: Bool)]) -> String? {
        var ownedUpdate: Int?
        var missingUpdate: Int?
        var hasOwnedUpdate = false
        var dlcCount = 0
        for file in files {
            switch SwitchTitleKind(fileName: file.name) {
            case .update(let version)?:
                if file.isPresent {
                    hasOwnedUpdate = true
                    ownedUpdate = max(ownedUpdate ?? 0, version ?? 0)
                } else {
                    missingUpdate = max(missingUpdate ?? 0, version ?? 0)
                }
            case .dlc?:
                if file.isPresent { dlcCount += 1 }
            case .base?, nil:
                break
            }
        }
        var parts: [String] = []
        if let missingUpdate {
            let have = hasOwnedUpdate ? "have \(number(ownedUpdate ?? 0))" : "none installed"
            parts.append("Update \(number(missingUpdate)) available (\(have))")
        } else if hasOwnedUpdate {
            parts.append(SwitchTitleKind.update(version: ownedUpdate).label)
        }
        if dlcCount > 0 { parts.append("\(dlcCount) DLC") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func number(_ version: Int) -> String {
        version > 0 && version % 65536 == 0 ? String(version / 65536) : "v\(version)"
    }
}
