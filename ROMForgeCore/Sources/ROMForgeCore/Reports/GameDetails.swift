// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// One short badge for the "Details" column — descriptive metadata about
/// the game/machine itself (MAME's own emulation-quality claim, display
/// characteristics, player/coin count), never a dependency the game needs to
/// run (see `DependencyBadge`, the "Dependencies" column's own equivalent,
/// for that separate concept — jensyleo's own decision, 2026-08-28: these
/// two stay separate columns rather than merging under one name, so
/// "Dependencies" keeps meaning exactly what it always has). Built entirely
/// from fields already carried by `AuditEntry`/`GameNode`
/// (`driverStatus`/`displayType`/`displayRotate`/`players`/`coins`), so
/// showing it costs nothing beyond what a scan (or the pre-scan DAT catalog)
/// already computed — no re-scan, no extra I/O. Same shape as
/// `DependencyBadge` — see that type's own doc comment for the "why a bare
/// label, full text in `tooltip`" reasoning, which applies identically here.
public struct DetailBadge: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case driverStatus, display, players
    }

    public let kind: Kind
    public let label: String
    public let tooltip: String

    public var id: String { "\(kind.rawValue):\(label)" }

    public init(kind: Kind, label: String, tooltip: String) {
        self.kind = kind
        self.label = label
        self.tooltip = tooltip
    }
}

extension GameNode {
    /// This game's detail badges, in a fixed display order (Emulation,
    /// Display, Players) — purely informational, never anything that feeds
    /// `AuditStatus`/severity, same as `dependencyBadges`. Empty for the
    /// synthetic "Surplus files" bucket and a CHD disk row (`isDiskRow`) —
    /// neither has real DAT machine metadata of its own to show.
    public var detailBadges: [DetailBadge] {
        guard !isSurplusBucket, !isDiskRow else { return [] }
        var badges: [DetailBadge] = []

        if !driverStatus.isEmpty {
            badges.append(DetailBadge(kind: .driverStatus, label: "Emulation", tooltip: driverStatusTooltip(driverStatus)))
        }

        if let displayTooltip = displayTooltip(type: displayType, rotate: displayRotate) {
            badges.append(DetailBadge(kind: .display, label: "Display", tooltip: displayTooltip))
        }

        if let playersTooltip = playersTooltip(players: players, coins: coins) {
            badges.append(DetailBadge(kind: .players, label: "Players", tooltip: playersTooltip))
        }

        return badges
    }
}

/// MAME's own three-value scale, in the exact words a non-developer reads
/// most easily — "good" stays a bare pass rather than "Good" to avoid
/// reading like this app's own audit verdicts (`AuditStatus`'s "Good"/"Bad"
/// wording), a genuinely different, unrelated concept living right next to
/// it in the same table. Kept out of the badge's own `label` (jensyleo's own
/// correction, 2026-08-28: "igual que en la celda Dependencies" — a bare
/// category word in the chip itself, exactly like "BIOS"/"CHD"/"Hardware"/
/// "Samples" there, with the real value only ever in the tooltip).
private func driverStatusTooltip(_ status: String) -> String {
    switch status {
    case "good": return "MAME driver status: Good"
    case "imperfect": return "MAME driver status: Imperfect"
    case "preliminary": return "MAME driver status: Preliminary"
    default: return "MAME driver status: \(status)"
    }
}

/// Orientation reads more immediately to a non-developer than the raw
/// MAME `rotate` degrees value — the practical question a collector/cabinet
/// owner actually has ("do I need to rotate my monitor for this?"). Only
/// ever shown in the tooltip (see `driverStatusTooltip`'s own doc comment
/// for why), not the badge's bare "Display" label.
private func displayTooltip(type: String, rotate: String) -> String? {
    guard !type.isEmpty || !rotate.isEmpty else { return nil }
    var parts: [String] = []
    switch rotate {
    case "0", "180": parts.append("Orientation: Horizontal")
    case "90", "270": parts.append("Orientation: Vertical")
    default: break
    }
    if !type.isEmpty { parts.append("Type: \(type.capitalized)") }
    return parts.isEmpty ? nil : parts.joined(separator: "\n")
}

private func playersTooltip(players: String, coins: String) -> String? {
    guard !players.isEmpty || !coins.isEmpty else { return nil }
    var parts: [String] = []
    if !players.isEmpty { parts.append(players == "1" ? "1 player" : "\(players) players") }
    if coins == "0" {
        parts.append("Free Play (no coin mechanism)")
    } else if !coins.isEmpty {
        parts.append(coins == "1" ? "1 coin slot" : "\(coins) coin slots")
    }
    return parts.isEmpty ? nil : parts.joined(separator: "\n")
}
