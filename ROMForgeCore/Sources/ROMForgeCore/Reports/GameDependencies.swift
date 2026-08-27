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

/// Curated, deliberately incomplete list of common MAME CPU device short
/// names — used only to split the "Hardware" tooltip into a `CPU:` line a
/// user is likely to recognize and an `Other:` line for everything else.
/// MAME's `<device_ref>` carries only a device name, no type, so this list
/// isn't sourced from the DAT and never claims completeness: any name not
/// in this set falls into `Other:`, never silently mislabeled as something
/// it isn't.
private let knownCPUDeviceNames: Set<String> = [
    "z80", "z8400", "z84c0010", "z180",
    "m6502", "m6507", "m6509", "m65c02", "m6510", "n2a03",
    "m6800", "m6801", "m6803", "m6805", "m6809", "m6809e", "hd6309", "hd63701", "hd6301",
    "m68000", "m68010", "m68020", "m68030", "m68040", "scc68070",
    "i8080", "i8085", "i8086", "i8088", "i80186", "i80286", "v20", "v30", "v33", "v60", "v70",
    "i8035", "i8039", "i8048", "i8049", "i8051", "i8749", "mcs48", "mcs51",
    "tms9900", "tms9980", "tms9995", "tms32010", "tms32025", "tms34010", "tms34020",
    "arm", "arm7", "arm7500", "arm9", "sh1", "sh2", "sh4",
    "mips1", "mips3", "powerpc", "ppc403", "ppc601", "ppc602", "ppc603",
    "upd7810", "upd78c05", "upd78c11", "upd7801",
    "cop420", "cop410", "cop440",
    "h6280", "h83002", "h83007", "h83044",
    "pic16c54", "pic16c57", "pic16c58",
    "se3208", "e116t", "mn10200", "dsp16a", "adsp2100", "adsp2105", "adsp2115",
]

/// Splits a comma-separated `deviceRefNames` string into a `CPU:` line
/// (names found in `knownCPUDeviceNames`) and an `Other:` line (everything
/// else), so the "Hardware" tooltip reads as more than a wall of internal
/// MAME device names without ever guessing at a category this doesn't
/// actually recognize. No leading "Uses hardware" restates the badge's own
/// "Hardware" label, so it's left out — same reasoning as the other badges'
/// tooltips below.
private func hardwareTooltip(from deviceRefNames: String) -> String {
    let names = deviceRefNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    let cpus = names.filter { knownCPUDeviceNames.contains($0.lowercased()) }
    let others = names.filter { !knownCPUDeviceNames.contains($0.lowercased()) }
    var lines: [String] = []
    if !cpus.isEmpty { lines.append("CPU: \(cpus.joined(separator: ", "))") }
    if !others.isEmpty { lines.append("Other: \(others.joined(separator: ", "))") }
    return lines.joined(separator: "\n")
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

        // Each tooltip below deliberately skips restating its own badge
        // label ("Requires BIOS:", "Uses CHD:", "Uses hardware:", "Uses
        // samples") — the chip is already labeled, so the tooltip carries
        // only the information the label itself can't fit: the actual
        // name(s).
        if !requiredBiosNames.isEmpty {
            badges.append(DependencyBadge(kind: .bios, label: "BIOS", tooltip: requiredBiosNames))
        }
        if !chdNames.isEmpty {
            let diskCount = chdNames.split(separator: ",").count
            let diskWord = diskCount == 1 ? "disk" : "disks"
            badges.append(
                DependencyBadge(kind: .chd, label: "CHD", tooltip: "\(diskCount) \(diskWord): \(chdNames)")
            )
        }
        if !deviceRefNames.isEmpty {
            badges.append(
                DependencyBadge(kind: .hardware, label: "Hardware", tooltip: hardwareTooltip(from: deviceRefNames))
            )
        }
        if samplesText == "Yes" {
            // Nothing beyond the "Samples" label itself to say here, so
            // this badge carries no tooltip at all rather than a sentence
            // that would just repeat the label.
            badges.append(DependencyBadge(kind: .samples, label: "Samples", tooltip: ""))
        }
        return badges
    }
}
