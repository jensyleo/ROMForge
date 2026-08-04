// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Loads a DAT of any supported format into the generic `DATFile` model, so
/// callers (the Matcher, Reports, Rebuilder, the app) never need to know or
/// care which one it was. Tries Logiqx/ClrMamePro XML first (the more
/// common case); a MAME `-listxml` dump has a different root element
/// (`<mame>` instead of `<datafile>`) and fails that parse immediately, so
/// falling back to `MAMEListXMLParser` is cheap and reliable. A MAME
/// software list (`hash/*.xml`, root `<softwarelist>`) — used for
/// cartridge/disk/cassette software on non-arcade systems MAME emulates,
/// rather than arcade machines — is tried last.
public enum DATLoader {
    /// - Parameter onProgress: reports (machinesParsed, totalMachines)
    ///   while parsing a MAME `-listxml` dump specifically — by far the
    ///   largest/slowest format in practice (the full driver set is
    ///   hundreds of MB), and the one place this has actually shown up as a
    ///   multi-minute silent wait in an unoptimized build. The Logiqx and
    ///   software-list formats don't report progress; they're typically far
    ///   smaller and Logiqx is tried first regardless (failing fast on a
    ///   MAME dump's different root element before this ever matters).
    /// - Parameter mergeMode: how a MAME `-listxml` machine's roms are laid
    ///   out into archives, per a real reference MAME frontend's own
    ///   Settings dialog ("Rom merge mode": Merged/Split/Un-merged) —
    ///   purely a parent/clone layout choice, with no bearing on BIOS
    ///   handling (`biosMergeMode`, below, is that same frontend's fully
    ///   separate, independent "Bios merge mode" setting): `.split` (the
    ///   default) keeps a clone's archive to just what changed versus its
    ///   parent, which the clone can't operate without; `.merged` combines
    ///   the parent and all its clones into the parent's own archive;
    ///   `.nonMerged` makes every game's archive completely self-contained
    ///   and independent. Ignored for Logiqx/software-list DATs (already
    ///   one flat rom list per machine — there's no merge concept to
    ///   apply).
    /// - Parameter biosMergeMode: where a BIOS machine's (e.g. `neogeo`)
    ///   roms end up, independently of `mergeMode` — `.split` (the
    ///   default): the BIOS keeps its own separate archive, nothing else
    ///   contains its roms; `.merged`: BIOS roms are folded into each
    ///   dependent ROM-family's root archive only (not into clones
    ///   directly), and the BIOS's own standalone entry is dropped;
    ///   `.nonMerged`: BIOS roms are folded into *every* dependent game
    ///   (root and clone alike), and the BIOS's own standalone entry still
    ///   exists alongside that duplication. See
    ///   `MAMESetLayoutPlanner.foldBiosRoms`'s doc comment for the full
    ///   reasoning.
    /// - Parameter onFileReadProgress: reports (bytesRead, totalBytes) while
    ///   reading the DAT file off disk, before any parsing even starts. A
    ///   real full MAME driver-set DAT is hundreds of MB — `Data(contentsOf:)`
    ///   alone gives no progress signal for however long that raw read
    ///   takes (worse, and unpredictably slower, if the file lives under
    ///   iCloud Drive or another sync provider — this app's own ROM
    ///   folders do), so the caller was left showing a bare, generic
    ///   spinner for that entire stretch with nothing to show for it. A
    ///   chunked `FileHandle` read reports real progress here instead.
    public static func load(
        contentsOf url: URL,
        mergeMode: SetMergeMode = .split,
        biosMergeMode: SetMergeMode = .split,
        onFileReadProgress: (@Sendable (Int64, Int64) -> Void)? = nil,
        onCountingStarted: (@Sendable () -> Void)? = nil,
        onCountingProgress: (@Sendable (Int, Int) -> Void)? = nil,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> DATFile {
        try load(data: try readFile(at: url, onProgress: onFileReadProgress), mergeMode: mergeMode, biosMergeMode: biosMergeMode, onCountingStarted: onCountingStarted, onCountingProgress: onCountingProgress, onProgress: onProgress)
    }

    /// A chunked read instead of a single blocking `Data(contentsOf:)` call
    /// — same eventual result (the whole file, in memory), but with a real
    /// progress signal for however long it takes, which for a large DAT
    /// file (hundreds of MB) can itself be a genuinely slow, unpredictable
    /// stretch (iCloud/network storage especially).
    private static func readFile(at url: URL, onProgress: (@Sendable (Int64, Int64) -> Void)?) throws -> Data {
        guard let onProgress else { return try Data(contentsOf: url) }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let totalSize = (attributes[.size] as? Int64) ?? Int64((attributes[.size] as? Int) ?? 0)
        guard totalSize > 0, let handle = FileHandle(forReadingAtPath: url.path) else {
            return try Data(contentsOf: url)
        }
        defer { try? handle.close() }
        let chunkSize = 4 * 1024 * 1024
        var result = Data(capacity: Int(totalSize))
        var bytesRead: Int64 = 0
        onProgress(0, totalSize)
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            result.append(chunk)
            bytesRead += Int64(chunk.count)
            onProgress(bytesRead, totalSize)
        }
        return result
    }

    public static func load(
        data: Data,
        mergeMode: SetMergeMode = .split,
        biosMergeMode: SetMergeMode = .split,
        onCountingStarted: (@Sendable () -> Void)? = nil,
        onCountingProgress: (@Sendable (Int, Int) -> Void)? = nil,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> DATFile {
        do {
            return try LogiqxDATParser.parse(data: data)
        } catch let logiqxError {
            do {
                let dataset = try MAMEListXMLParser.parse(data: data, onCountingStarted: onCountingStarted, onCountingProgress: onCountingProgress, onProgress: onProgress)
                return datFile(from: dataset, mode: mergeMode, biosMode: biosMergeMode)
            } catch let mameError {
                do {
                    let dataset = try SoftwareListParser.parse(data: data)
                    return datFile(from: dataset)
                } catch let softwareListError {
                    throw DATLoaderError.unrecognizedFormat(
                        logiqxError: String(describing: logiqxError),
                        mameError: String(describing: mameError),
                        softwareListError: String(describing: softwareListError)
                    )
                }
            }
        }
    }

    /// Device machines (sub-components MAME uses internally, e.g. a shared
    /// CPU or sound chip) aren't real games or BIOS sets — they're excluded
    /// so they don't show up as ROMs the user needs to find. A BIOS machine
    /// is excluded too when `biosMergeMode == .merged` (its roms now only
    /// live folded into dependent games' archives — see
    /// `MAMESetLayoutPlanner.foldBiosRoms`'s doc comment).
    ///
    /// Each machine's rom list goes through `MAMESetLayoutPlanner` in
    /// `mode`/`biosMode` rather than being taken as-is: a real `-listxml`
    /// dump declares every rom for every clone, marking ones inherited from
    /// its parent with `merge="..."` — without filtering those out per the
    /// chosen mode, a split-organized clone archive (which never contains
    /// that file, by convention) would wrongly show it as "missing" instead
    /// of correctly treating it as the parent archive's responsibility.
    ///
    /// Under `.merged` specifically, a clone doesn't just *share* roms with
    /// its parent — it has **no archive of its own at all**: everything
    /// ends up in the parent's single archive (e.g. `puckman.zip`). Listing
    /// every clone as its own top-level game anyway (as `.split`/
    /// `.nonMerged` correctly do, since those *do* keep a per-clone
    /// archive) would make ROMForge permanently report every clone archive
    /// as "missing" under Merged mode — a file a real Merged collection
    /// never has in the first place. Clones are excluded here;
    /// `MAMESetLayoutPlanner.mergedGame` already folds each excluded
    /// clone's roms into its parent's own entry.
    private static func datFile(from dataset: MAMEDataset, mode: SetMergeMode, biosMode: SetMergeMode) -> DATFile {
        DATFile(
            header: DATHeader(name: "MAME", description: "Parsed from mame -listxml", version: "", author: "MAMEDev"),
            games: dataset.machines.filter { machine in
                // Devices used to be excluded outright here — real bug
                // found by jensyleo (2026-07-28): a device with a real,
                // physical romset of its own (e.g. CPS2's `qsound_hle`,
                // whose one rom is `merge="..."`-inherited from another
                // device, `qsound`) could then never match anything at
                // all, in any merge mode — its real `qsound_hle.zip`
                // permanently showed as an unrecognized surplus file, no
                // matter how correct it was. A device isn't a "game", but
                // real romset tools (RomVault/ClrMamePro) still audit a
                // device's own set as its own entry, same as a BIOS — the
                // existing `deviceRoms`-folding-into-dependents behavior
                // (`MAMESetLayoutPlanner`) is unaffected either way, this
                // just *also* lets the device's own archive be matched.
                guard biosMode != .merged || !machine.isBios else { return false }
                guard mode != .merged || machine.cloneOf == nil else { return false }
                return true
            }.compactMap { machine in
                guard let layout = try? MAMESetLayoutPlanner.buildGame(for: machine.name, mode: mode, biosMode: biosMode, dataset: dataset) else {
                    return nil
                }
                return DATGame(
                    name: layout.name,
                    description: layout.description,
                    cloneOf: layout.cloneOf,
                    romOf: layout.romOf,
                    roms: layout.roms,
                    isBios: machine.isBios,
                    disks: machine.disks.map { DATDisk(name: $0.name, sha1: $0.sha1) },
                    hasSamples: machine.hasSamples,
                    year: machine.year.isEmpty ? nil : machine.year,
                    manufacturer: machine.manufacturer.isEmpty ? nil : machine.manufacturer,
                    biosSetNames: machine.biosSets.map(\.name),
                    deviceRefs: machine.deviceRefs
                )
            },
            mergeMode: mode,
            // From the raw, unfiltered machine list — see `DATFile.hasClones`'s
            // own doc comment for why this must never be derived from the
            // `games` list built just above (which, under `.merged`, has
            // every clone excluded from it by design).
            hasClones: dataset.machines.contains { $0.cloneOf != nil }
        )
    }

    /// A software's roms/disks are flattened across all its `<part>`s —
    /// `DATGame` has no part/interface concept, the same simplification
    /// applied to MAME machines above. `cloneOf` doubles as `romOf` since
    /// software lists only declare one parent relationship (`cloneof`), not
    /// a separate BIOS-style `romof`.
    private static func datFile(from dataset: SoftwareListDataset) -> DATFile {
        DATFile(
            header: DATHeader(name: dataset.name, description: dataset.description, version: "", author: ""),
            games: dataset.software.map { software in
                DATGame(
                    name: software.name,
                    description: software.description,
                    cloneOf: software.cloneOf,
                    romOf: software.cloneOf,
                    roms: software.allRoms,
                    disks: software.allDisks.map { DATDisk(name: $0.name, sha1: $0.sha1) }
                )
            },
            hasClones: dataset.software.contains { $0.cloneOf != nil }
        )
    }
}
