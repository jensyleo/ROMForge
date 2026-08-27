// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import SwiftUI

/// Presents `AppSettingsView` as a document-modal sheet on the main window —
/// jensyleo's own request (2026-08-27): "no me debería permitir regresar a
/// la app dando click fuera del área de la ventana de configuración." A
/// real departure from macOS's own convention (every system Preferences
/// window, and this app's own Settings window before this change, stays
/// non-modal), so this is deliberate, not an oversight.
///
/// The first version of this (same day) used `NSApp.runModal(for:)`
/// instead — genuinely app-modal, but it broke something jensyleo caught
/// immediately: every toggle in this same window stopped visibly doing
/// anything. `runModal(for:)` runs its own restricted run-loop mode
/// (`NSModalPanelRunLoopMode`), and the MAIN window — a separate `NSWindow`,
/// not part of that mode — stops receiving the display/update passes
/// SwiftUI schedules through the ordinary run loop while it's active, so a
/// toggle's `@AppStorage` write landed in `UserDefaults` correctly but the
/// Detail panel behind it never got the chance to redraw and show it. A
/// sheet (`NSWindow.beginSheet(_:completionHandler:)`) gets the same
/// "can't click the parent window while this is up" behavior — sheets are
/// document-modal to their own parent by definition — through the window
/// server's normal sheet-attachment mechanism instead of hijacking the
/// whole app's run loop, so the parent keeps receiving ordinary run-loop
/// service the entire time.
@MainActor
final class AppSettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = AppSettingsWindowController()

    private var window: NSWindow?

    private override init() {}

    /// Shows the window (creating it once, reusing it after) as a sheet on
    /// whatever window is currently key (ROMForge's own main window, in
    /// every real case this is ever called from — the "Settings…" menu
    /// command). Safe to call again while already showing: just re-focuses
    /// the existing sheet instead of attempting a second one.
    func show(store: SystemLibraryStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hostingController = NSHostingController(
            rootView: AppSettingsView(store: store, onDone: { [weak self] in self?.close() })
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        // `.resizable` (jensyleo's own report, 2026-08-27: content was
        // showing up clipped) alongside the explicit size set below —
        // `NSWindow(contentViewController:)` doesn't reliably pick up
        // `AppSettingsView`'s own `.frame(minWidth: 760, minHeight: 560)`
        // at creation time (a timing race against SwiftUI's own layout
        // pass), so this sets the same size directly rather than trusting
        // that to happen automatically.
        window.styleMask = [.titled, .closable, .resizable]
        let contentSize = NSSize(width: 760, height: 560)
        window.setContentSize(contentSize)
        window.contentMinSize = contentSize
        // Kept alive across closes (below) rather than deallocated, so
        // `show(store:)` can just re-show the same instance next time
        // instead of rebuilding `AppSettingsView`'s whole tab state from
        // scratch on every open.
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        guard let parent = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else {
            // No window to attach a sheet to (e.g. every window closed) —
            // an ordinary window is still strictly better than silently
            // doing nothing.
            window.center()
            window.makeKeyAndOrderFront(nil)
            return
        }
        parent.beginSheet(window)
    }

    private func close() {
        guard let window else { return }
        if let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        } else {
            window.close()
        }
    }

    /// Whatever closes the window — "Done", Escape, or the red button —
    /// ends up here. `endSheet`/`close` above already detaches it from its
    /// parent; this just drops the reference so the next `show(store:)`
    /// builds a fresh one rather than trying to reuse a closed window.
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
