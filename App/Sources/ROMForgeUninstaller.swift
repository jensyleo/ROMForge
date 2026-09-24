// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit

/// "Uninstall ROMForge…" (Help menu) — jensyleo's own request (2026-09-23):
/// a real, in-app menu command, not just the standalone `Scripts/uninstall.sh`
/// already in the repo (which only ever helps if the user happens to have a
/// checkout of the source and remembers to run it by hand). This does the
/// exact same steps, natively, reachable the moment the app itself is
/// running — no terminal, no repo checkout needed.
///
/// Deliberately does NOT touch `~/Library/Application Support/ROMForge/`
/// (the real, valuable data — configured systems, scan history, the SQLite
/// database, cached DATs) — same choice `Scripts/uninstall.sh` already
/// makes. This only clears macOS's own bookkeeping ABOUT the app
/// (permissions, window-restoration state, LaunchServices registration)
/// and then moves the app bundle itself to the Trash — never a silent,
/// permanent delete.
enum ROMForgeUninstaller {
    /// Shows a confirmation `NSAlert` (a `CommandGroup` button has no
    /// SwiftUI view of its own to host a `.confirmationDialog` on, unlike
    /// every other destructive action in this app) and only proceeds if
    /// the user explicitly agrees.
    static func confirmAndRun() {
        let alert = NSAlert()
        alert.messageText = "Uninstall ROMForge?"
        alert.informativeText = """
        This resets ROMForge's own macOS permission grants, removes its preferences/caches/saved window state, and moves ROMForge.app itself to the Trash.

        Your configured systems, scan history, and cached DATs (in Application Support) are kept — this only removes the app and its own housekeeping data, not your real collection data.

        ROMForge will quit right after.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        run()
    }

    private static func run() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.jensyleo.romforge"
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        runTool("/usr/bin/tccutil", ["reset", "All", bundleID])

        for relativePath in [
            "Library/Preferences/\(bundleID).plist",
            "Library/Caches/\(bundleID)",
            "Library/Saved Application State/\(bundleID).savedState",
            "Library/HTTPStorages/\(bundleID)",
        ] {
            try? fileManager.removeItem(at: home.appendingPathComponent(relativePath))
        }
        runTool("/usr/bin/defaults", ["delete", bundleID])

        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
        let appURL = Bundle.main.bundleURL
        runTool(lsregister, ["-u", appURL.path])

        // Moves the running app itself to the Trash (recoverable — never a
        // permanent delete), then quits once that's actually done. Falls
        // back to quitting anyway if the move itself somehow fails, rather
        // than leaving the app sitting there half-uninstalled with no way
        // forward.
        NSWorkspace.shared.recycle([appURL]) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    private static func runTool(_ path: String, _ arguments: [String]) {
        guard FileManager.default.isExecutableFile(atPath: path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }
}
