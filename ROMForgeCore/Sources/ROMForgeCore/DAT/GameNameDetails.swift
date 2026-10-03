// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// Everything a No-Intro/Redump-style game name encodes in its parenthesized
/// tags, decoded into labelled facts — `GameNameTagParser` only covers the
/// first region and languages; this covers every tag No-Intro defines.
public struct GameNameDetails: Equatable, Sendable {
    public var regions: [String] = []
    public var languages: [String] = []
    public var revision: String?
    public var version: String?
    /// "Prototype", "Beta", "Sample", "Demo" … `nil` for a retail release.
    public var releaseStage: String?
    public var distribution: [String] = []
    public var flags: [String] = []
    public var otherTags: [String] = []

    /// NTSC/PAL derived from the regions (SNES/NES/Genesis-era hardware).
    public var videoStandard: String? {
        let ntsc: Set<String> = ["usa", "japan", "korea", "canada", "brazil", "taiwan", "hong kong"]
        let pal: Set<String> = ["europe", "australia", "germany", "france", "spain", "italy", "uk", "united kingdom", "sweden", "netherlands", "norway", "denmark", "finland", "russia", "china", "greece", "portugal", "ireland"]
        let lower = Set(regions.map { $0.lowercased() })
        let isNTSC = !lower.isDisjoint(with: ntsc), isPAL = !lower.isDisjoint(with: pal)
        switch (isNTSC, isPAL) {
        case (true, true): return "NTSC / PAL (60 Hz / 50 Hz)"
        case (true, false): return "NTSC (60 Hz)"
        case (false, true): return "PAL (50 Hz)"
        default: return lower.contains("world") ? "NTSC / PAL" : nil
        }
    }

    public static let languageNames: [String: String] = [
        "en": "English", "ja": "Japanese", "fr": "French", "de": "German", "es": "Spanish", "it": "Italian",
        "nl": "Dutch", "pt": "Portuguese", "sv": "Swedish", "no": "Norwegian", "da": "Danish", "fi": "Finnish",
        "zh": "Chinese", "zh-hant": "Chinese (Traditional)", "zh-hans": "Chinese (Simplified)", "ko": "Korean",
        "pl": "Polish", "ru": "Russian", "cs": "Czech", "hu": "Hungarian", "tr": "Turkish", "ar": "Arabic",
        "el": "Greek", "he": "Hebrew",
    ]

    private static let regionNames: Set<String> = [
        "usa", "europe", "japan", "world", "asia", "australia", "brazil", "canada", "china", "denmark", "finland",
        "france", "germany", "greece", "hong kong", "ireland", "italy", "korea", "netherlands", "norway",
        "portugal", "russia", "spain", "sweden", "taiwan", "uk", "united kingdom",
    ]

    public static func parse(name: String) -> GameNameDetails {
        var details = GameNameDetails()
        for group in groups(in: name) {
            let tag = group.trimmingCharacters(in: .whitespaces)
            guard !tag.isEmpty else { continue }
            let lower = tag.lowercased()
            let parts = tag.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.allSatisfy({ regionNames.contains($0.lowercased()) }) { details.regions += parts; continue }
            if parts.allSatisfy({ languageNames[$0.lowercased()] != nil }) {
                details.languages += parts.compactMap { languageNames[$0.lowercased()] }; continue
            }
            if lower.hasPrefix("rev ") { details.revision = String(tag.dropFirst(4)); continue }
            if lower.hasPrefix("v") , tag.dropFirst().first?.isNumber == true { details.version = String(tag.dropFirst()); continue }
            if lower.hasPrefix("proto") { details.releaseStage = ("Prototype" + suffix(of: tag, dropping: 5)); continue }
            if lower.hasPrefix("beta") { details.releaseStage = ("Beta" + suffix(of: tag, dropping: 4)); continue }
            if lower.hasPrefix("sample") { details.releaseStage = "Sample"; continue }
            if lower.hasPrefix("demo") { details.releaseStage = "Demo"; continue }
            if lower.hasPrefix("kiosk") { details.releaseStage = "Kiosk"; continue }
            if lower.hasPrefix("promo") { details.releaseStage = "Promotional"; continue }
            switch lower {
            case "unl": details.flags.append("Unlicensed"); continue
            case "pirate": details.flags.append("Pirate / bootleg"); continue
            case "aftermarket": details.flags.append("Aftermarket (homebrew / post-release)"); continue
            case "alt": details.flags.append("Alternate dump of the same release"); continue
            case "np": details.flags.append("Nintendo Power cartridge (rewritable flash)"); continue
            case "competition cart": details.flags.append("Competition cartridge"); continue
            case "enhancement chip": details.flags.append("Uses an enhancement/coprocessor chip"); continue
            case "sgb enhanced": details.flags.append("Super Game Boy enhanced"); continue
            case "bs": details.flags.append("Satellaview (BS-X) broadcast"); continue
            default: break
            }
            if lower.contains("virtual console") || lower.contains("switch") || lower.contains("classic mini")
                || lower.contains("wii") || lower.contains("e-reader") || lower.contains("collection") {
                details.distribution += parts; continue
            }
            details.otherTags.append(tag)
        }
        return details
    }

    private static func suffix(of tag: String, dropping count: Int) -> String {
        let rest = tag.dropFirst(count).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? "" : " \(rest)"
    }

    private static func groups(in name: String) -> [String] {
        var result: [String] = [], depth = 0, current = ""
        for char in name {
            switch char {
            case "(": depth += 1; if depth == 1 { current = "" }
            case ")": if depth == 1 { result.append(current) }; depth = max(0, depth - 1)
            default: if depth >= 1 { current.append(char) }
            }
        }
        return result
    }
}
