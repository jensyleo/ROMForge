// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import SwiftUI

/// Presents `AppSettingsView` as a genuine app-modal window — jensyleo's own
/// request (2026-08-27): "no me debería permitir regresar a la app dando
/// click fuera del área de la ventana de configuración." A real departure
/// from macOS's own convention (every system Preferences window, and this
/// app's own Settings window before this change, stays non-modal — clicking
/// another window just switches focus to it), so this is deliberate, not an
/// oversight: SwiftUI's `Settings { }` scene has no supported way to do
/// this at all, which is why this hosts the exact same `AppSettingsView`
/// content in a plain `NSWindow` instead, driven with
/// `NSApp.runModal(for:)` — while that call is running, no other window in
/// the app can receive mouse/keyboard events, which is what "can't click
/// away" actually requires.
///
/// A singleton (not a `@State` in `ROMForgeApp`) because `NSApp.runModal
/// (for:)` blocks synchronously until the window closes — it has to be
/// called from an ordinary imperative context (a menu command's action
/// closure), not from inside a `View`'s `body`.
@MainActor
final class AppSettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = AppSettingsWindowController()

    private var window: NSWindow?

    private override init() {}

    /// Shows the window (creating it once, reusing it after) and blocks —
    /// via `NSApp.runModal(for:)` — until it closes. Safe to call again
    /// while already showing: just re-focuses the existing window instead
    /// of starting a second, redundant modal session.
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
        // `.resizable` added (jensyleo's own report, 2026-08-27: content
        // was showing up clipped) alongside the explicit size set below —
        // `NSWindow(contentViewController:)` doesn't reliably pick up
        // `AppSettingsView`'s own `.frame(minWidth: 760, minHeight: 560)`
        // at creation time (a timing race against SwiftUI's own layout
        // pass), so this sets the same size directly rather than trusting
        // that to happen automatically. No green zoom/yellow minimize —
        // neither makes sense for a modal window nothing else can interact
        // with while it's miniaturized or full-screened.
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
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
    }

    private func close() {
        window?.close()
    }

    /// Whatever closes the window — "Done", Escape, or the red button —
    /// ends up here, which is the one place that actually releases the
    /// modal session. Without this, `NSApp.stopModal()` never runs and
    /// every other window in the app stays unresponsive even after this
    /// one is gone.
    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal()
        window = nil
    }
}
