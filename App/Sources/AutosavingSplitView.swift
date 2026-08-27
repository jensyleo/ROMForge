// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import SwiftUI

/// One pane of an `AutosavingSplitView` — a view plus the minimum length
/// (width for a `.sideBySide` split, height for `.stacked`) its content
/// needs to stay usable.
struct SplitPane {
    let view: AnyView
    let minLength: CGFloat

    init<V: View>(minLength: CGFloat, @ViewBuilder view: () -> V) {
        self.view = AnyView(view())
        self.minLength = minLength
    }
}

/// A drop-in, persisting replacement for SwiftUI's `HSplitView`/`VSplitView`
/// — neither exposes any API to remember where the user left the divider
/// across launches. Backed directly by `NSSplitView` (the same class
/// SwiftUI's own split views wrap internally), but persistence is entirely
/// hand-rolled rather than using `NSSplitView.autosaveName`.
///
/// `autosaveName` was tried first and found genuinely unreliable in this
/// specific context (an `NSSplitView` hosted via `NSViewRepresentable`
/// inside a SwiftUI view that itself only gets its final frame after one or
/// more layout passes): its restore step ran against whatever transient
/// frame the split view had at that moment — sometimes 0×0, sometimes some
/// other pre-final size — and computed/saved degenerate proportions from
/// it (observed directly, repeatedly, across clean quit/relaunch cycles:
/// two edge panes collapsed to exactly 0 width, the middle pane taking
/// everything). Once saved, that bad ratio keeps reproducing itself
/// forever, since nothing about `autosaveName` re-derives a sane layout
/// from a degenerate one.
///
/// This version saves/restores **fractions of the split's total length**
/// (not absolute pixel positions, which don't survive the window opening
/// at a different size than it was saved at) to a plain `UserDefaults`
/// array, and only ever *applies* a restore once the split view has
/// actually been given a real, non-trivial frame — checked idempotently
/// from `updateNSView`, which SwiftUI calls repeatedly regardless, rather
/// than from a one-shot, timing-guessed callback.
struct AutosavingSplitView: NSViewRepresentable {
    enum Axis {
        /// Panes side by side, divided by a vertical line — matches
        /// SwiftUI's `HSplitView`.
        case sideBySide
        /// Panes stacked top to bottom, divided by a horizontal line —
        /// matches SwiftUI's `VSplitView`.
        case stacked
    }

    let axis: Axis
    let autosaveName: String
    let panes: [SplitPane]
    /// The split used before anything's ever been saved for `autosaveName`
    /// — defaults to an even split across every pane (this view's original,
    /// only behavior). jensyleo's own report (2026-08-19): an even split is
    /// wrong for a sidebar-style pane that only ever needs a fraction of a
    /// window's width (a plain list of configured systems ended up taking
    /// literal half the window on first launch) — pass explicit fractions
    /// for that case instead of leaving every caller stuck with 1/N.
    var defaultFractions: [Double]?

    init(axis: Axis, autosaveName: String, panes: [SplitPane], defaultFractions: [Double]? = nil) {
        self.axis = axis
        self.autosaveName = autosaveName
        self.panes = panes
        self.defaultFractions = defaultFractions
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            axis: axis, minLengths: panes.map(\.minLength), defaultsKey: "ROMForge.splitFractions.\(autosaveName)",
            defaultFractions: defaultFractions
        )
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = ObservingSplitView()
        // NSSplitView's own `isVertical` names the divider's orientation,
        // not the panes' layout direction — `true` means a vertical
        // divider line, i.e. panes arranged side by side.
        splitView.isVertical = axis == .sideBySide
        splitView.dividerStyle = .thin
        // Pane minimum sizes are enforced through the delegate below
        // (`constrainMinCoordinate`), NOT Auto Layout constraints on each
        // hosting view — a first attempt added a plain
        // `greaterThanOrEqualToConstant` width/height constraint per pane,
        // which fights `NSSplitView`'s own internal Auto Layout management
        // of its arranged subviews' constraints, snapping panes back
        // toward their minimum on almost every SwiftUI-driven re-render.
        splitView.delegate = context.coordinator
        // jensyleo's own report (2026-08-19): `updateNSView` (SwiftUI's own
        // update cadence) is what `applyRestoredLayoutIfPossible` used to
        // rely on being called repeatedly until a non-zero frame showed up
        // — true for a split nested inside a view that re-renders often
        // (`LibraryDetailView`'s own internal splits), but a split at
        // `ContentView`'s own root barely re-renders at all once launched.
        // Measured directly (not just visually) via `System Events`:
        // `updateNSView` fired exactly once, at `total == 0`, and never
        // again — so the restore never got a real size to apply against.
        // `ObservingSplitView.onLayout` calls back on *every* real AppKit
        // layout pass instead, which happens whenever this view actually
        // gets its final size, entirely independent of how often SwiftUI
        // itself re-renders the surrounding view.
        splitView.onLayout = { [weak splitView] in
            guard let splitView else { return }
            context.coordinator.applyRestoredLayoutIfPossible(to: splitView)
        }
        splitView.onDragEnded = { [weak splitView] in
            guard let splitView else { return }
            context.coordinator.saveCurrentLayout(of: splitView)
        }
        for pane in panes {
            let hosting = NSHostingView(rootView: pane.view)
            // Frame-based, not Auto Layout — sizing here is driven
            // directly by divider drags and by `Coordinator`'s restore,
            // not by a competing constraint system.
            hosting.translatesAutoresizingMaskIntoConstraints = true
            splitView.addArrangedSubview(hosting)
        }
        return splitView
    }

    /// A plain `NSSplitView` with two additions: a hook into AppKit's own
    /// `layout()` pass (see `makeNSView`'s doc comment for why that exists
    /// instead of relying on SwiftUI's `updateNSView` alone), and a
    /// trustworthy answer to "is the user dragging a divider right now?".
    ///
    /// That second one has to be exact, because it decides when the stored
    /// layout may be overwritten — see `Coordinator
    /// .splitViewDidResizeSubviews`. `NSSplitView` runs its divider drag as
    /// a modal event-tracking loop inside `mouseDown(with:)`, so the whole
    /// drag — every intermediate resize it reports — happens between this
    /// override setting the flag and `super` returning at mouse-up.
    /// Nothing else in the app's lifetime falls inside that window.
    ///
    /// `splitView(_:constrainSplitPosition:ofSubviewAt:)` was tried first,
    /// on the strength of it being documented as a drag-time callback. It
    /// is not one here: logging it live showed AppKit calling it during
    /// this view's own initial arrangement at launch, with no mouse
    /// involved at all — which was enough to persist a degenerate startup
    /// layout (observed directly: `[0.173, 0.825, 0.0]`, the right pane at
    /// literally zero width) straight over the user's saved proportions.
    final class ObservingSplitView: NSSplitView {
        var onLayout: (() -> Void)?
        /// Called once the user's drag has finished, so the layout they
        /// settled on gets persisted even though the flag below is already
        /// back to `false` by the time any final resize is reported.
        var onDragEnded: (() -> Void)?
        private(set) var isUserDraggingDivider = false

        override func layout() {
            super.layout()
            onLayout?()
        }

        override func mouseDown(with event: NSEvent) {
            isUserDraggingDivider = true
            // Blocks for the entire drag: AppKit's own modal tracking loop
            // lives in here, and every resize it reports arrives before
            // this returns.
            super.mouseDown(with: event)
            isUserDraggingDivider = false
            onDragEnded?()
        }
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        // Panes capture live `@State`/`@Observable` data that changes over
        // time — each hosting view's `rootView` needs refreshing on every
        // SwiftUI re-render, same as any other `NSViewRepresentable`.
        for (index, pane) in panes.enumerated() {
            guard let hosting = nsView.arrangedSubviews[safe: index] as? NSHostingView<AnyView> else { continue }
            hosting.rootView = pane.view
        }
        // Idempotent: applies the saved layout the first time (and only
        // the first time) `nsView` has a real, non-zero frame to apply it
        // against — however many `updateNSView` calls that takes.
        context.coordinator.applyRestoredLayoutIfPossible(to: nsView)
    }

    // `@MainActor` — AppKit's `NSView`/`NSSplitView` are only ever valid to
    // touch from the main thread anyway (real, standing AppKit constraint,
    // not new here); without this the compiler saw `Coordinator`'s methods
    // as `nonisolated` and flagged every `frame`/`setPosition`/
    // `dividerThickness` access below as a cross-actor reference. 2026-08-13
    // cleanup pass, no behavior change (an `NSSplitViewDelegate` is always
    // called back on the main thread by AppKit itself regardless).
    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        let axis: Axis
        let minLengths: [CGFloat]
        let defaultsKey: String
        let defaultFractions: [Double]?
        private var didApplyRestore = false
        // jensyleo's own report (2026-08-26): a resized pane snapped back to
        // roughly its minimum size (not the size it was left at) after a
        // quit/relaunch. Root-caused live (via stderr-logged instrumentation
        // through several real drag+quit+relaunch cycles): this view's very
        // first non-trivial `total` during launch is a TRANSIENT width
        // (observed consistently: ~868pt) smaller than the window's real,
        // final width (observed: ~1438pt) reached a moment later as SwiftUI
        // finishes laying out. The old code applied the restore exactly
        // once, at whatever `total` first cleared the "not degenerate"
        // guard — if a saved fraction was perfectly valid at the real final
        // width but computed to a pixel size below `minLengths` at that
        // smaller transient width, `NSSplitView`'s own delegate-constrained
        // `setPosition` silently clamped it up to the bare minimum, and
        // that clamped layout then just scaled proportionally as the window
        // grew to its final size — never re-deriving the correct fractions.
        //
        // Two timing-based attempts followed, both wrong. The first
        // re-applied on every width change until the same width was seen
        // twice running, then locked — but the transient width itself
        // repeats across consecutive passes, so it locked on the wrong one
        // just the same. The second deferred the apply through
        // `DispatchQueue.main.asyncAfter` scheduled from `layout()`. That
        // one did hold, but jensyleo then reported every divider in the
        // window lagging behind the mouse, and it was the cause:
        // `layout()` runs on every layout pass, and `DispatchWorkItem
        // .cancel()` does not remove an already-scheduled `asyncAfter`
        // from the queue — it only makes the block a no-op when it runs —
        // so each pass left another timer behind to wake the main queue at
        // its own deadline, burying the run loop AppKit drives its modal
        // divider-tracking loop on.
        //
        // What both were really working around is that the *saved* value
        // could be corrupted in the first place, which is the actual root
        // cause and is now fixed at the source instead:
        // `splitViewDidResizeSubviews` used to persist on every resize
        // notification, and AppKit sends plenty that have nothing to do
        // with the user — this view's own degenerate initial arrangement
        // at launch (logged live as `[0.173, 0.825, 0.0]`), every window
        // resize, the teardown passes as a window closes. Each of those
        // overwrote the proportions the user had actually chosen. Saving
        // is now gated on a real divider drag, detected exactly (see
        // `ObservingSplitView.isUserDraggingDivider`).
        //
        // With the stored value guaranteed to only ever be something the
        // user chose, restoring needs no timing heuristic at all: re-apply
        // whenever this split view's own length changes, reading the saved
        // value fresh each time. A transient launch width applies clamped
        // and harmlessly, the real width that follows re-applies correctly,
        // and nothing is persisted in between to poison the next launch.
        // A divider drag never changes the split view's own length — only
        // how that length is divided — so this can never fight a drag
        // either, and no timers are involved anywhere.
        private var appliedAgainstTotal: CGFloat?
        init(axis: Axis, minLengths: [CGFloat], defaultsKey: String, defaultFractions: [Double]? = nil) {
            self.axis = axis
            self.minLengths = minLengths
            self.defaultsKey = defaultsKey
            self.defaultFractions = defaultFractions
        }

        private func length(of view: NSView, in splitView: NSSplitView) -> CGFloat {
            axis == .sideBySide ? view.frame.width : view.frame.height
        }

        private func totalLength(of splitView: NSSplitView) -> CGFloat {
            axis == .sideBySide ? splitView.frame.width : splitView.frame.height
        }

        func applyRestoredLayoutIfPossible(to splitView: NSSplitView) {
            let total = totalLength(of: splitView)
            // A fresh SwiftUI-hosted view often starts at .zero (or some
            // other transient size) before its real layout pass — applying
            // fractions against that would just reproduce the exact
            // degenerate-collapse bug this replaced `autosaveName` to fix.
            guard total > CGFloat(minLengths.count) * 4 else { return }
            // Already positioned against exactly this length. This is the
            // common case on all but a handful of passes — including every
            // pass a divider drag causes, since a drag redistributes this
            // length without changing it. One comparison, no allocation.
            if let appliedAgainstTotal, abs(appliedAgainstTotal - total) < 0.5 { return }
            appliedAgainstTotal = total
            didApplyRestore = true
            // `NSSplitView`'s own default initial arrangement — used
            // whenever nothing is explicitly positioned — turned out to be
            // genuinely non-deterministic in this specific SwiftUI-hosted
            // context: observed, repeatedly, collapsing the two edge panes
            // to exactly zero width on some launches and not others, with
            // no drag and no saved data involved at all. Rather than ever
            // relying on it, a position is set explicitly for every
            // divider below — from saved fractions if there are any, or an
            // even split otherwise — so there's never a moment where this
            // split view's layout is whatever `NSSplitView` felt like.
            let fractions: [Double]
            if let saved = UserDefaults.standard.array(forKey: defaultsKey) as? [Double], saved.count == minLengths.count {
                fractions = saved
            } else if let defaultFractions, defaultFractions.count == minLengths.count {
                fractions = defaultFractions
            } else {
                fractions = Array(repeating: 1.0 / Double(minLengths.count), count: minLengths.count)
            }
            apply(fractions: fractions, to: splitView)
        }

        private func apply(fractions: [Double], to splitView: NSSplitView) {
            let total = totalLength(of: splitView)
            var position: CGFloat = 0
            for index in 0..<(fractions.count - 1) {
                position += CGFloat(fractions[index]) * total
                splitView.setPosition(position, ofDividerAt: index)
                position += splitView.dividerThickness
            }
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            // `NSSplitView` sends this for far more than user drags: its
            // own initial arrangement at launch, every window resize, and
            // the teardown passes as a window closes. Persisting on all of
            // them is what made the stored proportions unreliable in the
            // first place — any layout AppKit settled on by itself got
            // written straight over the proportions the user had chosen,
            // and the next launch faithfully restored *that*. Only a real
            // divider drag may change a stored preference now.
            guard let splitView = notification.object as? ObservingSplitView,
                  splitView.isUserDraggingDivider
            else { return }
            saveCurrentLayout(of: splitView)
        }

        /// Persists the layout as it stands right now. Only ever called
        /// from a context that has already established the user is the one
        /// who put it that way — mid-drag, or immediately after one ends.
        func saveCurrentLayout(of splitView: NSSplitView) {
            guard didApplyRestore else { return }
            let total = totalLength(of: splitView)
            guard total > 1 else { return }
            let fractions = splitView.arrangedSubviews.map { length(of: $0, in: splitView) / total }
            // A settled drag always reports a sane, in-range set of
            // fractions — anything summing far from 1 (a transient
            // mid-layout state) isn't a real answer to save.
            guard abs(fractions.reduce(0, +) - 1) < 0.01 else { return }
            UserDefaults.standard.set(fractions, forKey: defaultsKey)
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard minLengths.indices.contains(dividerIndex) else { return proposedMinimumPosition }
            return proposedMinimumPosition + minLengths[dividerIndex]
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            let nextIndex = dividerIndex + 1
            guard minLengths.indices.contains(nextIndex) else { return proposedMaximumPosition }
            return proposedMaximumPosition - minLengths[nextIndex]
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
