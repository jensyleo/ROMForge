// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import ROMForgeCore
import SwiftUI

/// The fixed choices for "Platform" in `AddSystemSheet` — jensyleo's own
/// request (2026-09-23), start of real NES support: this used to be plain
/// free text (e.g. "Nintendo"), used only for grouping systems in the
/// sidebar. Now it's ALSO what decides which "generate a DAT for me" button
/// (if any) makes sense to offer, and what `RomSystem.isMAMEStyle` gets set
/// to — a fixed list reads clearly ("what kind of system is this") in a way
/// free text never could, and avoids ever showing a MAME-only action for a
/// console/PC system, which is exactly what looked like "this app is
/// MAME-only" before this change.
///
/// Narrowed further to a short, concrete platform list — jensyleo's own
/// request (2026-10-01): "name" is now purely a free-text label the user
/// picks for themselves (e.g. "My NES Collection"), while THIS picker is
/// the one standardized, fixed-vocabulary field that actually decides
/// behavior (MAME-style vs console-style). Real bug this closes: the
/// previous list defaulted to `.arcade`, so a system added without
/// deliberately changing the picker silently became MAME-style and never
/// showed up under Settings → Systems → Consoles — not a DAT-loading gate,
/// just a silent miscategorization waiting to happen. The default below is
/// `.other` instead, so nothing is ever silently mis-added as MAME.
///
/// Only `.mame` is treated as MAME-style — every other case is a plain
/// "point me at a DAT you already have" system, since ROMForge has no known
/// way to *generate* a DAT for any of them (no console emulator has an
/// equivalent to `mame -listxml`; those DATs are downloaded ready-made from
/// No-Intro/Redump/TOSEC). Deliberately NOT claiming a fake "Generate from
/// Installed <emulator>…" for any of these — jensyleo's own concern, having
/// no idea whether even Homebrew has a matching package for every possible
/// console: better to offer nothing than to promise something that might
/// not exist.
enum SystemCategoryKind: String, CaseIterable, Identifiable {
    case nes = "NES"
    case snes = "SNES"
    /// SNES hacks with MSU-1 audio (patched ROM + `.msu` + `.pcm` tracks).
    /// Kept apart from "SNES" so patched ROMs never mix with verified ones;
    /// uses the same No-Intro SNES DAT to name the base game.
    case snesMSU1 = "SNES-MSU1"
    case n64 = "N64"
    case gb = "Game Boy"
    case gbc = "Game Boy Color"
    case gba = "GBA"
    case virtualBoy = "Virtual Boy"
    case pokemonMini = "Pokemon Mini"
    case fds = "Famicom Disk System"
    case nds = "NDS"
    case dsi = "DSi"
    case n3ds = "3DS"
    case gamecube = "GameCube"
    case wii = "Wii"
    case wiiU = "Wii U"
    case switchConsole = "Switch"
    case segaSG1000 = "SEGA SG-1000"
    case segaMasterSystem = "SEGA Master System"
    case segaGameGear = "SEGA Game Gear"
    case segaGenesis = "SEGA Genesis"
    case sega32X = "SEGA 32X"
    case segaCD = "SEGA CD"
    case segaSaturn = "SEGA Saturn"
    case segaDreamcast = "SEGA Dreamcast"
    case sonyPS1 = "Sony PlayStation"
    case sonyPS2 = "Sony PlayStation 2"
    case sonyPSP = "Sony PSP"
    case sonyPS3 = "Sony PlayStation 3"
    case sonyPS4 = "Sony PlayStation 4"
    case xbox = "Microsoft Xbox"
    case xbox360 = "Microsoft Xbox 360"
    case xboxOne = "Microsoft Xbox One"
    case atari2600 = "Atari 2600"
    case atari5200 = "Atari 5200"
    case atari7800 = "Atari 7800"
    case atariJaguar = "Atari Jaguar"
    case atariLynx = "Atari Lynx"
    case atariST = "Atari ST"
    case atari8bit = "Atari 8-bit"
    case pcEngine = "PC Engine"
    case pcEngineCD = "PC Engine CD"
    case superGrafx = "SuperGrafx"
    case pcfx = "PC-FX"
    case pc98 = "PC-98"
    case ngp = "Neo Geo Pocket"
    case ngpc = "Neo Geo Pocket Color"
    case neoGeoCD = "Neo Geo CD"
    case wonderSwan = "WonderSwan"
    case wonderSwanColor = "WonderSwan Color"
    case colecoVision = "ColecoVision"
    case intellivision = "Intellivision"
    case vectrex = "Vectrex"
    case odyssey2 = "Magnavox Odyssey 2"
    case channelF = "Fairchild Channel F"
    case supervision = "Watara Supervision"
    case megaDuck = "Mega Duck"
    case gameAndWatch = "Game & Watch"
    case scv = "Epoch Super Cassette Vision"
    case threeDO = "3DO"
    case cdi = "Philips CD-i"
    case c64 = "Commodore 64"
    case amiga = "Commodore Amiga"
    case vic20 = "Commodore VIC-20"
    case plus4 = "Commodore Plus/4"
    case c128 = "Commodore 128"
    case cbmPET = "Commodore PET"
    case zxSpectrum = "ZX Spectrum"
    case zx81 = "ZX81"
    case amstradCPC = "Amstrad CPC"
    case msx = "MSX"
    case msx2 = "MSX2"
    case appleII = "Apple II"
    case macintosh = "Apple Macintosh"
    case dos = "DOS"
    case x68000 = "Sharp X68000"
    case sharpX1 = "Sharp X1"
    case fmTowns = "FM Towns"
    case thomson = "Thomson MO/TO"
    case scummvm = "ScummVM"
    case mame = "MAME"
    case other = "Otros"
    var id: String { rawValue }

    /// How a platform's games are stored — decides what the app can
    /// promise: cartridge games are small single files (the case ROMForge
    /// already handles well), disc games can be several files per game
    /// (.cue + .bin) and are not verified end to end yet, and "catalog
    /// only" platforms (huge images, no usable macOS emulator) can be
    /// audited against a DAT but never launched.
    enum Media { case cartridge, disc, computer, catalogOnly, arcade, unknown }

    var media: Media {
        switch self {
        case .nes, .snes, .snesMSU1, .n64, .gb, .gbc, .gba, .virtualBoy, .pokemonMini, .fds, .nds, .dsi, .n3ds,
             .segaSG1000, .segaMasterSystem, .segaGameGear, .segaGenesis, .sega32X, .atari2600, .atari5200, .atari7800, .atariJaguar, .atariLynx, .pcEngine, .superGrafx, .ngp, .ngpc, .wonderSwan, .wonderSwanColor, .colecoVision, .intellivision, .vectrex, .odyssey2, .channelF, .supervision, .megaDuck, .gameAndWatch, .scv: return .cartridge
        case .segaCD, .segaSaturn, .segaDreamcast, .sonyPS1, .sonyPS2, .sonyPSP, .xbox, .gamecube, .wii, .wiiU, .pcEngineCD, .pcfx, .neoGeoCD, .threeDO, .cdi: return .disc
        case .sonyPS3, .sonyPS4, .xbox360, .xboxOne, .switchConsole: return .catalogOnly
        case .atariST, .atari8bit, .pc98, .c64, .amiga, .vic20, .plus4, .c128, .cbmPET, .zxSpectrum, .zx81, .amstradCPC, .msx, .msx2, .appleII, .macintosh, .dos, .x68000, .sharpX1, .fmTowns, .thomson, .scummvm: return .computer
        case .mame: return .arcade
        case .other: return .unknown
        }
    }

    /// Picker section title.
    var group: String {
        switch self {
        case .nes, .snes, .snesMSU1, .n64, .gb, .gbc, .gba, .virtualBoy, .pokemonMini, .fds, .nds, .dsi, .n3ds, .gamecube, .wii, .wiiU, .switchConsole: return "Nintendo"
        case .segaSG1000, .segaMasterSystem, .segaGameGear, .segaGenesis, .sega32X, .segaCD, .segaSaturn, .segaDreamcast: return "SEGA"
        case .sonyPS1, .sonyPS2, .sonyPSP, .sonyPS3, .sonyPS4: return "Sony"
        case .xbox, .xbox360, .xboxOne: return "Microsoft"
        case .atari2600, .atari5200, .atari7800, .atariJaguar, .atariLynx, .atariST, .atari8bit: return "Atari"
        case .pcEngine, .pcEngineCD, .superGrafx, .pcfx, .pc98: return "NEC"
        case .ngp, .ngpc, .neoGeoCD: return "SNK"
        case .wonderSwan, .wonderSwanColor: return "Bandai"
        case .colecoVision, .intellivision, .vectrex, .odyssey2, .channelF, .supervision, .megaDuck, .gameAndWatch, .scv, .threeDO, .cdi: return "Other consoles"
        case .c64, .amiga, .vic20, .plus4, .c128, .cbmPET, .zxSpectrum, .zx81, .amstradCPC, .msx, .msx2, .appleII, .macintosh, .dos, .x68000, .sharpX1, .fmTowns, .thomson, .scummvm: return "Computers"
        case .mame: return "Arcade"
        case .other: return "Other"
        }
    }

    /// `false` for catalog-only platforms — there is no usable emulator to
    /// launch their games with on macOS, so Play is never offered.
    var canPlay: Bool { media != .catalogOnly }

    /// Which DAT family normally covers this platform, plus any honest
    /// caveat — shown under the platform picker in "Add System".
    var datHint: String? {
        if self == .switchConsole {
            return "Catalog only — there is no emulator ROMForge can launch and no Redump DAT for Switch; look for a DAT on Dat-o-Matic (datomatic.no-intro.org). Images are very large."
        }
        switch media {
        case .cartridge: return "Cartridge platform — use a No-Intro DAT (Dat-o-Matic, datomatic.no-intro.org)."
        case .disc: return "Disc platform — use a Redump DAT (redump.org, Downloads page). Games made of several files (.cue + .bin) and large images are not verified end to end yet; scanning can be slow on a network volume."
        case .catalogOnly: return "Catalog only — you can audit and organize against a Redump DAT (redump.org), but there is no emulator to play these on macOS and the images are very large (scans can take a long time)."
        case .computer: return "Computer platform — No-Intro covers some of these, otherwise TOSEC (tosecdev.org). Games are often disk or tape images, sometimes several files; ROMForge matches best when each game is one file."
        case .arcade, .unknown: return nil
        }
    }
}

struct AddSystemSheet: View {
    let onAdd: (RomSystem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category: SystemCategoryKind = .other
    @State private var datURL: URL?
    @State private var romFolderURLs: [URL] = []
    /// jensyleo's own request (2026-08-13): "agregar la opción de sacar el
    /// DAT del binario del MAME instalado" — see `MAMEDATGenerator`'s own
    /// doc comment for the actual `mame -listxml` process and precedent
    /// (ClrMamePro's `engine.cfg`, confirmed by research the same day).
    /// These three drive the button's own progress/error UI while
    /// generation runs, which can genuinely take tens of seconds to a
    /// couple of minutes for a full driver list — no known total ahead of
    /// time, so `generatedDATBytes` is a live counter, not a percentage.
    @State private var isGeneratingDAT = false
    @State private var generatedDATBytes = 0
    @State private var generateDATErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add System")
                .font(.headline)

            TextField("Name (e.g. My SNES Collection)", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Platform", selection: $category) {
                ForEach(["Nintendo", "SEGA", "Sony", "Microsoft", "Atari", "NEC", "SNK", "Bandai", "Other consoles", "Computers", "Arcade", "Other"], id: \.self) { group in
                    Section(group) {
                        ForEach(SystemCategoryKind.allCases.filter { $0.group == group }) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Text("Decides which of the DAT options below make sense to offer, and groups this system in the sidebar — \"Name\" is just your own label.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let hint = category.datHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(category.media == .cartridge ? Color.secondary : Color.orange)
            }

            HStack {
                Button("Select DAT…") { chooseDAT() }
                // Only ever offered for MAME — see `SystemCategoryKind`'s
                // own doc comment for why every other category only ever
                // gets "Select DAT…". Also requires a real MAME executable
                // already configured (Settings → Systems → MAME) — nothing
                // to generate from otherwise. Disabled while a generation is
                // already running, rather than letting a second click start
                // a second overlapping `mame -listxml` process.
                if category == .mame, MAMELaunchSettings.isInstalled {
                    Button("Generate from Installed MAME…") { generateDATFromMAME() }
                        .disabled(isGeneratingDAT)
                }
                if isGeneratingDAT {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running mame -listxml… \(generatedDATBytes / 1024) KB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(datURL?.lastPathComponent ?? "No DAT selected")
                        .foregroundStyle(.secondary)
                }
            }
            if let generateDATErrorMessage {
                Text(generateDATErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("ROM Folders").font(.subheadline)
                    Spacer()
                    Button("Add Folder…") { addROMFolder() }
                }
                if romFolderURLs.isEmpty {
                    Text("No folders selected — a collection can span more than one.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    List {
                        ForEach(romFolderURLs, id: \.self) { url in
                            HStack {
                                Text(url.path)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    romFolderURLs.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 80)
                }
            }

            // Rom/Bios merge mode used to be configured here per system —
            // it's now one global setting (Settings → Systems → "MAME")
            // that applies to every MAME system uniformly, since it isn't
            // really a per-DAT preference (see `RomSystem`'s own doc
            // comment for the full reasoning). Only relevant for MAME —
            // real gap found live by jensyleo (2026-09-23): this used to
            // show unconditionally, even while adding a plain console DAT
            // (e.g. a No-Intro NES set) that has no concept of Rom/Bios
            // merge mode whatsoever.
            if category == .mame {
                Text("MAME's Rom/Bios merge mode is configured once for every system, in Settings (⌘,) → Systems.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || datURL == nil || romFolderURLs.isEmpty)
            }
        }
        .padding()
        .frame(width: 520, height: 460)
    }

    private func chooseDAT() {
        let panel = NSOpenPanel()
        // No content-type filter: DAT files show up with all sorts of
        // extensions in the wild (.dat, .xml, sometimes none at all), and a
        // ".dat" file's UTI doesn't conform to public.xml even though its
        // content is XML — restricting to .xml silently hid .dat files from
        // the picker entirely. Real validation happens when it's parsed.
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a DAT (.dat or .xml — Logiqx/ClrMamePro or MAME -listxml, auto-detected)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Copied into ROMForge's own storage right away — jensyleo's own
        // report (2026-09-29): `datURL` used to just be this external path
        // itself, so moving/renaming the original file afterward broke the
        // system entirely ("Scan Failed... no such file"). See
        // `DATStorageLocation`'s own doc comment.
        datURL = DATStorageLocation.copy(from: url)
        if name.isEmpty {
            name = url.deletingPathExtension().lastPathComponent
        }
    }

    /// Runs the configured MAME executable's own `-listxml` and uses its
    /// output directly as this system's DAT — see `MAMEDATGenerator`'s own
    /// doc comment for the process itself and why this is worth having
    /// (ClrMamePro has direct precedent for it, per research done the same
    /// day this was requested). Names the system "MAME" if nothing's been
    /// typed yet, same convention `chooseDAT()` already uses for a
    /// manually-picked file. Only ever reachable with `category == .arcade`
    /// already selected (see the button's own condition above).
    private func generateDATFromMAME() {
        isGeneratingDAT = true
        generateDATErrorMessage = nil
        generatedDATBytes = 0
        Task {
            do {
                let url = try await MAMEDATGenerator.generate { bytes in
                    Task { @MainActor in generatedDATBytes = bytes }
                }
                isGeneratingDAT = false
                datURL = url
                if name.isEmpty { name = "MAME" }
            } catch {
                isGeneratingDAT = false
                generateDATErrorMessage = String(describing: error)
            }
        }
    }

    private func addROMFolder() {
        romFolderURLs.append(contentsOf: ROMFolderPicker.pickFolders(existing: romFolderURLs))
    }

    private func add() {
        guard let datURL, !romFolderURLs.isEmpty else { return }
        onAdd(
            RomSystem(
                name: name.trimmingCharacters(in: .whitespaces),
                category: category.rawValue,
                datURL: datURL,
                romFolderURLs: romFolderURLs,
                isMAMEStyle: category == .mame,
                // The settings every console system had to be switched to by hand
                // after being added (rename suggestions at 50%, region hints).
                // MAME-style systems ignore both, so they keep the plain defaults.
                similarNameFixEnabled: category != .mame,
                similarNameFixThreshold: category == .mame ? 0.80 : 0.50,
                regionQualityHintsEnabled: category != .mame
            )
        )
        dismiss()
    }
}

/// The user's own region-quality notes (`RegionQualityNotes.json` in
/// Application Support/ROMForge) — see `RegionQualityOverrides` (Core) for
/// the format. Cached in memory; the file's modification date is checked at
/// most every 2 seconds so lookups from table rows stay cheap and an edit
/// is picked up without restarting the app.
@MainActor
enum RegionQualityOverrideStore {
    static let fileName = "RegionQualityNotes.json"
    static let builtInExportName = "RegionQualityNotes-builtin.json"

    private(set) static var notes: [RegionQualityNote] = []
    private(set) static var issues: [String] = []
    private static var fileExists = false
    private static var lastModified: Date?
    private static var lastCheck = Date.distantPast
    private static var loaded = false

    static var folderURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ROMForge", isDirectory: true)
    }

    static var fileURL: URL { folderURL.appendingPathComponent(fileName) }

    /// Notes to hand to `RegionQualityNotes.note(forGameName:platform:overrides:)`.
    static var current: [RegionQualityNote] {
        refreshIfNeeded()
        return notes
    }

    static var statusText: String {
        refreshIfNeeded()
        guard fileExists else { return "No notes file yet — only the built-in notes are used." }
        return "\(notes.count) note\(notes.count == 1 ? "" : "s") loaded from \(fileName)."
    }

    static var currentIssues: [String] {
        refreshIfNeeded()
        return issues
    }

    private static func refreshIfNeeded() {
        let now = Date()
        guard !loaded || now.timeIntervalSince(lastCheck) > 2 else { return }
        lastCheck = now
        let modified = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
        guard !loaded || modified != lastModified else { return }
        reload()
    }

    static func reload() {
        loaded = true
        lastCheck = Date()
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        lastModified = attributes?[.modificationDate] as? Date
        guard let data = try? Data(contentsOf: fileURL) else {
            fileExists = false; notes = []; issues = []
            return
        }
        fileExists = true
        let result = RegionQualityOverrides.parse(data: data, knownPlatforms: Set(SystemCategoryKind.allCases.map(\.rawValue)))
        notes = result.notes
        issues = result.issues
    }

    /// Creates the notes file (if it does not exist yet) with one clearly
    /// marked example entry that matches no real game, and returns its URL.
    @discardableResult
    static func createTemplateIfNeeded() throws -> URL {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return fileURL }
        let example = RegionQualityNote(
            gameFamily: "EXAMPLE - replace or delete this entry",
            platform: "SNES",
            alternateTitles: ["Another Title Of The Same Game"],
            recommendedRegion: "Japan",
            tiedRegions: ["USA"],
            reason: "One or two sentences, in your own words, on why these regions are the best versions.",
            sourceURL: "https://example.com/where-you-read-it",
            sourceLicense: "Own summary",
            consultedDate: ISO8601DateFormatter().string(from: Date()).prefix(10).description
        )
        try RegionQualityOverrides.encode(notes: [example]).write(to: fileURL, options: .atomic)
        reload()
        return fileURL
    }

    /// Writes every built-in note to a separate reference file (never read
    /// back) so entries can be copied into the notes file and edited.
    static func exportBuiltIn() throws -> URL {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let url = folderURL.appendingPathComponent(builtInExportName)
        try RegionQualityOverrides.encode(notes: RegionQualityNotes.seed).write(to: url, options: .atomic)
        return url
    }
}
