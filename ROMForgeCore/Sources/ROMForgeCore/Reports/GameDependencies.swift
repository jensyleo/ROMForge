// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// One short badge for the "Dependencies" column — purely informational,
/// like `ParentCloneSummary`'s family indicator: never a new `AuditStatus`,
/// never anything that feeds severity. Built entirely from fields
/// `AuditEntry`/`GameNode` already carry (`requiredBiosNames`, `chdNames`,
/// `deviceRefNames`, `hasSamples`), so showing it costs nothing beyond what a
/// scan (or the pre-scan DAT catalog) already computed — no re-scan, no
/// extra I/O.
///
/// jensyleo tried putting the real DAT name(s) inline in `label` (2026-08-20)
/// and reverted it the same day: with `deviceRefNames` routinely holding
/// half a dozen names, the chip text made the column wrap across several
/// lines for exactly the games this feature most needs to help with.
/// `label` is back to the bare category word; `tooltip` still carries the
/// full name list.
public struct DependencyBadge: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case bios, chd, hardware, samples
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
    /// This game's dependency badges, in a fixed display order (BIOS, CHD,
    /// Hardware, Samples) — roughly how central each dependency usually is
    /// to whether the machine runs at all. The parent/clone relationship
    /// itself is deliberately not one of these: it already has its own
    /// "Family" column (`ParentCloneSummary`), so repeating it here would
    /// just be a redundant "Clone" chip with nothing new to say. Empty for
    /// the synthetic "Surplus files" bucket and a CHD disk row
    /// (`isDiskRow`) — neither has real DAT dependency data of its own to
    /// show (a disk row's `chdNames` names the row itself, not a
    /// dependency of some other row).
    public var dependencyBadges: [DependencyBadge] {
        guard !isSurplusBucket, !isDiskRow else { return [] }
        var badges: [DependencyBadge] = []

        if !requiredBiosNames.isEmpty {
            badges.append(
                DependencyBadge(kind: .bios, label: "BIOS", tooltip: "Requires BIOS: \(requiredBiosNames)")
            )
        }
        if !chdNames.isEmpty {
            let diskCount = chdNames.split(separator: ",").count
            badges.append(
                DependencyBadge(kind: .chd, label: "CHD", tooltip: "Uses CHD (\(diskCount) disk(s)): \(chdNames)")
            )
        }
        if !deviceRefNames.isEmpty {
            badges.append(
                DependencyBadge(kind: .hardware, label: "Hardware", tooltip: "Uses hardware: \(deviceRefNames)")
            )
        }
        if samplesText == "Yes" {
            badges.append(
                DependencyBadge(kind: .samples, label: "Samples", tooltip: "Uses samples")
            )
        }
        return badges
    }
}
