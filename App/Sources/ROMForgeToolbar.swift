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
    /// Whether this button is allowed to show its text label when the
    /// toolbar's real `displayMode` (set from "Customize Toolbar…", or
    /// restored from a prior launch — see `ROMForgeToolbarController`'s
    /// `displayModeDefaultsKey`) calls for one (`.iconAndLabel`/
    /// `.labelOnly`). `false` forces icon-only regardless of that mode —
    /// reserved for "Toggle Sidebar", which keeps the plain-icon look most
    /// macOS sidebar toggles use even when the user has switched every
    /// other button to show text. `title`/`help` still apply everywhere
    /// else (tooltip, customization palette) regardless of this flag.
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
    // Confirmed live (2026-08-25) as the real cause of a startup
    // `SIGABRT`: `WindowGroup` lets macOS open more than one `ContentView`
    // window (⌘N, or window-state restoration recreating more than one
    // from a prior quit) — each gets its own `ROMForgeToolbarController`
    // and thus its own real `NSToolbar`, but a *shared static* identifier
    // string here meant every one of those `NSToolbar` instances counted
    // as the same AppKit "family". Any family member inserting an item
    // makes AppKit walk every other member (`_enumerateToolbarsInFamily`/
    // `_notifyFamily_InsertedNewItem`, both in the crash's own stack) and
    // clone that same item onto it directly — bypassing this controller's
    // own `NSToolbarDelegate` and its `reconcile(...)` duplicate guard
    // entirely, since the sync path never asks the delegate anything. The
    // second window's toolbar reaches this same identifier on its own,
    // independently, moments later in the exact same startup sequence,
    // and AppKit's family-sync tries to insert it there too — this time
    // hitting an item that's already present, which is the fatal
    // `NSAssertionHandler` failure in the crash report. A unique-per-
    // instance identifier (below) makes each window's toolbar its own
    // family of one, so this sync path never fires across windows at
    // all — which is correct anyway, since nothing here ever wanted two
    // windows' toolbars mirroring each other's item set.
    let toolbarIdentifier = "ROMForge.mainToolbar.v2.\(UUID().uuidString)"
    /// Fixed so items don't jump around as regions update independently/
    /// out of order — sidebar items always precede the per-system actions,
    /// matching this app's existing layout, though a user's own manual
    /// reorder (once customization is real) is respected afterward since
    /// this only decides where a *newly appearing* item gets inserted.
    private static let regionOrder = ["sidebar", "detail"]

    private var actionsByID: [String: ToolbarAction] = [:]
    private var itemsByRegion: [String: [ToolbarAction]] = [:]
    private weak var toolbar: NSToolbar?
    /// Confirmed live (2026-08-25): right-click on the toolbar → "Icon and
    /// Text"/"Icon Only"/"Text Only" mutates `toolbar.displayMode`
    /// directly, with no sheet involved at all — `NSWindow
    /// .didEndSheetNotification` (added for the "Customize Toolbar…"
    /// palette's own segmented control) never fires for it, so neither the
    /// buttons' own rendering nor the saved preference ever updated for
    /// this path; reproduced by clicking it and reading back both the
    /// screen and `UserDefaults` unchanged. AppKit exposes no dedicated
    /// notification for a `displayMode` change either, but the property
    /// itself is KVO-compliant, which is the one hook that covers every
    /// path (this quick menu, the palette's control, and any other way
    /// AppKit might flip it) uniformly instead of chasing each one by hand.
    private var displayModeObservation: NSKeyValueObservation?
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

    /// jensyleo's own report (2026-08-25): switching to "Icon and Text" in
    /// "Customize Toolbar…" never actually showed any text, and didn't
    /// survive relaunch even where it visually appeared to take. Root
    /// cause was two-fold — `toolbar(_:itemForItemIdentifier:...)` and
    /// `setRegion` both decided a button's text purely from `spec.showsLabel`
    /// (a fixed per-action flag, see its own doc comment) and never
    /// consulted `toolbar.displayMode` at all, so the customization
    /// panel's segmented control changed AppKit's own bookkeeping but
    /// nothing this controller actually draws; and `autosavesConfiguration`
    /// is off (see `itemOrderDefaultsKey` above), which also throws away
    /// `NSToolbar`'s free native persistence of `displayMode` alongside
    /// item order. This key restores just that one piece manually, the
    /// same way `itemOrderDefaultsKey` already does for order.
    private static let displayModeDefaultsKey = "ROMForge.mainToolbar.v2.displayMode"

    private func loadSavedOrder() -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.itemOrderDefaultsKey) ?? []
    }

    @objc private func persistCurrentOrder() {
        guard let toolbar else { return }
        UserDefaults.standard.set(toolbar.items.map(\.itemIdentifier.rawValue), forKey: Self.itemOrderDefaultsKey)
    }

    private func loadSavedDisplayMode() -> NSToolbar.DisplayMode? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.displayModeDefaultsKey) != nil else { return nil }
        return NSToolbar.DisplayMode(rawValue: UInt(defaults.integer(forKey: Self.displayModeDefaultsKey)))
    }

    @objc private func persistDisplayModeAndRefresh() {
        guard let toolbar else { return }
        UserDefaults.standard.set(Int(toolbar.displayMode.rawValue), forKey: Self.displayModeDefaultsKey)
        // No per-item re-render needed here (contrast the old custom-
        // NSButton version's `refreshAllButtonLabels`): a plain
        // `NSToolbarItem` already redraws itself for the new `displayMode`
        // on its own — see `toolbar(_:itemForItemIdentifier:...)`'s own
        // doc comment for why this controller switched to plain items.
    }

    func install(on window: NSWindow) {
        if let existing = window.toolbar, existing.identifier == toolbarIdentifier {
            toolbar = existing
            return
        }
        let toolbar = NSToolbar(identifier: toolbarIdentifier)
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        // See `itemOrderDefaultsKey`'s own doc comment just above — native
        // autosave doesn't actually round-trip this toolbar's custom-view
        // items across a relaunch, so it stays off rather than left
        // silently doing nothing (or worse, racing this controller's own
        // manual restore).
        toolbar.autosavesConfiguration = false
        // jensyleo's own stated preference: icon-only by default, text
        // only once explicitly switched to "Icon and Text"/"Text Only"
        // from the toolbar's own menu. A saved `displayMode` (from that
        // prior choice — see `displayModeDefaultsKey`'s own doc comment)
        // overrides this default; applied here, before any item exists,
        // so the very first items `toolbar(_:itemForItemIdentifier:...)`
        // builds already render in the right mode instead of flashing
        // `.iconOnly` first.
        let savedDisplayMode = loadSavedDisplayMode() ?? .iconOnly
        toolbar.displayMode = savedDisplayMode
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        // `NSWindow.toolbar`'s setter silently resets `displayMode` back to
        // `.default` (which AppKit then renders as icon-only) as part of
        // attaching a brand-new toolbar — confirmed live (2026-08-25): the
        // assignment above reads back correctly immediately after, but a
        // relaunch showed icon-only again despite the right value already
        // sitting in `UserDefaults`. Reasserting it once more here, after
        // attachment, is what actually survives.
        toolbar.displayMode = savedDisplayMode
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
        // jensyleo's own report (2026-08-25), confirmed live: a reorder
        // dragged inside the "Customize Toolbar…" sheet (`NSToolbar`'s own
        // built-in palette, opened via right-click → "Customize Toolbar…"
        // or `runCustomizationPalette(for:)`) visibly reorders the real
        // toolbar the moment you drop an item, but neither
        // `didRemoveItemNotification` nor `willAddItemNotification` fires
        // for it — those two only cover a plain ⌘-drag directly on the
        // live toolbar (AppKit implements *that* as a remove+re-insert
        // pair), not a drag inside the palette sheet, which apparently
        // mutates `toolbar.items` some other way internally. Confirmed by
        // reproducing the exact failure end-to-end: reorder via the
        // palette, quit, relaunch — `itemOrderDefaultsKey` still held the
        // pre-reorder order because `persistCurrentOrder()` was simply
        // never called. The palette always runs as a sheet on this
        // toolbar's own window, so `NSWindow.didEndSheetNotification`
        // catches exactly the moment it closes (Done/Escape/clicking
        // outside), regardless of what AppKit did internally to get there.
        NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: nil) { [weak self] _ in
            DispatchQueue.main.async { self?.persistCurrentOrder() }
        }
        // See `displayModeObservation`'s own doc comment: the right-click
        // quick menu changes `toolbar.displayMode` with no sheet and no
        // dedicated AppKit notification at all, so KVO on the property
        // itself is the only hook that reliably covers that path (and the
        // palette's own control, which also goes through this same
        // property either way — no separate handling needed for it here
        // anymore).
        displayModeObservation = toolbar.observe(\.displayMode, options: [.new]) { [weak self] _, _ in
            self?.persistDisplayModeAndRefresh()
        }
        // Safety net, not the fix for the bug above: covers quitting while
        // some other, still-unknown reorder path also skipped the two
        // notifications above without a sheet ever closing.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.persistCurrentOrder()
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
            item.isEnabled = spec.isEnabled
            // `showsLabel == false` (only "Toggle Sidebar" today) forces
            // icon-only regardless of `displayMode` — a plain
            // `NSToolbarItem` with an empty `label` simply doesn't reserve
            // a text row under any display mode, so this alone is enough;
            // no per-`displayMode` branching needed the way the old
            // custom-button version required.
            item.label = spec.showsLabel ? spec.title : ""
            if let systemImage = spec.systemImage {
                item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: spec.title)
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
        for id in newIDs where !previousIDs.contains(id) {
            guard !toolbar.items.contains(where: { $0.itemIdentifier.rawValue == id }) else { continue }
            toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier(rawValue: id), at: insertionIndex(forRegion: region, id: id, toolbar: toolbar))
        }
        // jensyleo's own report (2026-08-25), confirmed live: a real
        // reorder made via the "Customize Toolbar…" sheet never survived
        // even a single quit/relaunch, despite `persistCurrentOrder()`
        // genuinely running (confirmed with `defaults read` right after
        // clicking "Done") and genuinely writing the correct 11-item
        // order. Root cause traced to THIS call, previously here
        // (`if insertedAny { persistCurrentOrder() }`) — `setRegion` is
        // called separately per region ("sidebar" with 2 items, then
        // "detail" with 9, at every single launch), so this fired right
        // after the *first* of those two calls populated only 2 of the
        // eventual 11 items, and `persistCurrentOrder()` unconditionally
        // saves `toolbar.items` *in full* — silently overwriting the
        // user's real, complete saved order with a 2-item snapshot before
        // "detail" had even loaded. Every later `setRegion` call then
        // built its placement off that already-truncated saved order,
        // and any structural change (any system's toolbar merely
        // finishing its startup population, not an actual user reorder)
        // kept re-deriving and re-saving a "mostly declaration order"
        // result, permanently burying whatever the user last actually
        // dragged. Removed entirely — persisting on every incremental
        // population was never necessary in the first place: applying a
        // saved order (`insertionIndex` below) only ever *reads*
        // `loadSavedOrder()`, and the real triggers that should persist
        // (an actual user-driven reorder) are covered on `install(on:)`
        // by the `didRemoveItem`/`willAddItem`/sheet-close/app-terminate
        // observers, none of which is this method.
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

    // jensyleo's own report (2026-08-19): plain `NSToolbarItem.label` never
    // rendered visible text back when most actions here had no
    // `systemImage` yet — worked around at the time with a hand-built
    // `NSButton` `view`, which then needed its own icon-position/duplicate-
    // label bugs chased across several follow-up sessions (2026-08-25).
    // Every action now carries a `systemImage`, so that whole workaround
    // is unnecessary: a plain `NSToolbarItem` (`image` + `label` +
    // `target`/`action`) renders correctly on its own, governed by
    // `toolbar.displayMode` exactly like any other native toolbar item —
    // matching how this app's own other toolbar (TCPV4MAC's) already does
    // this, which is what jensyleo pointed at as the reference to copy.
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let spec = actionsByID[itemIdentifier.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = spec.showsLabel ? spec.title : ""
        item.paletteLabel = spec.title
        item.toolTip = spec.help
        item.isEnabled = spec.isEnabled
        item.target = self
        item.action = #selector(performAction(_:))
        if let systemImage = spec.systemImage {
            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: spec.title)
        }
        return item
    }

    @objc private func performAction(_ sender: NSToolbarItem) {
        actionsByID[sender.itemIdentifier.rawValue]?.action()
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
