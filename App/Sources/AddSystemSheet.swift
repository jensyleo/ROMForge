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
    case n64 = "N64"
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
    case mame = "MAME"
    case other = "Otros"
    var id: String { rawValue }

    /// How a platform's games are stored — decides what the app can
    /// promise: cartridge games are small single files (the case ROMForge
    /// already handles well), disc games can be several files per game
    /// (.cue + .bin) and are not verified end to end yet, and "catalog
    /// only" platforms (huge images, no usable macOS emulator) can be
    /// audited against a DAT but never launched.
    enum Media { case cartridge, disc, catalogOnly, arcade, unknown }

    var media: Media {
        switch self {
        case .nes, .snes, .n64, .segaSG1000, .segaMasterSystem, .segaGameGear, .segaGenesis, .sega32X: return .cartridge
        case .segaCD, .segaSaturn, .segaDreamcast, .sonyPS1, .sonyPS2, .sonyPSP, .xbox: return .disc
        case .sonyPS3, .sonyPS4, .xbox360, .xboxOne: return .catalogOnly
        case .mame: return .arcade
        case .other: return .unknown
        }
    }

    /// Picker section title.
    var group: String {
        switch self {
        case .nes, .snes, .n64: return "Nintendo"
        case .segaSG1000, .segaMasterSystem, .segaGameGear, .segaGenesis, .sega32X, .segaCD, .segaSaturn, .segaDreamcast: return "SEGA"
        case .sonyPS1, .sonyPS2, .sonyPSP, .sonyPS3, .sonyPS4: return "Sony"
        case .xbox, .xbox360, .xboxOne: return "Microsoft"
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
        switch media {
        case .cartridge: return "Cartridge platform — use a No-Intro DAT."
        case .disc: return "Disc platform — use a Redump DAT. Games made of several files (.cue + .bin) and large images are not verified end to end yet; scanning can be slow on a network volume."
        case .catalogOnly: return "Catalog only — you can audit and organize against a Redump DAT, but there is no emulator to play these on macOS and the images are very large (scans can take a long time)."
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
                ForEach(["Nintendo", "SEGA", "Sony", "Microsoft", "Arcade", "Other"], id: \.self) { group in
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
                isMAMEStyle: category == .mame
            )
        )
        dismiss()
    }
}
