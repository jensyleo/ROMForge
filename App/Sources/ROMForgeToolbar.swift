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
    /// The dynamic bits of `ToolbarAction` that actually get pushed to
    /// AppKit on a refresh (everything except `action` itself, which
    /// isn't `Equatable`) — jensyleo's own report (2026-08-19): this
    /// controller was writing `toolTip`/`label`/`button.title`/`isEnabled`
    /// on *every* item, on *every* `setRegion` call, even when a render
    /// recomputed the exact same 9 actions unchanged (which is the common
    /// case — most SwiftUI re-renders of `LibraryDetailView` don't
    /// actually change any button's state). Comparing against this cached
    /// signature first skips that AppKit write/relayout entirely on a
    /// no-op update.
    private struct ActionSignature: Equatable {
        let title: String
        let isEnabled: Bool
        let help: String
        let showsLabel: Bool
        init(_ action: ToolbarAction) {
            title = action.title
            isEnabled = action.isEnabled
            help = action.help
            showsLabel = action.showsLabel
        }
    }
    private var lastAppliedSignatureByID: [String: ActionSignature] = [:]

    /// jensyleo's own report (2026-08-24): a ⌘-drag reorder never survived
    /// quit/relaunch, despite `autosavesConfiguration = true` — the
    /// property that's supposed to make `NSToolbar` persist this on its
    /// own for free. Confirmed live this genuinely isn't the `Set`-
    /// iteration bug documented on `reconcile(region:previousIDs:newIDs:toolbar:)`
    /// below (that fix is still intact, and only ever affected *newly
    /// appearing* items in the first place, not a manual drag of items
    /// already present): the real cause is `NSToolbar`'s own native
    /// autosave, which keys its saved dictionary off each item's
    /// `NSToolbarItem`, silently failing to round-trip items whose `view`
    /// is a hand-built `NSButton` rather than one of its own standard
    /// item kinds — exactly what every item here is (see `toolbar(_:
    /// itemForItemIdentifier:willBeInsertedIntoToolbar:)` below, and its
    /// own doc comment on why a custom view was needed at all). A fresh
    /// launch's brand-new `NSToolbar` never receives any saved order back
    /// from AppKit for these items, so it just falls back to
    /// `toolbarDefaultItemIdentifiers`'s own declared (region) order every
    /// time — indistinguishable from "reset to defaults" even though
    /// nothing was ever actually purged.
    ///
    /// Fixed by not depending on that native mechanism at all:
    /// `autosavesConfiguration` stays off, and this controller keeps its
    /// own plain `[String]` of item identifiers under `itemOrderDefaultsKey`,
    /// updated live off `NSToolbar.didRemoveItemNotification`/
    /// `.willAddItemNotification` (both of which a ⌘-drag reorder fires,
    /// since AppKit implements it internally as a remove immediately
    /// followed by a re-insert) and consulted by `reconcile(...)` to place
    /// a newly (re)appearing item back where the user last put it, rather
    /// than wherever `regionOrder`/declaration order would put it.
    private static let itemOrderDefaultsKey = "ROMForge.mainToolbar.v2.savedOrder"

    private func loadSavedOrder() -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.itemOrderDefaultsKey) ?? []
    }

    @objc private func persistCurrentOrder() {
        guard let toolbar else { return }
        UserDefaults.standard.set(toolbar.items.map(\.itemIdentifier.rawValue), forKey: Self.itemOrderDefaultsKey)
    }

    func install(on window: NSWindow) {
        if let existing = window.toolbar, existing.identifier == Self.toolbarIdentifier {
            toolbar = existing
            return
        }
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        // See `itemOrderDefaultsKey`'s own doc comment just above — native
        // autosave doesn't actually round-trip this toolbar's custom-view
        // items across a relaunch, so it stays off rather than left
        // silently doing nothing (or worse, racing this controller's own
        // manual restore).
        toolbar.autosavesConfiguration = false
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
        // Deferred one runloop turn (`DispatchQueue.main.async`, same
        // reasoning as `ToolbarHost.Coordinator`'s own deferral): both
        // notifications fire mid-mutation (`willAddItem` before the item
        // is actually in `toolbar.items` yet, `didRemoveItem` before a
        // reorder's matching re-insert has happened), so reading
        // `toolbar.items` synchronously inside either handler would
        // capture a transient, incomplete order rather than the real one.
        NotificationCenter.default.addObserver(forName: NSToolbar.didRemoveItemNotification, object: toolbar, queue: nil) { [weak self] _ in
            DispatchQueue.main.async { self?.persistCurrentOrder() }
        }
        NotificationCenter.default.addObserver(forName: NSToolbar.willAddItemNotification, object: toolbar, queue: nil) { [weak self] _ in
            DispatchQueue.main.async { self?.persistCurrentOrder() }
        }
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
        reconcile(region: region, previousIDs: previousIDs, newIDs: newIDs, toolbar: toolbar)
        for item in toolbar.items {
            let id = item.itemIdentifier.rawValue
            guard let spec = actionsByID[id] else { continue }
            let signature = ActionSignature(spec)
            guard lastAppliedSignatureByID[id] != signature else { continue }
            lastAppliedSignatureByID[id] = signature
            item.toolTip = spec.help
            item.label = spec.title
            if let button = item.view as? NSButton {
                button.title = spec.showsLabel ? spec.title : ""
                button.isEnabled = spec.isEnabled
                button.toolTip = spec.help
            }
        }
    }

    // jensyleo's own report (2026-08-19): the button order came out
    // scrambled, differently on every single launch — traced to this
    // method iterating `Set<String>`s (`previousIDs.subtracting(newIDs)`,
    // `newIDs.subtracting(previousIDs)`) to decide *which* ids to
    // remove/insert. A `Set`'s iteration order is unspecified and, for
    // `String` specifically, actively randomized per process launch
    // (Swift's own hash-seed-per-run security measure) — harmless for
    // *which* ids end up present, but this method also used that same
    // unordered iteration to decide the *sequence* of `insertItem` calls,
    // so the final on-screen order came out different, at random, every
    // launch. Fixed by only ever using sets to decide membership
    // (removed/added), while the actual insertion loop below walks
    // `newIDs` — a plain, order-preserving `[String]` — in its real,
    // declared sequence.
    private func reconcile(region: String, previousIDs: Set<String>, newIDs: [String], toolbar: NSToolbar) {
        let newIDSet = Set(newIDs)
        guard previousIDs != newIDSet else { return }
        for id in previousIDs.subtracting(newIDSet) {
            if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier.rawValue == id }) {
                toolbar.removeItem(at: index)
            }
        }
        var insertedAny = false
        for id in newIDs where !previousIDs.contains(id) {
            guard !toolbar.items.contains(where: { $0.itemIdentifier.rawValue == id }) else { continue }
            toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier(rawValue: id), at: insertionIndex(forRegion: region, id: id, toolbar: toolbar))
            insertedAny = true
        }
        // Only a real structural change (not every no-op `setRegion` call)
        // should touch the saved order — matters the very first time a
        // region populates at app launch, since that's exactly when a
        // user's own last-saved order needs applying (see
        // `itemOrderDefaultsKey`'s own doc comment), and it must win over
        // whatever plain `regionOrder` position `insertionIndex` picked as
        // a fallback for ids `loadSavedOrder()` didn't already know about.
        if insertedAny { persistCurrentOrder() }
    }

    /// Where a newly-appearing `id` in `region` belongs. Consults the
    /// user's own last saved order first (see `itemOrderDefaultsKey`'s own
    /// doc comment): if `id` appears there, this places it right before
    /// whichever *later*-in-that-saved-order id is already present on the
    /// toolbar (or at the end if every id after it in the saved order is
    /// itself still absent) — reproducing a past ⌘-drag reorder on a fresh
    /// `NSToolbar` that never got AppKit's own native restore. Falls back
    /// to the plain `regionOrder`-based placement below for an id the
    /// saved order has never seen (a newly added action, or the very
    /// first launch ever).
    private func insertionIndex(forRegion region: String, id: String, toolbar: NSToolbar) -> Int {
        let savedOrder = loadSavedOrder()
        if let savedPosition = savedOrder.firstIndex(of: id) {
            let presentIDs = Set(toolbar.items.map(\.itemIdentifier.rawValue))
            for laterID in savedOrder[(savedPosition + 1)...] where presentIDs.contains(laterID) {
                if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier.rawValue == laterID }) {
                    return index
                }
            }
            return toolbar.items.count
        }
        return insertionIndex(forRegion: region, toolbar: toolbar)
    }

    /// Where a newly-appearing item in `region` belongs when the saved
    /// order (above) doesn't already know about it: right before the
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
        //
        // jensyleo's own report (2026-08-19): a burst of renders (typing
        // in a search field, dragging a table selection) used to queue one
        // of these blocks *per* `updateNSView` call, each repeating
        // `setRegion`'s own work even though only the very last one's
        // `actions` value is still relevant by the time any of them
        // actually run. `Coordinator` below coalesces that into a single
        // pending apply that always uses whichever `actions` was current
        // when it fires.
        context.coordinator.pendingRegion = region
        context.coordinator.pendingActions = actions
        guard !context.coordinator.isScheduled else { return }
        context.coordinator.isScheduled = true
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak nsView] in
            coordinator.isScheduled = false
            guard let nsView, let window = nsView.window,
                  let region = coordinator.pendingRegion, let actions = coordinator.pendingActions
            else { return }
            controller.install(on: window)
            controller.setRegion(region, actions: actions)
        }
    }

    @MainActor
    final class Coordinator {
        var pendingRegion: String?
        var pendingActions: [ToolbarAction]?
        var isScheduled = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}
