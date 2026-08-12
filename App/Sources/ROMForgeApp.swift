// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.

import SwiftUI

/// Posted by the "View" menu's reset commands below — `LibraryDetailView`
/// owns the actual column-customization state (`@State`, scoped per view),
/// so a plain `NotificationCenter` broadcast is simpler than threading a
/// callback down through `ContentView` for something this infrequent.
extension Notification.Name {
    static let romForgeResetColumnSizes = Notification.Name("ROMForge.resetColumnSizes")
}

@main
struct ROMForgeApp: App {
    // Owned here (not inside `ContentView`) so the Settings scene below —
    // a separate `Scene`, not a child of `ContentView` — can read/write the
    // same configured systems rather than a second, disconnected store.
    @State private var store = SystemLibraryStore()

    var body: some Scene {
        // SwiftUI already restores this window's size/position across
        // launches on its own, keyed off the *exact static type* of
        // `WindowGroup`'s content (verified directly: it round-trips a
        // resize through quit/relaunch with no extra code at all). That
        // key is brittle — attaching a modifier directly here (an earlier
        // `.onAppear`, added to try an AppKit-level `setFrameAutosaveName`
        // workaround that never actually panned out) changes the content's
        // static type to `ModifiedContent<ContentView, ...>`, silently
        // orphaning whatever frame was saved under the old, unmodified
        // `ContentView` key — which is exactly what broke this. Keeping
        // `ContentView(store: store)` bare here, with zero modifiers, is
        // what keeps that key (and the restore) stable long-term; put any
        // future one-time startup logic inside `ContentView`'s own body
        // instead, where it doesn't affect this type at all.
        WindowGroup {
            ContentView(store: store)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Reset Column Sizes") {
                    NotificationCenter.default.post(name: .romForgeResetColumnSizes, object: nil)
                }
            }
            // jensyleo's own request (2026-08-12): a custom "About" (macOS's
            // own auto-generated panel only ever shows name/version/
            // copyright from Info.plist, with no room for "what is this
            // app") and a "Help" window explaining the basics — prompted by
            // realizing the new ⌘-drag-to-reorder gesture on "ROM folder"
            // had nowhere documented for a user to discover it at all.
            CommandGroup(replacing: .appInfo) {
                AboutMenuButton()
            }
            CommandGroup(replacing: .help) {
                HelpMenuButton()
            }
        }
        // A real "Settings…" window (⌘,), the conventional macOS place for
        // configuration that isn't part of the main content flow —
        // replaces the earlier "Edit Merge Settings…" context-menu item,
        // which buried this in a place a user had no reason to check first.
        // Two tabs: per-system merge mode, and app-wide preferences (which
        // hash algorithms to compute) — see `AppSettingsView`.
        Settings {
            AppSettingsView(store: store)
        }
        // `Window` (not `WindowGroup`): each is a single, unique window —
        // opening "About"/"Help" again while one's already showing should
        // just bring the existing one forward, not spawn a second copy.
        Window("About ROMForge", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        Window("ROMForge Help", id: "help") {
            HelpView()
        }
    }
}

/// A small, standalone `View` (not a bare `Button` inline in `.commands`)
/// purely so it can read `@Environment(\.openWindow)` — `CommandGroup`'s
/// content is itself `@ViewBuilder`, so any real `View` works here, but the
/// environment value isn't available directly inside `ROMForgeApp`'s own
/// `body` the way it is once inside a child view's own body.
private struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("About ROMForge") { openWindow(id: "about") }
    }
}

private struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("ROMForge Help") { openWindow(id: "help") }
    }
}
