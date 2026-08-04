// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Metadata describing the origin of a DAT (name, description, version, author).
public struct DATHeader: Equatable, Sendable, Codable {
    public let name: String
    public let description: String
    public let version: String
    public let author: String

    public init(name: String, description: String, version: String, author: String) {
        self.name = name
        self.description = description
        self.version = version
        self.author = author
    }
}

/// A rom's dump-quality flag, from its `status` attribute — a DAT's own
/// claim about the reference dump, independent of whether ROMForge finds a
/// matching local file. `good` (the default) means the attribute was absent
/// or explicitly "good".
public enum RomDumpStatus: String, Equatable, Sendable, Codable {
    case good
    case baddump
    case nodump
}

/// A single expected ROM file within a game, as declared by the DAT.
public struct DATRom: Equatable, Sendable, Codable {
    public let name: String
    public let size: Int64
    public let crc: String?
    public let md5: String?
    public let sha1: String?
    public let status: RomDumpStatus
    /// The `merge="..."` attribute (MAME `-listxml`): names the rom in this
    /// machine's parent/BIOS that this one is identical to — MAME's own
    /// signal for split-mode layout, i.e. "don't duplicate this, it's
    /// already in the parent archive under that name". Nil for Logiqx DATs
    /// (no such concept) and for a machine's own non-inherited roms.
    public let mergeName: String?

    public init(name: String, size: Int64, crc: String?, md5: String?, sha1: String?, status: RomDumpStatus = .good, mergeName: String? = nil) {
        self.name = name
        self.size = size
        self.crc = crc?.lowercased()
        self.md5 = md5?.lowercased()
        self.sha1 = sha1?.lowercased()
        self.status = status
        self.mergeName = mergeName
    }
}

/// A CHD disk image declared by a game/machine. Only identity is modeled —
/// reading/verifying CHD content is a separate, later effort (see
/// `CHDHeaderReader`/`CHDMatcher`, not yet wired into the scan pipeline).
public struct DATDisk: Equatable, Sendable, Codable {
    public let name: String
    public let sha1: String?

    public init(name: String, sha1: String?) {
        self.name = name
        self.sha1 = sha1?.lowercased()
    }
}

/// A game (ROM set) entry, i.e. one or more ROM files that together make up a title.
public struct DATGame: Equatable, Sendable, Codable {
    public let name: String
    public let description: String
    public let cloneOf: String?
    public let romOf: String?
    public let roms: [DATRom]
    /// True for MAME BIOS sets (`isbios="yes"`). Always false for
    /// Logiqx/ClrMamePro DATs, which have no such concept.
    public let isBios: Bool
    /// CHD disks this game declares. Presence alone (not verification — see
    /// `DATDisk`) is enough to answer "does this game need a CHD".
    public let disks: [DATDisk]
    /// True if the DAT declares this game uses samples (`<sample>` /
    /// `sampleof`). Presence-only, like `disks` — ROMForge doesn't audit
    /// sample files on disk.
    public let hasSamples: Bool
    /// Release year, when the DAT declares one (MAME `-listxml`'s
    /// `<year>`) — `nil` for formats/entries that don't.
    public let year: String?
    /// Manufacturer/developer, when the DAT declares one (MAME
    /// `-listxml`'s `<manufacturer>`) — `nil` for formats/entries that
    /// don't.
    public let manufacturer: String?
    /// Named BIOS ROM variants this machine itself declares (MAME
    /// `-listxml`'s `<biosset>` children) — e.g. several selectable
    /// region/revision BIOSes on one PCB. Empty for formats with no such
    /// concept, or a machine that declares none.
    public let biosSetNames: [String]
    /// Names of internal "device" sub-machines (shared CPU/sound chip,
    /// etc.) this machine references (MAME `-listxml`'s `<device_ref>`) —
    /// not real games themselves (already filtered out of `DATFile.games`
    /// entirely), just a dependency list. Empty for formats with no such
    /// concept.
    public let deviceRefs: [String]

    public init(
        name: String,
        description: String,
        cloneOf: String?,
        romOf: String?,
        roms: [DATRom],
        isBios: Bool = false,
        disks: [DATDisk] = [],
        hasSamples: Bool = false,
        year: String? = nil,
        manufacturer: String? = nil,
        biosSetNames: [String] = [],
        deviceRefs: [String] = []
    ) {
        self.name = name
        self.description = description
        self.cloneOf = cloneOf
        self.romOf = romOf
        self.roms = roms
        self.isBios = isBios
        self.disks = disks
        self.hasSamples = hasSamples
        self.year = year
        self.manufacturer = manufacturer
        self.biosSetNames = biosSetNames
        self.deviceRefs = deviceRefs
    }
}

/// The parsed representation of a Logiqx/ClrMamePro-style XML DAT.
public struct DATFile: Equatable, Sendable, Codable {
    public let header: DATHeader
    public let games: [DATGame]
    /// The MAME Rom merge mode this `DATFile` was built with, when it came
    /// from a MAME `-listxml` dataset (`DATLoader`'s `datFile(from:mode:
    /// biosMode:)`) — `nil` for a Logiqx/ClrMamePro DAT or a MAME software
    /// list, neither of which has this concept at all. `ROMMatcher` reads
    /// this to decide whether a game may ever be satisfied by a rom found
    /// in some *other* archive: under `.nonMerged`, jensyleo's own
    /// definition (2026-07-28) is that every game's own archive must be
    /// fully self-contained, full stop — it must never "need" a rom that
    /// actually lives in a different game's file, clone/bootleg/parent or
    /// otherwise, not even the existing renamed-archive fallback that
    /// otherwise helps `.split`/`.merged` scans tolerate a whole archive
    /// the user renamed.
    public let mergeMode: SetMergeMode?
    /// Whether *any* machine in the original dataset has a real clone/
    /// parent relationship — computed once from the raw, pre-layout-
    /// planning machine list, deliberately independent of `mergeMode`.
    /// Real bug found live by jensyleo (2026-08-04): the app used to derive
    /// this same fact itself by checking `games.contains { $0.cloneOf !=
    /// nil }` on `DATFile.games` directly — but under `.merged`,
    /// `DATLoader`'s own game-list filter *excludes every clone from the
    /// list entirely* (folded into its parent's own entry — see that
    /// filter's own doc comment), so that check is **structurally
    /// guaranteed to be `false` whenever computed from a Merged-mode
    /// `DATFile`**, regardless of whether the underlying system has real
    /// clones or not. That false reading then got persisted onto
    /// `RomSystem.hasClones` and silently poisoned a later optimization
    /// (skip re-parsing a clone-less system's DAT when only Rom merge mode
    /// changes) into applying to a system that actually has hundreds of
    /// real clones — serving a stale/wrong DAT for every other mode after
    /// that. Computed here, once, from data that's never subject to that
    /// mode-dependent filtering, so it's correct no matter which mode the
    /// resulting `DATFile` itself was built under.
    public let hasClones: Bool
    /// Every machine name in the *original*, pre-layout-planning dataset
    /// (lowercased), independent of `mergeMode` — same pattern, and same
    /// real reason, as `hasClones` right above. Real bug found live by
    /// jensyleo (2026-08-04, Merged mode): `ROMMatcher`'s own
    /// `isInClaimedArchive` check (guards its renamed-unclaimed-archive
    /// fallback from stealing content between two archives that both
    /// happen to be real game names) used to derive its "which archive
    /// names are claimed" set from `DATFile.games.map(\.name)` directly —
    /// but under `.merged`, that list has every *clone* excluded entirely
    /// (folded into its parent's own entry). A clone's own physical
    /// archive (e.g. `sf2acca.zip`, still sitting on disk unrenamed) then
    /// read as *unclaimed* purely because Merged mode's own list no longer
    /// mentions its name — reopening the exact cross-game "steal" problem
    /// that check exists to prevent: a completely unrelated bootleg/
    /// gambling machine's blank-socket placeholder rom ("missing.rom",
    /// byte-identical across dozens of unrelated boards by sheer
    /// coincidence — an unpopulated EPROM socket) matched against whatever
    /// physically occupies that same byte pattern inside `sf2acca.zip`,
    /// reporting a nonsensical relationship between two totally
    /// unconnected games. Defaults to empty for a Logiqx/software-list
    /// `DATFile` (no merge-mode clone-exclusion concept exists there at
    /// all — every caller of this initializer for those formats already
    /// passes the *same* set as `games`' own names, so nothing is lost).
    public let allMachineNames: Set<String>

    public init(header: DATHeader, games: [DATGame], mergeMode: SetMergeMode? = nil, hasClones: Bool = false, allMachineNames: Set<String>? = nil) {
        self.header = header
        self.games = games
        self.mergeMode = mergeMode
        self.hasClones = hasClones
        self.allMachineNames = allMachineNames ?? Set(games.map { $0.name.lowercased() })
    }
}
