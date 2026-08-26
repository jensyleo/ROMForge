// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// A CHD disk declared inside a software's `<part>` — MAME software lists
/// use `<diskarea><disk>` the same way `-listxml` machines use `<disk>`.
public struct SoftwareListDisk: Equatable, Sendable {
    public let name: String
    public let sha1: String?
    public let status: RomDumpStatus

    public init(name: String, sha1: String?, status: RomDumpStatus = .good) {
        self.name = name
        self.sha1 = sha1?.lowercased()
        self.status = status
    }
}

/// One physically separate piece of media within a software entry — a
/// cartridge, floppy, or CD, each with its own MAME device `interface`
/// (e.g. `floppy_5_25`, `cdrom`). A multi-disc game has one `<part>` per
/// disc rather than one `<software>` per disc, unlike Redump's convention
/// of a separate top-level game per disc.
public struct SoftwareListPart: Equatable, Sendable {
    public let name: String
    public let interface: String
    public let roms: [DATRom]
    public let disks: [SoftwareListDisk]

    public init(name: String, interface: String, roms: [DATRom], disks: [SoftwareListDisk]) {
        self.name = name
        self.interface = interface
        self.roms = roms
        self.disks = disks
    }
}

/// One `<software>` entry — a single piece of software for a MAME-emulated
/// computer/console/handheld system, as opposed to an arcade `<machine>`.
public struct SoftwareListSoftware: Equatable, Sendable {
    public let name: String
    public let description: String
    public let cloneOf: String?
    public let parts: [SoftwareListPart]

    public init(name: String, description: String, cloneOf: String?, parts: [SoftwareListPart]) {
        self.name = name
        self.description = description
        self.cloneOf = cloneOf
        self.parts = parts
    }

    /// Every rom across every part, flattened — ROMForge's generic
    /// `DATGame` has no part/interface concept, so a multi-part software
    /// (e.g. a multi-disk game) is audited as one set with all its roms
    /// combined, the same simplification `DATLoader` already applies when
    /// converting a MAME `-listxml` machine.
    public var allRoms: [DATRom] { parts.flatMap(\.roms) }
    public var allDisks: [SoftwareListDisk] { parts.flatMap(\.disks) }
}

/// The full set of software entries parsed from a MAME software-list XML
/// document (`hash/*.xml`, or `mame -listsoftware` output).
public struct SoftwareListDataset: Equatable, Sendable {
    public let name: String
    public let description: String
    public let software: [SoftwareListSoftware]

    public init(name: String, description: String, software: [SoftwareListSoftware]) {
        self.name = name
        self.description = description
        self.software = software
    }
}
