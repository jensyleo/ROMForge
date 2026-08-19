// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import SwiftUI

/// One toolbar button, declared by SwiftUI (`ContentView`/`LibraryDetailView`)
/// and kept in sync with a real, hand-built `NSToolbar` by
/// `ROMForgeToolbarController` — see that type's own doc comment for why
/// SwiftUI's own `.toolbar(id:)` API isn't used for this.
struct ToolbarAction: Identifiable {
    let id: String
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    var help: String = ""
    /// `false` for an icon-only button (needs `systemImage`) — jensyleo's
    /// own request (2026-08-19): "Toggle Sidebar" reads better as just its
    /// icon, same as most macOS sidebar-toggle buttons. `title`/`help`
    /// still apply everywhere else (tooltip, customization palette).
    var showsLabel: Bool = true
    let action: () -> Void
}

/// Owns the window's real `NSToolbar` and keeps it in sync with the
/// declarative `[ToolbarAction]` lists SwiftUI recomputes on every render —
/// built specifically because SwiftUI's own `.toolbar(id:)` +
/// `ToolbarItem(id:)` never actually gets AppKit to set
/// `NSToolbar.allowsUserCustomization` when declared on a nested detail
/// view rather than the window's own root content (confirmed live,
/// 2026-08-18 — a debug `print` inside a "Customize Toolbar…" menu action
/// never even fired).
///
/// A first attempt (2026-08-19) assigned `window.toolbar` directly while
/// `ContentView` still used SwiftUI's `NavigationSplitView` — that broke
/// the app outright the moment it ran: `NavigationSplitView` manages its
/// *own* `NSToolbar` internally (it needs a slot in it for the sidebar
/// toggle button), and fighting it over `window.toolbar` ownership made
/// the entire sidebar and most toolbar buttons vanish. `ContentView` no
/// longer uses `NavigationSplitView` (see its own doc comment) —
/// `window.toolbar` is genuinely unclaimed by SwiftUI now, which is what
/// makes this safe.
///
/// Two independent "regions" contribute items — `ContentView`'s own
/// sidebar-toggle/"Add System" (sidebar-scoped, always present) and
/// `LibraryDetailView`'s scan/export/play group (detail-scoped, only
/// present while a system is selected) — each calls `setRegion` with its
/// own current list without needing to know about the other's.
@MainActor
final class ROMForgeToolbarController: NSObject, NSToolbarDelegate {
    // `.v2` — a fresh identifier, deliberately never reused from the
    // earlier, briefly-broken attempt (2026-08-19, see this type's own
    // doc comment) at this exact same string. `autosavesConfiguration`
    // persists whatever item set a toolbar had under a key derived from
    // its identifier; reusing the old string risked silently restoring
    // that broken (near-empty) saved configuration instead of the real
    // one this controller declares.
    static let toolbarIdentifier = "ROMForge.mainToolbar.v2"
    /// Fixed so items don't jump around as regions update independently/
    /// out of order — sidebar items always precede the per-system actions,
    /// matching this app's existing layout, though a user's own manual
    /// reorder (once customization is real) is respected afterward since
    /// this only decides where a *newly appearing* item gets inserted.
    private static let regionOrder = ["sidebar", "detail"]

    private var actionsByID: [String: ToolbarAction] = [:]
    private var itemsByRegion: [String: [ToolbarAction]] = [:]
    private weak var toolbar: NSToolbar?

    func install(on window: NSWindow) {
        if let existing = window.toolbar, existing.identifier == Self.toolbarIdentifier {
            toolbar = existing
            return
        }
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        // jensyleo's own report (2026-08-19): `.iconAndLabel` left every
        // item without a `systemImage` (all but "Play") showing no visible
        // text at all — AppKit's icon+label layout doesn't fall back to a
        // plain text button when there's no icon to anchor the label
        // under. Only "Play" carries an icon in this app's action set
        // today, so `.labelOnly` is what actually renders every button's
        // name reliably; "Play" trades its ▶ icon for the plain word
        // "Play" as a result, a small visual difference from before.
        toolbar.displayMode = .labelOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        self.toolbar = toolbar
    }

    /// Declares (or replaces) one named region's current action list.
    /// Existing items already on the real toolbar only ever have their
    /// dynamic state (enabled/help/title) refreshed in place — item
    /// identity, order, and visibility are AppKit's/the user's own to
    /// manage once installed, exactly what "real customization" means.
    /// Items that appear/disappear between calls (e.g. the whole "detail"
    /// region clearing when no system is selected) are inserted/removed
    /// explicitly, since `NSToolbar` never re-queries
    /// `toolbarDefaultItemIdentifiers` on its own after first creation.
    func setRegion(_ region: String, actions newActions: [ToolbarAction]) {
        let previousIDs = Set(itemsByRegion[region]?.map(\.id) ?? [])
        let newIDs = newActions.map(\.id)
        itemsByRegion[region] = newActions
        for action in newActions { actionsByID[action.id] = action }

        guard let toolbar else { return }
        reconcile(region: region, previousIDs: previousIDs, newIDs: Set(newIDs), toolbar: toolbar)
        for item in toolbar.items {
            guard let spec = actionsByID[item.itemIdentifier.rawValue] else { continue }
            item.toolTip = spec.help
            item.label = spec.title
            if let button = item.view as? NSButton {
                button.title = spec.showsLabel ? spec.title : ""
                button.isEnabled = spec.isEnabled
                button.toolTip = spec.help
            }
        }
    }

    private func reconcile(region: String, previousIDs: Set<String>, newIDs: Set<String>, toolbar: NSToolbar) {
        guard previousIDs != newIDs else { return }
        for id in previousIDs.subtracting(newIDs) {
            if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier.rawValue == id }) {
                toolbar.removeItem(at: index)
            }
        }
        for id in newIDs.subtracting(previousIDs) {
            guard !toolbar.items.contains(where: { $0.itemIdentifier.rawValue == id }) else { continue }
            toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier(rawValue: id), at: insertionIndex(forRegion: region, toolbar: toolbar))
        }
    }

    /// Where a newly-appearing item in `region` belongs: right before the
    /// first existing item that belongs to a later region, or at the end
    /// if none exists yet — keeps `regionOrder` roughly respected on first
    /// appearance without moving anything already there.
    private func insertionIndex(forRegion region: String, toolbar: NSToolbar) -> Int {
        guard let regionPosition = Self.regionOrder.firstIndex(of: region) else { return toolbar.items.count }
        for laterRegion in Self.regionOrder[(regionPosition + 1)...] {
            let laterIDs = Set(itemsByRegion[laterRegion]?.map(\.id) ?? [])
            if let index = toolbar.items.firstIndex(where: { laterIDs.contains($0.itemIdentifier.rawValue) }) {
                return index
            }
        }
        return toolbar.items.count
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.regionOrder.flatMap { itemsByRegion[$0]?.map(\.id) ?? [] }.map { NSToolbarItem.Identifier(rawValue: $0) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.flexibleSpace]
    }

    // jensyleo's own report (2026-08-19): plain `NSToolbarItem.label` under
    // `.iconAndLabel` (and later `.labelOnly`) never actually rendered any
    // visible text for the 8 of 9 actions with no `systemImage` — AppKit's
    // own implicit image+label layout apparently doesn't fall back to a
    // readable plain-text button on this SDK/macOS combination, at least
    // not for a custom (non-system) toolbar item. Rather than keep
    // guessing at `NSToolbarItem`'s own undocumented rendering heuristics,
    // each item gets its OWN `NSButton` as its `view` — full control over
    // what's actually drawn, guaranteed visible text regardless of
    // whether an icon is present.
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let spec = actionsByID[itemIdentifier.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = spec.title
        item.paletteLabel = spec.title
        item.toolTip = spec.help

        let button = NSButton(title: spec.showsLabel ? spec.title : "", target: self, action: #selector(performAction(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(itemIdentifier.rawValue)
        button.bezelStyle = .texturedRounded
        button.isEnabled = spec.isEnabled
        button.toolTip = spec.help
        if let systemImage = spec.systemImage {
            button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: spec.title)
            button.imagePosition = spec.showsLabel ? .imageLeading : .imageOnly
        }
        item.view = button
        return item
    }

    @objc private func performAction(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        actionsByID[id]?.action()
    }
}

/// Installs/updates `ROMForgeToolbarController`'s real `NSToolbar` on this
/// view's own window — an invisible, zero-size bridge, since SwiftUI has
/// no API to reach the containing `NSWindow` directly from a nested
/// view's body. Meant to be attached via `.background(...)` so it doesn't
/// affect layout.
struct ToolbarHost: NSViewRepresentable {
    let region: String
    let actions: [ToolbarAction]
    let controller: ROMForgeToolbarController

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // `nsView.window` is nil until AppKit has actually attached this
        // view into a window's view hierarchy, which hasn't necessarily
        // happened yet on the very first `updateNSView` call — deferred to
        // the next run-loop turn so it reads the real window once it's
        // there, same pattern already used elsewhere in this app for
        // AppKit interop that depends on view/window attachment timing.
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            controller.install(on: window)
            controller.setRegion(region, actions: actions)
        }
    }
}
