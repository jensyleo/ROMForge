// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("MAMESetLayoutPlanner")
struct MAMESetLayoutPlannerTests {
    private func rom(_ name: String, size: Int64 = 1, crc: String? = nil, mergeName: String? = nil) -> DATRom {
        DATRom(name: name, size: size, crc: crc, md5: nil, sha1: nil, mergeName: mergeName)
    }

    /// `isBios` defaults to inferring from `romOf`/`cloneOf` absence — a
    /// reasonable shorthand for most test fixtures (only the fixture's own
    /// "bios" machine has neither), but wrong for a standalone machine that
    /// isn't a BIOS at all (e.g. one that only references a device) —
    /// pass `isBios` explicitly for those.
    private func machine(_ name: String, cloneOf: String? = nil, romOf: String? = nil, roms: [DATRom], deviceRefs: [String] = [], isDevice: Bool = false, isBios: Bool? = nil) -> MAMEMachine {
        MAMEMachine(
            name: name, description: name, year: "", manufacturer: "",
            cloneOf: cloneOf, romOf: romOf, isBios: isBios ?? (romOf == nil && cloneOf == nil && !isDevice),
            isDevice: isDevice, biosSets: [], roms: roms, disks: [], deviceRefs: deviceRefs
        )
    }

    // bios: shared.bin (bios version)
    // parent (romof: bios): parent-only.bin, shared.bin (parent overrides bios's shared.bin)
    // clone (cloneof/romof: parent): clone-only.bin, plus merge=-tagged redeclarations
    // of the parent's own roms it shares — matching real MAME `-listxml`
    // convention, where a clone always marks exactly which ancestor roms it
    // inherits rather than inheriting silently.
    private var dataset: MAMEDataset {
        MAMEDataset(machines: [
        machine("bios", roms: [rom("shared.bin")]),
        machine("parent", romOf: "bios", roms: [rom("parent-only.bin"), rom("shared.bin", size: 2)]),
        machine("clone", cloneOf: "parent", romOf: "parent", roms: [
            rom("clone-only.bin"),
            rom("parent-only.bin", mergeName: "parent-only.bin"),
            rom("shared.bin", size: 2, mergeName: "shared.bin"),
        ]),
        ])
    }

    @Test("split mode keeps only the machine's own declared roms")
    func splitKeepsOwnRomsOnly() throws {
        let game = try MAMESetLayoutPlanner.buildGame(for: "clone", mode: .split, biosMode: .split, dataset: dataset)
        #expect(game.roms.map(\.name) == ["clone-only.bin"])
    }

    @Test("non-merged mode includes the full ancestor chain, descendant rom wins on name collision")
    func nonMergedIncludesFullChainWithDescendantPrecedence() throws {
        let game = try MAMESetLayoutPlanner.buildGame(for: "clone", mode: .nonMerged, biosMode: .split, dataset: dataset)

        // Order isn't a real contract here (this is a set of roms to check
        // on disk, not an archive layout) — bios's exclusion from this
        // family chain (now a fully independent `biosMode` concern) shifts
        // exactly *where* `shared.bin` first gets inserted, without
        // changing the actual expected content at all.
        #expect(Set(game.roms.map(\.name)) == ["shared.bin", "parent-only.bin", "clone-only.bin"])
        let sharedRom = try #require(game.roms.first { $0.name == "shared.bin" })
        #expect(sharedRom.size == 2, "parent's shared.bin must win over bios's, since parent is closer to the target")
    }

    @Test("non-merged mode does not pull in an ancestor's own rom the clone doesn't reference via merge=, even when the clone declares its own different rom for the same logical slot")
    func nonMergedDoesNotOverRequireUnreferencedAncestorRoms() throws {
        // Real bug found against a real MAME 0.288 dump (2026-07-27): CPS1's
        // `sf2ee` clone declares its own six maincpu program roms (a
        // distinct revision, e.g. `sf2e_30e.11e`), while its parent `sf2`
        // separately owns a completely different, unrelated six roms at the
        // very same region/offsets (e.g. `sf2e_30g.11e`) — two alternate
        // revisions of the same PCB position, not shared content. The old
        // implementation blindly unioned every ancestor's whole own-rom
        // list, so `sf2ee`'s built game demanded the parent's unrelated
        // "g"-revision roms too, on top of its own genuine six — a rom that
        // could never be found in `sf2ee`'s real archive, reporting a
        // correctly-dumped clone as red/incomplete. Only a rom the clone
        // actually references by `merge="name"` should ever be pulled in
        // from an ancestor.
        let parent = machine("altparent", roms: [rom("parent-revA.bin", crc: "aaaaaaaa"), rom("shared-plds.bin", crc: "cccccccc")], isBios: false)
        let clone = machine("altclone", cloneOf: "altparent", romOf: "altparent", roms: [
            rom("clone-revB.bin", crc: "bbbbbbbb"),
            rom("shared-plds.bin", crc: "cccccccc", mergeName: "shared-plds.bin"),
        ])
        let extendedDataset = MAMEDataset(machines: [parent, clone])

        let game = try MAMESetLayoutPlanner.buildGame(for: "altclone", mode: .nonMerged, biosMode: .split, dataset: extendedDataset)
        #expect(
            Set(game.roms.map(\.name)) == ["clone-revB.bin", "shared-plds.bin"],
            "the parent's unrelated own alternate-revision rom must not be required — the clone never referenced it via merge="
        )
    }

    @Test("non-merged mode excludes a machine's own merge=-tagged roms, e.g. BIOS-selectable variants it redeclares from its BIOS")
    func nonMergedExcludesOwnMergeTaggedRoms() throws {
        // Real bug found against a real MAME 0.288 dump (2026-07-24): a
        // Neo-Geo game like `gpilots` redeclares every one of its `neogeo`
        // BIOS's selectable `<biosset>` variants as its own `<rom bios="..."
        // merge="...">` entries — 34 of them, alongside its 11 truly own
        // roms. Under Non-Merged mode this made every dependent game demand
        // its BIOS's entire variant set bundled inside its own archive,
        // regardless of `biosMode` (which is supposed to govern BIOS
        // folding independently, via `foldBiosRoms`). A `merge="..."` rom is
        // never physically this machine's own file — same rule `splitGame`
        // already applies — so it must be excluded here too.
        let biosVariantRom = rom("neogeo-variant.bin", mergeName: "neogeo-variant.bin")
        let dependent = machine("neogeodep", romOf: "bios", roms: [rom("own.bin"), biosVariantRom], isBios: false)
        let extendedDataset = MAMEDataset(machines: dataset.machines + [dependent])

        let game = try MAMESetLayoutPlanner.buildGame(for: "neogeodep", mode: .nonMerged, biosMode: .split, dataset: extendedDataset)
        #expect(game.roms.map(\.name) == ["own.bin"], "the merge=-tagged BIOS-variant redeclaration must not be required inside this game's own archive")
    }

    @Test("non-merged mode still includes a root BIOS machine's own roms when building the BIOS's own standalone entry")
    func nonMergedIncludesRootBiosOwnRoms() throws {
        // Real bug found right after the fix above (2026-07-24): excluding
        // BIOS *ancestors* from the chain (`!$0.isBios`) also excluded the
        // chain's last element when the requested machine *is itself* the
        // root BIOS (`resolveDependencies` always includes the requested
        // machine as the chain's own last element) — e.g. building
        // `neogeo`'s own standalone entry for Bios merge mode "Split" ended
        // up with zero required roms, so a real, correctly-dumped
        // `neogeo.zip` matched nothing and was reported as pure "surplus".
        #expect(Set(try MAMESetLayoutPlanner.buildGame(for: "bios", mode: .nonMerged, biosMode: .split, dataset: dataset).roms.map(\.name)) == ["shared.bin"])
    }

    @Test("merged mode excludes a machine's own merge=-tagged roms too, e.g. BIOS-selectable variants it redeclares from its BIOS")
    func mergedExcludesOwnMergeTaggedRoms() throws {
        // Real bug found live (2026-08-03), sibling of the identical
        // Non-Merged fix above: `mergedGame` alone (unlike `splitGame` and
        // the target-rom branch of `nonMergedGame`) never filtered
        // `mergeName != nil` off the target's own roms before including
        // them — so switching *Rom* merge mode to Merged (Bios merge mode
        // held constant) injected a clone-less Neo-Geo game's BIOS-variant
        // redeclarations into its own expected rom list, something only
        // Bios merge mode should ever affect.
        let biosVariantRom = rom("neogeo-variant.bin", mergeName: "neogeo-variant.bin")
        let dependent = machine("neogeodep", romOf: "bios", roms: [rom("own.bin"), biosVariantRom], isBios: false)
        let extendedDataset = MAMEDataset(machines: dataset.machines + [dependent])

        let game = try MAMESetLayoutPlanner.buildGame(for: "neogeodep", mode: .merged, biosMode: .split, dataset: extendedDataset)
        #expect(game.roms.map(\.name) == ["own.bin"], "the merge=-tagged BIOS-variant redeclaration must not be required inside this clone-less game's own archive under Merged mode either")
    }

    @Test("merged mode combines the parent with every direct clone into one game")
    func mergedCombinesParentAndClones() throws {
        let game = try MAMESetLayoutPlanner.buildGame(for: "parent", mode: .merged, biosMode: .split, dataset: dataset)
        #expect(game.roms.map(\.name) == ["parent-only.bin", "shared.bin", "clone-only.bin"])
    }

    @Test("merged mode keeps the parent's own rom on a name collision, and preserves (doesn't drop) the clone's differing version")
    func mergedKeepsParentRomOnCollisionAndPreservesCloneVersion() throws {
        // Real bug this guards against: older RomCenter versions silently
        // deleted/overwrote one version when a parent and clone declared
        // the same filename with different content. ClrMamePro's fix (and
        // ours) is to namespace the clone's colliding file instead of
        // dropping it.
        let collidingClone = machine("collider", cloneOf: "parent", romOf: "parent", roms: [rom("shared.bin", size: 999, crc: "deadbeef")])
        let extendedDataset = MAMEDataset(machines: dataset.machines + [collidingClone])

        let game = try MAMESetLayoutPlanner.buildGame(for: "parent", mode: .merged, biosMode: .split, dataset: extendedDataset)

        let parentShared = try #require(game.roms.first { $0.name == "shared.bin" })
        #expect(parentShared.size == 2, "the parent's own rom is unchanged")

        let renamedClone = try #require(game.roms.first { $0.name == "collider/shared.bin" })
        #expect(renamedClone.size == 999)
        #expect(renamedClone.crc == "deadbeef", "the clone's differing content must survive, just namespaced — not dropped")
    }

    @Test("merged mode does not duplicate a clone rom that's byte-identical to the parent's, even without a merge= marker")
    func mergedSkipsTrulyIdenticalCloneRoms() throws {
        let identicalClone = machine("twin", cloneOf: "parent", romOf: "parent", roms: [rom("shared.bin", size: 2)])
        let extendedDataset = MAMEDataset(machines: dataset.machines + [identicalClone])

        let game = try MAMESetLayoutPlanner.buildGame(for: "parent", mode: .merged, biosMode: .split, dataset: extendedDataset)
        #expect(game.roms.filter { $0.name == "shared.bin" || $0.name == "twin/shared.bin" }.count == 1, "identical content shouldn't be duplicated under a namespaced name")
    }

    @Test("split mode excludes a clone rom marked merge=, since it's already covered by the parent archive")
    func splitExcludesRomsMarkedAsMerged() throws {
        let cloneWithMergeMarker = machine(
            "clone2", cloneOf: "parent", romOf: "parent",
            roms: [rom("clone-only.bin"), rom("shared.bin", size: 2, mergeName: "shared.bin")]
        )
        let extendedDataset = MAMEDataset(machines: dataset.machines + [cloneWithMergeMarker])

        let game = try MAMESetLayoutPlanner.buildGame(for: "clone2", mode: .split, biosMode: .split, dataset: extendedDataset)
        #expect(game.roms.map(\.name) == ["clone-only.bin"], "the merge=-marked shared.bin belongs to the parent archive, not this one")
    }

    @Test("non-merged mode includes a device's roms too, not just the BIOS/parent chain")
    func nonMergedIncludesDeviceRoms() throws {
        // Real gap this guards against: a "non-merged" (fully self-
        // contained) archive that omits a shared device's roms (e.g. a
        // CPU/sound sub-board) isn't actually self-contained.
        let device = machine("shared_cpu", roms: [rom("device.bin")], isDevice: true)
        let machineWithDevice = machine("withdevice", roms: [rom("own.bin")], deviceRefs: ["shared_cpu"], isBios: false)
        let extendedDataset = MAMEDataset(machines: dataset.machines + [device, machineWithDevice])

        let game = try MAMESetLayoutPlanner.buildGame(for: "withdevice", mode: .nonMerged, biosMode: .split, dataset: extendedDataset)
        #expect(game.roms.map(\.name).sorted() == ["device.bin", "own.bin"])
    }

    @Test("throws when the requested machine does not exist")
    func throwsWhenMachineNotFound() {
        #expect(throws: BIOSResolutionError.machineNotFound("ghost")) {
            try MAMESetLayoutPlanner.buildGame(for: "ghost", mode: .split, biosMode: .split, dataset: dataset)
        }
    }
}
