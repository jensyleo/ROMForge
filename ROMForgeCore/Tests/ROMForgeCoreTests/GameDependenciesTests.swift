// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("GameNode.dependencyBadges")
struct GameDependenciesTests {
    private func game(
        _ name: String, cloneOf: String? = nil, romOf: String? = nil, disks: [DATDisk] = [],
        hasSamples: Bool = false, deviceRefs: [String] = [], chips: [DATChip] = []
    ) -> DATGame {
        DATGame(
            name: name, description: name, cloneOf: cloneOf, romOf: romOf, roms: [], disks: disks,
            hasSamples: hasSamples, deviceRefs: deviceRefs, chips: chips
        )
    }

    private func node(_ game: DATGame) -> GameNode {
        GameNode(id: game.name, name: game.name, entries: [], aggregateStatus: nil, sourceGame: game)
    }

    @Test("a game with no dependencies gets no badges")
    func noDependencies() {
        let badges = node(game("pacman")).dependencyBadges
        #expect(badges.isEmpty)
    }

    @Test("a BIOS-dependent game gets a BIOS badge naming the required BIOS")
    func biosDependency() {
        var node = node(game("mslug"))
        node.resolvedBiosMachineName = "neogeo"
        let badges = node.dependencyBadges
        #expect(badges.map(\.kind) == [.bios])
        #expect(badges[0].label == "BIOS")
        #expect(badges[0].tooltip == "neogeo")
    }

    @Test("a game with a CHD disk gets a CHD badge naming the disk and its count")
    func chdDependency() {
        let badges = node(game("cubeqst", disks: [DATDisk(name: "cubeqst", sha1: "abc")])).dependencyBadges
        #expect(badges.map(\.kind) == [.chd])
        #expect(badges[0].label == "CHD")
        #expect(badges[0].tooltip == "1 disk: cubeqst")
    }

    @Test("a game with multiple CHD disks names them all and counts them")
    func multipleChdDisks() {
        let disks = [DATDisk(name: "disk1", sha1: "a"), DATDisk(name: "disk2", sha1: "b")]
        let badges = node(game("biggame", disks: disks)).dependencyBadges
        #expect(badges[0].label == "CHD")
        #expect(badges[0].tooltip == "2 disks: disk1, disk2")
    }

    @Test("a game with an unrecognized device_ref gets a Hardware badge naming it under Other")
    func hardwareDependency() {
        let badges = node(game("sf2", deviceRefs: ["ym2151"])).dependencyBadges
        #expect(badges.map(\.kind) == [.hardware])
        #expect(badges[0].label == "Hardware")
        #expect(badges[0].tooltip == "Other: ym2151")
    }

    @Test("a game with several unrecognized device_refs names them all under one Other line")
    func multipleHardwareRefs() {
        let badges = node(game("sf2", deviceRefs: ["ym2151", "okim6295"])).dependencyBadges
        #expect(badges.map(\.kind) == [.hardware])
        #expect(badges[0].label == "Hardware")
        #expect(badges[0].tooltip == "Other: ym2151, okim6295")
    }

    @Test("a game with a known CPU device_ref gets it split into its own CPU: line")
    func knownCPUDeviceRef() {
        let badges = node(game("sf2", deviceRefs: ["z80"])).dependencyBadges
        #expect(badges[0].tooltip == "CPU: z80")
    }

    @Test("a game mixing known CPU and unrecognized device_refs splits them into CPU: and Other: lines")
    func mixedCPUAndOtherDeviceRefs() {
        let badges = node(game("sf2", deviceRefs: ["z80", "ym2151", "m68000", "okim6295"])).dependencyBadges
        #expect(badges[0].tooltip == "CPU: z80, m68000\nOther: ym2151, okim6295")
    }

    @Test("CPU device_ref matching is case-insensitive against the known-CPU list")
    func caseInsensitiveCPUMatch() {
        let badges = node(game("sf2", deviceRefs: ["Z80"])).dependencyBadges
        #expect(badges[0].tooltip == "CPU: Z80")
    }

    @Test("a game with real <chip> CPU data uses it verbatim instead of guessing from device_ref")
    func realChipCPUData() {
        let badges = node(game("dkong", chips: [DATChip(type: "cpu", name: "Zilog Z80")])).dependencyBadges
        #expect(badges.map(\.kind) == [.hardware])
        #expect(badges[0].tooltip == "CPU: Zilog Z80")
    }

    @Test("a game with real <chip> audio data gets a Sound: line")
    func realChipAudioData() {
        let badges = node(game("sf2", chips: [DATChip(type: "audio", name: "Capcom QSound (custom)")])).dependencyBadges
        #expect(badges.map(\.kind) == [.hardware])
        #expect(badges[0].tooltip == "Sound: Capcom QSound (custom)")
    }

    @Test("real <chip> CPU and audio data combine into CPU: and Sound: lines, in that order")
    func realChipCPUAndAudioData() {
        let badges = node(
            game(
                "dkong",
                chips: [
                    DATChip(type: "cpu", name: "Zilog Z80"), DATChip(type: "cpu", name: "Intel 8035"),
                    DATChip(type: "audio", name: "Discrete"),
                ]
            )
        ).dependencyBadges
        #expect(badges[0].tooltip == "CPU: Zilog Z80, Intel 8035\nSound: Discrete")
    }

    @Test("real <chip> CPU data and device_ref both present: device_ref becomes purely Other:, not re-guessed")
    func realChipCPUWithDeviceRef() {
        let badges = node(
            game("dkong", deviceRefs: ["z80"], chips: [DATChip(type: "cpu", name: "Zilog Z80")])
        ).dependencyBadges
        // "z80" isn't dropped as a duplicate of the chip-derived "Zilog Z80" —
        // chip and device_ref are different namespaces, so it surfaces as
        // Other: rather than being cross-referenced away.
        #expect(badges[0].tooltip == "CPU: Zilog Z80\nOther: z80")
    }

    @Test("a Hardware badge appears from real <chip> data alone, even with no device_ref at all")
    func hardwareBadgeFromChipDataWithNoDeviceRef() {
        let badges = node(game("dkong", chips: [DATChip(type: "cpu", name: "Zilog Z80")])).dependencyBadges
        #expect(badges.map(\.kind) == [.hardware])
    }

    @Test("with no real <chip> CPU data, a known device_ref name still falls back to the curated CPU heuristic")
    func fallsBackToHeuristicWithoutChipData() {
        let badges = node(game("sf2", deviceRefs: ["z80", "ym2151"])).dependencyBadges
        #expect(badges[0].tooltip == "CPU: z80\nOther: ym2151")
    }

    @Test("a game declaring samples gets a Samples badge")
    func samplesDependency() {
        let badges = node(game("dkong", hasSamples: true)).dependencyBadges
        #expect(badges.map(\.kind) == [.samples])
        #expect(badges[0].tooltip == "")
    }

    @Test("a clone gets no dependency badge of its own — that's the Family column's job")
    func cloneGetsNoBadge() {
        let badges = node(game("sf2a", cloneOf: "sf2")).dependencyBadges
        #expect(badges.isEmpty)
    }

    @Test("a game can carry several dependency badges at once, in a fixed order")
    func combinedDependencies() {
        var built = node(
            game(
                "cloneWithEverything", cloneOf: "parent", disks: [DATDisk(name: "d1", sha1: "a")],
                hasSamples: true, deviceRefs: ["ym2151"]
            )
        )
        built.resolvedBiosMachineName = "neogeo"
        let badges = built.dependencyBadges
        #expect(badges.map(\.kind) == [.bios, .chd, .hardware, .samples])
    }

    @Test("the synthetic surplus-files bucket never gets dependency badges")
    func surplusBucketHasNoBadges() {
        let node = GameNode(
            id: "surplus", name: "Surplus files", entries: [], aggregateStatus: .surplus, isSurplusBucket: true
        )
        #expect(node.dependencyBadges.isEmpty)
    }

    @Test("a CHD disk row never gets dependency badges of its own")
    func diskRowHasNoBadges() {
        let node = GameNode(
            id: "cubeqst-disk", name: "cubeqst", entries: [], aggregateStatus: .correct, isDiskRow: true,
            sourceGame: game("cubeqst", disks: [DATDisk(name: "cubeqst", sha1: "abc")])
        )
        #expect(node.dependencyBadges.isEmpty)
    }
}
