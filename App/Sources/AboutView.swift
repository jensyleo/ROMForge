// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import SwiftUI

/// Custom "About ROMForge…" window, replacing macOS's own auto-generated
/// About panel (`CommandGroup(replacing: .appInfo)` in `ROMForgeApp`) —
/// jensyleo's own request (2026-08-12): "la app debe tener un about y un
/// help donde explique cosas como esas [el arrastre con ⌘]... colócalos con
/// lo básico de la app". The default panel only ever shows name/version/
/// copyright pulled from `Info.plist`; this adds a real "what is this app"
/// explanation alongside that same information.
///
/// jensyleo's own follow-up correction (2026-08-12): the first version's
/// description only ever mentioned MAME — accurate about where actual
/// scanning support is *today* (MAME is this project's current development
/// priority, ahead of other systems), but wrong as a description of the
/// *app itself*, which — see the README's own opening line — targets
/// "arcade, consoles and other systems alike" and is deliberately not
/// MAME-specific in its own architecture (a DAT is a DAT regardless of
/// which system it describes). Rewritten to lead with that broader identity
/// and mention MAME only as where support is most complete right now, not
/// as the app's whole scope.
struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)
            Text("ROMForge")
                .font(.title2.bold())
            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("A native ROM collection manager for macOS, in the spirit of RomCenter and ClrMamePro — audits a ROM collection against a DAT and reports what's correct, incorrect, missing, or unrecognized, without ever renaming, moving, or deleting a file itself. Built for arcade and console systems alike, not tied to any one of them — MAME (`-listxml` DATs, BIOS sets, parent/clone families, CHDs) is where support is most complete today, with Logiqx/No-Intro/Redump-style DATs for other systems supported at the file-format level already. It is not, and will never become, an emulator frontend — no launching, no controller UI, no \"play\" button.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Text("Copyright © 2026 Jensy Leonardo Martínez Cruz. Free software under the GNU General Public License v3.0 or later.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .padding(32)
        .frame(width: 460)
    }
}
