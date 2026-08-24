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
        hasSamples: Bool = false, deviceRefs: [String] = []
    ) -> DATGame {
        DATGame(
            name: name, description: name, cloneOf: cloneOf, romOf: romOf, roms: [], disks: disks,
            hasSamples: hasSamples, deviceRefs: deviceRefs
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
        #expect(badges[0].tooltip == "Requires BIOS: neogeo")
    }

    @Test("a game with a CHD disk gets a CHD badge naming the disk and its count")
    func chdDependency() {
        let badges = node(game("cubeqst", disks: [DATDisk(name: "cubeqst", sha1: "abc")])).dependencyBadges
        #expect(badges.map(\.kind) == [.chd])
        #expect(badges[0].label == "CHD")
        #expect(badges[0].tooltip == "Uses CHD (1 disk(s)): cubeqst")
    }

    @Test("a game with multiple CHD disks names them all and counts them")
    func multipleChdDisks() {
        let disks = [DATDisk(name: "disk1", sha1: "a"), DATDisk(name: "disk2", sha1: "b")]
        let badges = node(game("biggame", disks: disks)).dependencyBadges
        #expect(badges[0].label == "CHD")
        #expect(badges[0].tooltip == "Uses CHD (2 disk(s)): disk1, disk2")
    }

    @Test("a game with a device_ref gets a Hardware badge naming it")
    func hardwareDependency() {
        let badges = node(game("sf2", deviceRefs: ["ym2151"])).dependencyBadges
        #expect(badges.map(\.kind) == [.hardware])
        #expect(badges[0].label == "Hardware")
        #expect(badges[0].tooltip == "Uses hardware: ym2151")
    }

    @Test("a game with several device_refs names them all in one Hardware badge")
    func multipleHardwareRefs() {
        let badges = node(game("sf2", deviceRefs: ["ym2151", "okim6295"])).dependencyBadges
        #expect(badges.map(\.kind) == [.hardware])
        #expect(badges[0].label == "Hardware")
        #expect(badges[0].tooltip == "Uses hardware: ym2151, okim6295")
    }

    @Test("a game declaring samples gets a Samples badge")
    func samplesDependency() {
        let badges = node(game("dkong", hasSamples: true)).dependencyBadges
        #expect(badges.map(\.kind) == [.samples])
        #expect(badges[0].tooltip == "Uses samples")
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
