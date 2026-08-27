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
/// `deviceRefNames`, `cpuChipNames`, `audioChipNames`, `hasSamples`), so
/// showing it costs nothing beyond what a scan (or the pre-scan DAT
/// catalog) already computed — no re-scan, no extra I/O.
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
/// names — used only as a fallback for the "Hardware" tooltip's `CPU:` line
/// when a game has no real `<chip>` data of its own (see `hardwareTooltip`).
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

/// Builds the "Hardware" tooltip out of up to three lines — `CPU:`,
/// `Sound:`, `Other:` — none of them restating the badge's own "Hardware"
/// label, same reasoning as the other badges' tooltips below.
///
/// `cpuChipNames`/`audioChipNames` are MAME `-listxml`'s own `<chip
/// type="cpu"|"audio">` elements (see `MAMEChip`'s own doc comment) — real
/// DAT ground truth, with human-readable names (e.g. "Capcom QSound
/// (custom)"), not a guess. jensyleo's own question (2026-08-27): does the
/// DAT actually mark qsound as a sound chip anywhere? It does, just not in
/// `device_ref` — `<chip>` is a separate element ROMForge didn't parse
/// before this. When present, it entirely replaces the curated-list
/// guess below for the CPU line, and `deviceRefNames` becomes purely
/// `Other:` (device_ref lists shared/support sub-devices, a different
/// namespace from chip, so no attempt is made to cross-reference the two
/// against each other).
///
/// When a game has no `<chip>` data at all (an older/partial DAT, or a
/// non-MAME format with no such concept), CPU falls back to matching
/// `deviceRefNames` against `knownCPUDeviceNames` — the same heuristic this
/// tooltip used before real chip data was available — so CPU identification
/// degrades gracefully instead of disappearing outright.
private func hardwareTooltip(cpuChipNames: String, audioChipNames: String, deviceRefNames: String) -> String {
    let deviceNames = deviceRefNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

    let cpuLine: String?
    let otherNames: [String]
    if !cpuChipNames.isEmpty {
        cpuLine = "CPU: \(cpuChipNames)"
        otherNames = deviceNames
    } else {
        let cpus = deviceNames.filter { knownCPUDeviceNames.contains($0.lowercased()) }
        cpuLine = cpus.isEmpty ? nil : "CPU: \(cpus.joined(separator: ", "))"
        otherNames = deviceNames.filter { !knownCPUDeviceNames.contains($0.lowercased()) }
    }
    let soundLine = audioChipNames.isEmpty ? nil : "Sound: \(audioChipNames)"
    let otherLine = otherNames.isEmpty ? nil : "Other: \(otherNames.joined(separator: ", "))"
    return [cpuLine, soundLine, otherLine].compactMap { $0 }.joined(separator: "\n")
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
        if !deviceRefNames.isEmpty || !cpuChipNames.isEmpty || !audioChipNames.isEmpty {
            badges.append(
                DependencyBadge(
                    kind: .hardware, label: "Hardware",
                    tooltip: hardwareTooltip(cpuChipNames: cpuChipNames, audioChipNames: audioChipNames, deviceRefNames: deviceRefNames)
                )
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
