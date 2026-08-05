// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// Builds the ROM list for one machine's output archive under a given
/// `SetMergeMode`/BIOS merge mode pair, expressed as a generic `DATGame` so
/// the existing Matcher/Rebuilder pipeline can be reused unchanged
/// regardless of layout.
///
/// `mode` and `biosMode` are **independent axes** — confirmed against a
/// real reference tool's own Settings dialog (a MAME frontend offering
/// separate "Rom merge mode" and "Bios merge mode" radio groups, each with
/// its own Merged/Split/Un-merged choice) rather than assumed. `mode`
/// governs only how a clone's roms relate to its parent's archive; it says
/// nothing about the BIOS. `biosMode` governs only whether/where BIOS roms
/// get folded into a dependent game's archive — completely separate from,
/// and combinable with, any `mode` value. An earlier version conflated the
/// two (a plain "include BIOS" toggle whose meaning shifted depending on
/// `mode`) — this replaces that.
///
/// Additional edge cases below come from real bugs documented in
/// ClrMamePro's/RomCenter's own forums (see ROADMAP.md's merge-mode
/// research notes) — deliberately handled as explicit rules here instead of
/// being rediscovered the hard way once rebuild ships:
/// - a **merged-set hash collision** (same rom filename, different content,
///   across a parent and its clone) must not silently drop one version;
/// - **split mode** must respect the DAT's own `merge="..."` marker, not
///   just hand back every rom the machine happens to declare;
/// - **non-merged** must be truly self-contained, including device roms,
///   not just the parent/clone chain.
public enum MAMESetLayoutPlanner {
    public static func buildGame(for machineName: String, mode: SetMergeMode, biosMode: SetMergeMode, dataset: MAMEDataset) throws -> DATGame {
        let base: DATGame
        switch mode {
        case .split:
            base = try splitGame(for: machineName, dataset: dataset)
        case .nonMerged:
            base = try nonMergedGame(for: machineName, dataset: dataset)
        case .merged:
            base = try mergedGame(for: machineName, dataset: dataset)
        }
        let roms = try foldBiosRoms(into: base.roms, machineName: machineName, biosMode: biosMode, dataset: dataset)
        return DATGame(name: base.name, description: base.description, cloneOf: base.cloneOf, romOf: base.romOf, roms: roms, mergedFamilyMachineNames: base.mergedFamilyMachineNames)
    }

    /// A rom with `merge="..."` (MAME `-listxml`) is identical to one
    /// already in the parent archive — split mode leaves it there rather
    /// than duplicating it here, rather than the previous implementation's
    /// "just return every declared rom" (which happened to work only when
    /// a DAT already pre-filtered clone roms itself). A machine's own
    /// `<rom>` list never includes its BIOS's roms by MAME `-listxml`
    /// convention, so this needs no BIOS-specific handling of its own —
    /// `foldBiosRoms` (driven by `biosMode`, independently) is what adds
    /// them back in when asked to.
    private static func splitGame(for machineName: String, dataset: MAMEDataset) throws -> DATGame {
        guard let machine = dataset.machine(named: machineName) else {
            throw BIOSResolutionError.machineNotFound(machineName)
        }
        // Some real `-listxml` dumps (e.g. `neogeo`'s BIOS chip options)
        // redeclare the exact same rom (same name, same hash) more than
        // once under one machine. Left as-is, that's two logical
        // requirements for a single physical file — one of them can never
        // resolve to "correct" even with a perfect dump. A second identical
        // declaration adds no real requirement, so it's dropped.
        var seen: Set<String> = []
        let ownRoms = machine.roms.filter { $0.mergeName == nil }.filter { seen.insert("\($0.name)|\($0.crc ?? "")|\($0.size)").inserted }
        return game(from: machine, roms: ownRoms)
    }

    /// Self-contained with respect to its *ROM parent/clone* family only —
    /// the machine's own roms plus its full non-BIOS ancestor chain (a
    /// clone's parent, and so on), and every device's roms reachable via
    /// `device_ref` (device roms weren't included before, which meant a
    /// "non-merged" archive wasn't actually complete for a machine that
    /// depends on a shared device — e.g. a CPU/sound sub-board). BIOS
    /// ancestors are deliberately excluded from this chain — whether they
    /// get folded in too is `biosMode`'s job, independently, in
    /// `foldBiosRoms`.
    ///
    /// A real `-listxml` dump has every BIOS-dependent machine redeclare
    /// *each* of its BIOS's selectable `<biosset>` variants as its own
    /// `<rom bios="..." merge="...">` entries (confirmed against a real
    /// MAME 0.288 dump: a Neo-Geo game like `gpilots` declares 45 roms
    /// total, only 11 of which are actually its own — the other 34 are
    /// `merge="..."`-tagged redeclarations of every regional/hacked
    /// `neogeo` BIOS variant). Left unfiltered, this made a "Non-Merged"
    /// game demand all of its BIOS's variants bundled inside its own
    /// archive regardless of `biosMode` — a real, reported bug (see
    /// `CHANGELOG.md`). A `merge="..."` rom is never physically this
    /// machine's own file (`splitGame` already relies on the same rule) —
    /// it's either genuinely shared ROM-family ancestor content (already
    /// covered by that ancestor's own, unmarked entry earlier in `chain`)
    /// or BIOS content, which is `foldBiosRoms`'s job alone.
    private static func nonMergedGame(for machineName: String, dataset: MAMEDataset) throws -> DATGame {
        // "BIOS ancestors are deliberately excluded" means just that —
        // *ancestors*. `resolveDependencies` always includes the requested
        // machine itself as the chain's last element; blindly filtering
        // every `isBios` entry also dropped that last element whenever the
        // requested machine *is itself* a root BIOS (e.g. building
        // `neogeo`'s own standalone entry for Bios merge mode "Split") —
        // leaving it with zero required roms, so a real, correctly-dumped
        // `neogeo.zip` had nothing to match against and was reported as
        // pure "surplus". A real, reported bug (see `CHANGELOG.md`).
        let fullChain = try BIOSResolver.resolveDependencies(of: machineName, in: dataset)
        let chain = fullChain.enumerated().filter { index, machine in
            !machine.isBios || index == fullChain.count - 1
        }.map(\.element)
        guard let target = chain.last ?? dataset.machine(named: machineName) else {
            throw BIOSResolutionError.machineNotFound(machineName)
        }

        var roms: [DATRom] = []
        var indexByName: [String: Int] = [:]
        func add(_ rom: DATRom) {
            if let index = indexByName[rom.name] {
                roms[index] = rom
            } else {
                indexByName[rom.name] = roms.count
                roms.append(rom)
            }
        }

        // A real DAT's ancestors don't just hold "shared" content under
        // `merge=` — a parent also declares its *own* unrelated alternate
        // revision of a rom at the same region/offset a clone fills with
        // its own different revision (confirmed against a real MAME 0.288
        // dump: CPS1's `sf2ee` clone has its own six maincpu roms, e.g.
        // `sf2e_30e.11e`, while its parent `sf2` separately owns a *different*
        // unrelated six, e.g. `sf2e_30g.11e` — alternates at the same PCB
        // position, not shared content). Blindly unioning every ancestor's
        // whole own-rom list (the previous implementation) added the
        // parent's unrelated alternate revision on top of the clone's own,
        // demanding a rom that could never be found in the clone's real
        // archive — a real, reported bug (see `CHANGELOG.md`). The only
        // correct way to know which ancestor rom(s) a clone actually
        // inherits is its own `merge="name"` attribute — look each one up
        // by that exact name instead.
        var ancestorRomsByName: [String: DATRom] = [:]
        for machine in chain where machine.name != target.name {
            for rom in machine.roms where rom.mergeName == nil {
                ancestorRomsByName[rom.name] = rom
            }
        }
        for rom in target.roms {
            if let mergeName = rom.mergeName {
                // Not found in the ROM-family ancestor chain at all usually
                // means it's actually a BIOS-variant redeclaration (see
                // `nonMergedExcludesOwnMergeTaggedRoms`'s own doc comment) —
                // `foldBiosRoms` is what's responsible for BIOS content,
                // independently; silently dropping it here (rather than
                // falling back to the clone's own copy) is what keeps that
                // case excluded.
                if let ancestorRom = ancestorRomsByName[mergeName] { add(ancestorRom) }
            } else {
                add(rom)
            }
        }

        var seenDevices: Set<String> = []
        for machine in chain {
            for deviceRom in deviceRoms(for: machine, dataset: dataset, seenDevices: &seenDevices) { add(deviceRom) }
        }
        return game(from: target, roms: roms)
    }

    private static func deviceRoms(for machine: MAMEMachine, dataset: MAMEDataset, seenDevices: inout Set<String>) -> [DATRom] {
        var result: [DATRom] = []
        for deviceName in machine.deviceRefs {
            guard !seenDevices.contains(deviceName) else { continue }
            seenDevices.insert(deviceName)
            guard let device = dataset.machine(named: deviceName) else { continue }
            result.append(contentsOf: device.roms)
            result.append(contentsOf: deviceRoms(for: device, dataset: dataset, seenDevices: &seenDevices))
        }
        return result
    }

    /// Target-first order: the parent's own ROM wins any name collision
    /// against a clone's entry. A clone rom marked `merge="..."` (or one
    /// that's simply byte-identical even without that marker) is already
    /// covered by the parent's copy and skipped. A clone rom whose name
    /// collides with an already-included rom but whose *content differs* —
    /// the real "hash collision" case older RomCenter versions used to
    /// silently drop or overwrite — is namespaced under the clone's own
    /// name (`cloneName/romName`) instead, so both versions coexist in the
    /// merged archive rather than one disappearing.
    private static func mergedGame(for machineName: String, dataset: MAMEDataset) throws -> DATGame {
        guard let target = dataset.machine(named: machineName) else {
            throw BIOSResolutionError.machineNotFound(machineName)
        }
        let clones = dataset.clones(ofParent: machineName)

        var roms: [DATRom] = []
        var romsByName: [String: DATRom] = [:]
        // `mergeName != nil` on the target's *own* declaration means this
        // rom's real content lives elsewhere — for a machine with a real
        // ROM-family parent that's this target's own parent (handled by
        // the merge-mode-independent BIOS/device chain, not this rom-mode
        // function at all); for a BIOS-dependent, clone-less machine
        // (e.g. any NEOGEO title: no parent/clone relationship between
        // NEOGEO games at all, but every title still `merge=`-tags its own
        // BIOS-variant redeclarations against the shared `neogeo` machine)
        // it's a redeclaration of BIOS content that's `foldBiosRoms`/
        // `biosMode`'s exclusive responsibility (see this file's own
        // doc comment there). `splitGame` (above) and the target-rom
        // branch of `nonMergedGame` (below) already filter these out —
        // jensyleo's own report (2026-08-03), confirmed live: `mergedGame`
        // alone skipped this filter, so switching *Rom* merge mode to
        // Merged (Bios merge mode held constant) injected a clone-less
        // NEOGEO game's BIOS-variant redeclarations into its own expected
        // rom list — something only Bios merge mode should ever affect.
        //
        // A real `-listxml` dump can also redeclare the exact same rom
        // (same name, same hash) twice under one machine's own `<rom>`
        // list — confirmed live (2026-08-04): `neogeo` itself lists
        // `sm1.sm1` once for region `audiobios` and again for region
        // `audiocpu`, byte-identical both times. `splitGame` already
        // guards against this (see its own comment, also citing this
        // exact `neogeo`/`sm1.sm1` case); `mergedGame` never did, so two
        // requirements existed for one physical file — one could never
        // resolve to "correct" even with a perfect dump, surfacing as a
        // spurious yellow "Rom need fix" on `neogeo` under Merged mode
        // while every visibly-listed rom showed green. Skipping an exact
        // repeat of an already-added name closes that gap the same way
        // `splitGame` does.
        for rom in target.roms where rom.mergeName == nil {
            if let existing = romsByName[rom.name],
               existing.crc == rom.crc, existing.md5 == rom.md5, existing.sha1 == rom.sha1, existing.size == rom.size {
                continue
            }
            romsByName[rom.name] = rom
            roms.append(rom)
        }

        for clone in clones {
            for rom in clone.roms {
                if rom.mergeName != nil {
                    continue
                }
                if let existing = romsByName[rom.name] {
                    if existing.crc == rom.crc, existing.md5 == rom.md5, existing.sha1 == rom.sha1, existing.size == rom.size {
                        continue
                    }
                    roms.append(
                        DATRom(
                            name: "\(clone.name)/\(rom.name)", size: rom.size, crc: rom.crc, md5: rom.md5, sha1: rom.sha1,
                            status: rom.status, mergeName: rom.mergeName
                        )
                    )
                } else {
                    romsByName[rom.name] = rom
                    roms.append(rom)
                }
            }
        }
        // Every raw machine name this merged entry drew roms from — see
        // `DATGame.mergedFamilyMachineNames`'s own doc comment for why this
        // exists (a `nodump` rom, real case: `007766.20d.bin`, redeclared
        // identically by `contra` and every one of its clones including
        // `gryzor`, can only ever be located by name, and the user's real
        // dumped file for it isn't guaranteed to sit in the *parent's* own
        // archive at all).
        let familyMachineNames = ([target.name] + clones.map(\.name)).map { $0.lowercased() }
        return game(from: target, roms: roms, mergedFamilyMachineNames: familyMachineNames)
    }

    /// Folds a machine's BIOS roms into `roms`, per `biosMode` — entirely
    /// independent of `mode` above:
    /// - `.split` (the common real-world default): no-op. The BIOS keeps
    ///   its own separate archive; nothing here needs its roms.
    /// - `.merged`: BIOS roms are folded in only for a ROM-family *root*
    ///   (`cloneOf == nil` — a true parent, or a standalone machine) — a
    ///   clone still relies on its own parent for anything shared,
    ///   including (now) the BIOS, matching a real Merged BIOS file's
    ///   placement. `DATLoader` excludes the BIOS's own standalone entry
    ///   entirely in this mode (its roms now only live inside dependents).
    /// - `.nonMerged`: BIOS roms are folded into *every* machine that
    ///   depends on it, root or clone alike — maximally self-contained.
    ///   The BIOS's own standalone entry still exists alongside this (it's
    ///   just also duplicated elsewhere), matching a real Non-Merged set.
    private static func foldBiosRoms(into roms: [DATRom], machineName: String, biosMode: SetMergeMode, dataset: MAMEDataset) throws -> [DATRom] {
        guard biosMode != .split else { return roms }
        guard let machine = dataset.machine(named: machineName) else { return roms }
        if biosMode == .merged, machine.cloneOf != nil {
            return roms
        }
        let biosRoms = try BIOSResolver.resolveDependencies(of: machineName, in: dataset).filter(\.isBios).flatMap(\.roms)
        guard !biosRoms.isEmpty else { return roms }
        var result = roms
        var seenNames = Set(roms.map(\.name))
        for rom in biosRoms where seenNames.insert(rom.name).inserted {
            result.append(rom)
        }
        return result
    }

    private static func game(from machine: MAMEMachine, roms: [DATRom], mergedFamilyMachineNames: [String] = []) -> DATGame {
        DATGame(name: machine.name, description: machine.description, cloneOf: machine.cloneOf, romOf: machine.romOf, roms: roms, mergedFamilyMachineNames: mergedFamilyMachineNames)
    }
}
