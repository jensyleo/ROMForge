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

    func makeCoordinator() -> Coordinator {
        Coordinator(axis: axis, minLengths: panes.map(\.minLength), defaultsKey: "ROMForge.splitFractions.\(autosaveName)")
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
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

    final class Coordinator: NSObject, NSSplitViewDelegate {
        let axis: Axis
        let minLengths: [CGFloat]
        let defaultsKey: String
        private var didApplyRestore = false

        init(axis: Axis, minLengths: [CGFloat], defaultsKey: String) {
            self.axis = axis
            self.minLengths = minLengths
            self.defaultsKey = defaultsKey
        }

        private func length(of view: NSView, in splitView: NSSplitView) -> CGFloat {
            axis == .sideBySide ? view.frame.width : view.frame.height
        }

        private func totalLength(of splitView: NSSplitView) -> CGFloat {
            axis == .sideBySide ? splitView.frame.width : splitView.frame.height
        }

        func applyRestoredLayoutIfPossible(to splitView: NSSplitView) {
            guard !didApplyRestore else { return }
            let total = totalLength(of: splitView)
            // A fresh SwiftUI-hosted view often starts at .zero (or some
            // other transient size) before its real layout pass — applying
            // fractions against that would just reproduce the exact
            // degenerate-collapse bug this replaced `autosaveName` to fix.
            guard total > CGFloat(minLengths.count) * 4 else { return }
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
            } else {
                fractions = Array(repeating: 1.0 / Double(minLengths.count), count: minLengths.count)
            }
            var position: CGFloat = 0
            for index in 0..<(fractions.count - 1) {
                position += CGFloat(fractions[index]) * total
                splitView.setPosition(position, ofDividerAt: index)
                position += splitView.dividerThickness
            }
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            // `NSSplitView` fires this for its own *initial* natural
            // layout too, not just user drags — before `applyRestoredLayout
            // IfPossible` (called from `updateNSView`, which can run after
            // this first internal layout pass) has had any chance to run.
            // Saving unconditionally meant that very first, unwanted
            // natural-layout event would overwrite a real saved value
            // before it was ever read back — reproducing, one level up,
            // the same "the real value never actually gets applied"
            // symptom this rewrite was meant to fix. Ignored until our own
            // restore step has run at least once (successfully applying a
            // saved layout, or confirming there was none to apply).
            guard didApplyRestore else { return }
            guard let splitView = notification.object as? NSSplitView else { return }
            let total = totalLength(of: splitView)
            guard total > 1 else { return }
            let fractions = splitView.arrangedSubviews.map { length(of: $0, in: splitView) / total }
            // A user drag (or a restore we just applied) always reports a
            // sane, in-range set of fractions — anything summing far from
            // 1 (a transient mid-layout state) isn't a real answer to save.
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
