// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// A required BIOS set declared by a `<machine>`, e.g. `neogeo` for most
/// Neo-Geo games. Distinct from the BIOS *machine* itself (see
/// `MAMEMachine.isBios`).
public struct MAMEBiosSet: Equatable, Sendable {
    public let name: String
    public let description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

/// A CHD disk image referenced by a `<machine>`. Only identity is modeled
/// here — reading/verifying CHD content itself is a separate, later effort.
public struct MAMEDisk: Equatable, Sendable {
    public let name: String
    public let sha1: String?
    /// The `optional="yes"` attribute — see `DATDisk.optional`'s own doc
    /// comment for the concept.
    public let optional: Bool

    public init(name: String, sha1: String?, optional: Bool = false) {
        self.name = name
        self.sha1 = sha1?.lowercased()
        self.optional = optional
    }
}

/// One `<chip>` a `<machine>` actually instantiates — MAME's own hardware
/// truth, straight from `-listxml`'s `type` ("cpu" or "audio" — MAME has
/// never defined a third) and human-readable `name` (e.g. "Capcom QSound
/// (custom)", not an internal device short name). Distinct from
/// `MAMEMachine.deviceRefs`, which lists shared/support sub-devices by
/// short name with no type at all.
public struct MAMEChip: Equatable, Sendable {
    public let type: String
    public let name: String

    public init(type: String, name: String) {
        self.type = type
        self.name = name
    }
}

/// One `<machine>` entry from MAME's `-listxml` output — a superset of the
/// generic Logiqx `DATGame`, with the hardware/BIOS metadata Logiqx lacks.
public struct MAMEMachine: Equatable, Sendable {
    public let name: String
    public let description: String
    public let year: String
    public let manufacturer: String
    public let cloneOf: String?
    public let romOf: String?
    public let isBios: Bool
    public let isDevice: Bool
    public let biosSets: [MAMEBiosSet]
    public let roms: [DATRom]
    public let disks: [MAMEDisk]
    public let deviceRefs: [String]
    /// Every CPU/audio chip this machine actually instantiates, per
    /// `-listxml`'s own `<chip>` elements — see `MAMEChip`'s own doc
    /// comment. Empty for machines `-listxml` reports none for (rare but
    /// real, e.g. some pure-mechanical or placeholder devices) and for
    /// every non-MAME DAT format, which has no such concept.
    public let chips: [MAMEChip]
    /// True when the machine declares any `<sample>` — presence-only, like
    /// `disks`; ROMForge doesn't audit sample files on disk.
    public let hasSamples: Bool
    /// The `<driver status="...">` MAME reports for its OWN emulation of
    /// this machine ("good"/"imperfect"/"preliminary") — purely descriptive
    /// metadata about MAME itself, never a claim about whether the user's
    /// own dump is correct (that's `AuditEntry.status`, an entirely
    /// different, unrelated concept). `nil` for every non-MAME DAT format,
    /// which has no such concept, and for a machine `-listxml` reports none
    /// for.
    public let driverStatus: String?
    /// The `<display type="...">` this machine reports — "raster", "vector",
    /// or "lcd". `nil` for a machine with no display (e.g. some mechanical
    /// machines) or a non-MAME DAT.
    public let displayType: String?
    /// The `<display rotate="...">` this machine reports — "0"/"90"/"180"/
    /// "270", i.e. screen orientation (0/180 = horizontal, 90/270 =
    /// vertical). `nil` under the same conditions as `displayType`.
    public let displayRotate: String?
    /// The `<input players="...">` this machine reports, e.g. "2" for a
    /// two-player game. `nil` for a non-MAME DAT or a machine `-listxml`
    /// reports none for.
    public let players: String?
    /// The `<input coins="...">` this machine reports — how many coin slots
    /// it uses (`"0"` for a freeplay-only machine, no coin mechanism at
    /// all). `nil` under the same conditions as `players`.
    public let coins: String?

    public init(
        name: String,
        description: String,
        year: String,
        manufacturer: String,
        cloneOf: String?,
        romOf: String?,
        isBios: Bool,
        isDevice: Bool,
        biosSets: [MAMEBiosSet],
        roms: [DATRom],
        disks: [MAMEDisk],
        deviceRefs: [String],
        chips: [MAMEChip] = [],
        hasSamples: Bool = false,
        driverStatus: String? = nil,
        displayType: String? = nil,
        displayRotate: String? = nil,
        players: String? = nil,
        coins: String? = nil
    ) {
        self.name = name
        self.description = description
        self.year = year
        self.manufacturer = manufacturer
        self.cloneOf = cloneOf
        self.romOf = romOf
        self.isBios = isBios
        self.isDevice = isDevice
        self.biosSets = biosSets
        self.roms = roms
        self.disks = disks
        self.deviceRefs = deviceRefs
        self.chips = chips
        self.hasSamples = hasSamples
        self.driverStatus = driverStatus
        self.displayType = displayType
        self.displayRotate = displayRotate
        self.players = players
        self.coins = coins
    }
}

/// The full set of machines parsed from a MAME `-listxml` document.
///
/// `machine(named:)`/`clones(ofParent:)` back onto dictionaries built once
/// at `init` rather than scanning `machines` linearly per lookup — a real
/// full MAME driver set is 50,000+ machines, and `MAMESetLayoutPlanner`
/// calls one or both of these *once per machine* while converting the whole
/// dataset (`DATLoader.datFile`). A linear scan per call made that an O(n²)
/// pass over the entire dataset — tens of billions of comparisons for a
/// real `-listxml` dump — which in practice looked exactly like the DAT
/// load hanging forever, rather than just being slow.
public struct MAMEDataset: Sendable {
    public let machines: [MAMEMachine]
    private let machinesByName: [String: MAMEMachine]
    private let clonesByParent: [String: [MAMEMachine]]

    public init(machines: [MAMEMachine]) {
        self.machines = machines
        self.machinesByName = Dictionary(machines.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.clonesByParent = Dictionary(grouping: machines.filter { $0.cloneOf != nil }, by: { $0.cloneOf! })
    }

    public func machine(named name: String) -> MAMEMachine? {
        machinesByName[name]
    }

    /// Every machine whose `cloneOf` points at `name` — order not
    /// guaranteed to match `machines`' own order (grouped by parent, not
    /// scanned in original sequence), which no caller has depended on.
    public func clones(ofParent name: String) -> [MAMEMachine] {
        clonesByParent[name] ?? []
    }
}

extension MAMEDataset: Equatable {
    // Custom, rather than synthesized: the dictionaries above are a derived
    // cache of `machines`, not independent state — comparing them too would
    // just be redundant, more expensive work for the same answer.
    public static func == (lhs: MAMEDataset, rhs: MAMEDataset) -> Bool {
        lhs.machines == rhs.machines
    }
}
