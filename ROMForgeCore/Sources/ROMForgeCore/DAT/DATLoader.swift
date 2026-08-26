// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// The result of `DATLoader.parse` — everything genuinely learned from the
/// DAT's own bytes, BEFORE `mergeMode`/`biosMergeMode` get applied. Exists
/// to let a caller cache the (slow) parse independently of the (fast)
/// mode-dependent derivation — see `DATLoader.build(from:mergeMode:biosMergeMode:)`'s
/// own doc comment for why that split exists and the measurements behind it.
///
/// Only the MAME `-listxml` case has a real, separate derivation step at
/// all (`MAMESetLayoutPlanner`, driven by `mode`/`biosMode`) — a Logiqx/
/// ClrMamePro XML or MAME software list DAT already IS one flat rom list
/// per machine with no merge concept to apply, so `.build` returns those
/// two cases back out untouched, at whatever mode was asked for.
public enum ParsedDAT: Sendable {
    case logiqx(DATFile)
    case mame(MAMEDataset)
    case softwareList(SoftwareListDataset)
}

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
        try build(
            from: try parse(contentsOf: url, onFileReadProgress: onFileReadProgress, onCountingStarted: onCountingStarted, onCountingProgress: onCountingProgress, onProgress: onProgress),
            mergeMode: mergeMode, biosMergeMode: biosMergeMode
        )
    }

    /// The `contentsOf:` counterpart to `parse(data:...)` — reads the file
    /// off disk (with the same chunked, progress-reporting read
    /// `load(contentsOf:...)` always used) and parses it, without applying
    /// any `mergeMode`/`biosMergeMode` yet. See `ParsedDAT`'s and
    /// `build(from:mergeMode:biosMergeMode:)`'s own doc comments for why a
    /// caller would want this split instead of just calling `load`.
    public static func parse(
        contentsOf url: URL,
        onFileReadProgress: (@Sendable (Int64, Int64) -> Void)? = nil,
        onCountingStarted: (@Sendable () -> Void)? = nil,
        onCountingProgress: (@Sendable (Int, Int) -> Void)? = nil,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> ParsedDAT {
        try parse(data: try readFile(at: url, onProgress: onFileReadProgress), onCountingStarted: onCountingStarted, onCountingProgress: onCountingProgress, onProgress: onProgress)
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
            try Task.checkCancellation()
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
        try build(
            from: try parse(data: data, onCountingStarted: onCountingStarted, onCountingProgress: onCountingProgress, onProgress: onProgress),
            mergeMode: mergeMode, biosMergeMode: biosMergeMode
        )
    }

    /// Everything genuinely learned from the DAT's own bytes, with NO
    /// `mergeMode`/`biosMergeMode` applied yet — see `ParsedDAT`'s own doc
    /// comment for why this is worth having as its own step, and
    /// `build(from:mergeMode:biosMergeMode:)`'s own doc comment for the
    /// measurements that justify it.
    ///
    /// Split out of `load(data:mergeMode:biosMergeMode:...)` on 2026-08-11
    /// (jensyleo's own request, after reporting that changing Rom/Bios merge
    /// mode mid-session re-triggered the full, slow reload) — `load` itself
    /// is now a thin `parse` + `build` wrapper, so every existing call site
    /// and test keeps working completely unchanged; only a caller that
    /// wants to cache the parse independently of the mode needs to call
    /// these two separately.
    public static func parse(
        data: Data,
        onCountingStarted: (@Sendable () -> Void)? = nil,
        onCountingProgress: (@Sendable (Int, Int) -> Void)? = nil,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> ParsedDAT {
        // A genuine cancellation must never fall into the "try the next
        // format" cascade below — real bug found live by jensyleo
        // (2026-08-04), the same class as `ROMMatcher`/`AuditReporter`
        // needing this fix downstream: without this explicit re-throw, a
        // `CancellationError` from deep inside the MAME branch would be
        // caught by `catch let mameError` below, misread as "this isn't a
        // MAME DAT after all", and swallowed into a fallback attempt at
        // `SoftwareListParser` — hiding the real cancellation behind an
        // unrelated "unrecognized format" error instead of actually
        // stopping.
        do {
            return .logiqx(try LogiqxDATParser.parse(data: data))
        } catch is CancellationError {
            throw CancellationError()
        } catch let logiqxError {
            do {
                return .mame(try MAMEListXMLParser.parse(data: data, onCountingStarted: onCountingStarted, onCountingProgress: onCountingProgress, onProgress: onProgress))
            } catch is CancellationError {
                throw CancellationError()
            } catch let mameError {
                do {
                    return .softwareList(try SoftwareListParser.parse(data: data))
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

    /// Applies `mergeMode`/`biosMergeMode` to an already-`parse`d DAT —
    /// the ONLY step that actually depends on either setting.
    ///
    /// **Why this split exists, with real numbers behind it** (jensyleo's
    /// own request, 2026-08-11, after reporting that changing Rom/Bios merge
    /// mode re-triggered a full, slow DAT reload): timed separately against
    /// a real MAME 0.288 dump (50,097 machines) —
    ///
    ///   raw XML parse (`parse`, above)          9.4s
    ///   derivation only (this function, MAME)   0.17 – 0.92s  (mode-dependent)
    ///   `load` end to end (both combined)        9.7 – 10.4s
    ///
    /// The parse is 90%+ of the total cost, and it does not depend on
    /// `mergeMode`/`biosMergeMode` at all — those only affect this
    /// derivation step, which is at least an order of magnitude cheaper. A
    /// caller that keeps its own already-`parse`d `ParsedDAT` around (the
    /// app's `LibraryViewModel` does, per-system, for exactly this reason)
    /// can therefore let a user switch merge modes near-instantly instead of
    /// paying the full parse again for a file that hasn't actually changed.
    ///
    /// A Logiqx/software-list DAT has no such step (already one flat rom
    /// list per machine, mode-independent by construction) — returned as-is,
    /// `mergeMode`/`biosMergeMode` simply don't apply to those two cases.
    public static func build(from parsed: ParsedDAT, mergeMode: SetMergeMode = .split, biosMergeMode: SetMergeMode = .split) throws -> DATFile {
        switch parsed {
        case .logiqx(let dat):
            return dat
        case .mame(let dataset):
            return try datFile(from: dataset, mode: mergeMode, biosMode: biosMergeMode)
        case .softwareList(let dataset):
            return datFile(from: dataset)
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
    /// `throws` only ever propagates `CancellationError` — real bug found
    /// live by jensyleo (2026-08-04): pressing Cancel during DAT loading
    /// showed the "loading cancelled" warning immediately, but loading kept
    /// running to completion regardless (the *first* instance of this class
    /// of bug found, before the same fix was applied to `ROMMatcher`/
    /// `AuditReporter`/`DiskAuditor` downstream — this loop, building a
    /// `DATGame` layout for every one of a full MAME dataset's ~43,000
    /// machines via `MAMESetLayoutPlanner`, is often the *actual* long
    /// stretch during "loading", not the XML parse itself). Checked
    /// throttled (every 2000 machines) inside the loop — this runs
    /// synchronously on the calling `Task`'s own thread (no concurrent
    /// dispatch here), so the check is meaningful everywhere in it.
    /// A game's expected CHDs under the current Rom merge mode — real bug
    /// found live by jensyleo (2026-08-04, testing Merged mode): under
    /// `.merged`, every clone is excluded from `dat.games` entirely
    /// (`MAMESetLayoutPlanner.mergedGame` already unions a clone family's
    /// *roms* into the surviving parent entry — see its own doc comment —
    /// but nothing did the same for *disks*, which this function reads
    /// straight from `machine.disks` alone). Confirmed against a real MAME
    /// 0.288 dump: 313 clones declare a CHD with a genuinely different
    /// sha1 from their own parent's (a different disc revision/region —
    /// not a rare edge case), so under Merged that clone's own real CHD
    /// was never expected by *any* surviving `DATGame` at all — a user's
    /// real `.chd` file for that revision permanently read as plain
    /// unrecognized surplus, no matter how correct it was, the exact same
    /// class of bug the 2026-07-28 device-exclusion fix already fixed
    /// once for roms. Split/Non-merged need no equivalent fix here: every
    /// clone still gets its own `DATGame` entry there (this function's own
    /// `for machine in dataset.machines` loop reaches it directly), so its
    /// own `machine.disks` is already captured correctly on its own.
    private static func mergedDisks(for machine: MAMEMachine, mode: SetMergeMode, dataset: MAMEDataset) -> [DATDisk] {
        guard mode == .merged else {
            return machine.disks.map { DATDisk(name: $0.name, sha1: $0.sha1, optional: $0.optional) }
        }
        var seen = Set<String>()
        var disks: [DATDisk] = []
        for disk in machine.disks + dataset.clones(ofParent: machine.name).flatMap(\.disks) where seen.insert("\(disk.name)::\(disk.sha1 ?? "")").inserted {
            disks.append(DATDisk(name: disk.name, sha1: disk.sha1, optional: disk.optional))
        }
        return disks
    }

    private static func datFile(from dataset: MAMEDataset, mode: SetMergeMode, biosMode: SetMergeMode) throws -> DATFile {
        var games: [DATGame] = []
        games.reserveCapacity(dataset.machines.count)
        for machine in dataset.machines {
            // Checked every machine, not throttled — see `ROMMatcher.match`'s
            // own doc comment for why throttling this was a real bug.
            try Task.checkCancellation()
            // Devices used to be excluded outright here — real bug found by
            // jensyleo (2026-07-28): a device with a real, physical romset
            // of its own (e.g. CPS2's `qsound_hle`, whose one rom is
            // `merge="..."`-inherited from another device, `qsound`) could
            // then never match anything at all, in any merge mode — its
            // real `qsound_hle.zip` permanently showed as an unrecognized
            // surplus file, no matter how correct it was. A device isn't a
            // "game", but real romset tools (RomVault/ClrMamePro) still
            // audit a device's own set as its own entry, same as a BIOS —
            // the existing `deviceRoms`-folding-into-dependents behavior
            // (`MAMESetLayoutPlanner`) is unaffected either way, this just
            // *also* lets the device's own archive be matched.
            // A BIOS's own standalone entry used to be dropped entirely
            // under `biosMode == .merged` — correct for a genuine
            // multi-clone family (the root absorbs the BIOS, clones rely on
            // it), but for a *flat* system where every dependent is its own
            // clone-less title (no clone relationships between titles at
            // all — every real NeoGeo game, each only `romof="neogeo"`),
            // `MAMESetLayoutPlanner.foldBiosRoms`'s own "family root" test
            // (`cloneOf == nil`) is satisfied by literally every single
            // title, so Merged ended up folding the BIOS into every game
            // (indistinguishable from Non-Merged) while ALSO hiding the
            // BIOS's own row — the one thing Non-Merged still showed.
            // jensyleo's own report (2026-08-17), confirmed live against a
            // real NeoGeo collection: switching Bios merge mode made
            // "neogeo" vanish from the games list entirely, reading as
            // data loss rather than a deliberate display choice. Always
            // keeping the BIOS's own entry, in all three modes, is simpler
            // and strictly more informative — it never conflicts with
            // whatever else also folds a copy of its roms in.
            guard mode != .merged || machine.cloneOf == nil else { continue }
            guard let layout = try? MAMESetLayoutPlanner.buildGame(for: machine.name, mode: mode, biosMode: biosMode, dataset: dataset) else {
                continue
            }
            games.append(DATGame(
                name: layout.name,
                description: layout.description,
                cloneOf: layout.cloneOf,
                romOf: layout.romOf,
                roms: layout.roms,
                isBios: machine.isBios,
                disks: mergedDisks(for: machine, mode: mode, dataset: dataset),
                hasSamples: machine.hasSamples,
                year: machine.year.isEmpty ? nil : machine.year,
                manufacturer: machine.manufacturer.isEmpty ? nil : machine.manufacturer,
                mergedFamilyMachineNames: layout.mergedFamilyMachineNames,
                biosSetNames: machine.biosSets.map(\.name),
                deviceRefs: machine.deviceRefs
            ))
        }
        return DATFile(
            header: DATHeader(name: "MAME", description: "Parsed from mame -listxml", version: "", author: "MAMEDev"),
            games: games,
            mergeMode: mode,
            // From the raw, unfiltered machine list — see `DATFile.hasClones`'s
            // own doc comment for why this must never be derived from the
            // `games` list built just above (which, under `.merged`, has
            // every clone excluded from it by design).
            hasClones: dataset.machines.contains { $0.cloneOf != nil },
            // Same reasoning, for `ROMMatcher`'s own `isInClaimedArchive`
            // check this time — see `DATFile.allMachineNames`'s own doc
            // comment for the real cross-game "steal" bug this fixes.
            allMachineNames: Set(dataset.machines.map { $0.name.lowercased() })
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
