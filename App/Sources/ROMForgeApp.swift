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
    }
}
