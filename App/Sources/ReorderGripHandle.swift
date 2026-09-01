// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import SwiftUI

/// A grip-icon (`line.3.horizontal`) handle enabling ⌘-drag reordering —
/// jensyleo's own request (2026-08-31), evolving an earlier menu-based
/// "Move Up"/"Move Down" grip into a direct drag. Gated behind the ⌘ key
/// specifically because a plain drag gesture on a `List`/`Form` row has
/// repeatedly fought this app's own existing tap/selection gestures on the
/// very same row — `romFolderRow`'s own doc comment (`LibraryDetailView.swift`)
/// documents three prior drag-and-drop attempts that all lost to exactly
/// that conflict, settling on plain ↑/↓ buttons instead. Requiring ⌘
/// sidesteps the whole problem: an ordinary click still does whatever it
/// always did (select a row, tap a toggle), and only a ⌘-held drag ever
/// reorders anything.
///
/// jensyleo's own report (2026-08-31, second pass): "solo de a un renglon y
/// no resalta la línea" — a first version reordered the *actual* backing
/// array as the drag crossed each row boundary. That's exactly what broke
/// it: `ForEach(id: \.element)` re-homes the dragged row's own view to a new
/// position in the list the instant the array changes, and that mid-gesture
/// re-parenting was enough for AppKit to treat the drag as having left the
/// view, ending it after exactly one step. This version follows the same
/// idea the menu bar's own icon reordering uses: the backing array is never
/// actually reordered until the drag *ends* (in `onCommit`) — so the
/// gesture's own view identity never changes mid-drag.
///
/// jensyleo's own follow-up report (same day, third pass): "quiero que se
/// pueda sostener, resalte la línea, y mover más allá de un renglón —
/// revisa cómo lo hace la barra de menús". A second version tried to make
/// the dragged row's own live content float with the cursor via
/// `.offset(y:)`, shifting sibling rows out of the way the same amount —
/// that's exactly how the real menu bar reorder looks, but it doesn't work
/// inside a SwiftUI `List` on macOS: each row is clipped to its own fixed
/// row rect (an `NSTableView` cell under the hood), so content offset far
/// enough to visually reach a neighboring row's slot gets clipped away
/// entirely — confirmed live: the dragged row went blank and the rows it
/// should have floated past disappeared rather than sliding. This settled,
/// for that pass, on lighter clip-safe feedback instead: the source row's
/// own background highlight, and a thin drop-line on the row under the
/// cursor — both painted via each row's own `.background`/`.overlay`,
/// never moved outside that row's own bounds.
///
/// jensyleo's own follow-up (same day, fourth pass): "falta que lo dejes
/// visualmente como en la barra de iconos superior" — the drop-line alone
/// doesn't look like something is actually being picked up and carried.
/// This version adds that back the way the menu bar really does it:
/// instead of moving the real row (which is what got clipped), a *ghost*
/// — a free-floating duplicate of the row's own content — is drawn in a
/// `.overlay` attached to the whole list/form container, not to any one
/// row. That overlay is a sibling of the rows in the view tree, not nested
/// inside one, so nothing about `List`'s own per-row clipping ever touches
/// it. Every row reports its own on-screen frame via
/// `reportReorderFrame(_:)` (a `GeometryReader` in a `.background`,
/// publishing through `RowFramePreferenceKey`); the ghost is positioned at
/// the dragged row's own captured frame, offset by the gesture's *raw*
/// (unstepped) translation, so it tracks the cursor smoothly rather than
/// jumping row to row. The real row stays exactly where it is underneath,
/// still carrying the highlight from the third pass — dimmed slightly so
/// the ghost above it reads as the thing actually moving.
struct ReorderGripHandle: View {
    /// This row's own current position among its siblings — used only to
    /// compute `dragPreviewIndex` from the raw drag distance; never mutated
    /// here.
    let index: Int
    /// Total number of rows in this list — clamps `dragPreviewIndex` so a
    /// drag past either end just pins at the first/last row instead of
    /// computing a nonsense target.
    let count: Int
    /// The list's own per-row height, in points — how far (in points) the
    /// cursor has to move to cross one row boundary. Callers should pass
    /// this row's own measured frame height (`rowFrames[index]?.height`,
    /// from the same `reportReorderFrame(_:)`/`reorderGhostOverlay` this
    /// handle already needs) rather than a guessed constant — jensyleo's
    /// own report (2026-09-01): a `List` row and a `Form`/`.formStyle(.grouped)`
    /// `Section` row are NOT the same height, so a hardcoded value tuned
    /// for one made the drop-line land on a different row than the ghost
    /// was actually floating over in the other. A static fallback (for the
    /// first frame, before any row has reported its real height yet) is
    /// still fine — just not the steady-state value.
    let rowHeight: CGFloat
    /// The original index of whichever row is currently being ⌘-dragged,
    /// `nil` when nothing is. Shared (one binding) across every row in the
    /// list so each row can tell whether *it's* the one being dragged, and
    /// so sibling rows can compute their own shift-out-of-the-way offset.
    @Binding var draggingIndex: Int?
    /// Where the dragged row would land right now if the drag ended this
    /// instant — updates live as the cursor moves, independent of the real
    /// backing array (which doesn't change until the drag actually ends).
    @Binding var dragPreviewIndex: Int?
    /// The drag's own raw vertical translation, in points, straight from
    /// the gesture — never stepped or rounded. Exists only so the caller's
    /// ghost overlay (`reorderGhostOverlay`) can track the cursor smoothly;
    /// the actual target row (`dragPreviewIndex`) is computed independently
    /// above.
    @Binding var dragOffset: CGFloat
    /// Called exactly once, when a real ⌘-drag ends somewhere other than
    /// where it started — `(from, to)` are both original-array indices;
    /// never called for a drag that ends back where it began.
    let onCommit: (Int, Int) -> Void

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            // `.highPriorityGesture` (not plain `.gesture`) — this icon
            // always sits inside a row that already claims its own tap/
            // selection gesture, and a plain `.gesture` here lost that
            // priority fight often enough that ⌘-dragging the grip simply
            // did nothing (jensyleo's own report, 2026-08-31: "no funciona
            // con command + click").
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { value in
                        guard NSEvent.modifierFlags.contains(.command) else {
                            // Not (or no longer) holding ⌘ — release cleanly
                            // if this row was the one dragging, so lifting ⌘
                            // mid-gesture cancels rather than commits.
                            if draggingIndex == index {
                                draggingIndex = nil
                                dragPreviewIndex = nil
                                dragOffset = 0
                            }
                            return
                        }
                        if draggingIndex != index {
                            draggingIndex = index
                            dragPreviewIndex = index
                        }
                        dragOffset = value.translation.height
                        let steps = (value.translation.height / rowHeight).rounded()
                        let target = min(max(index + Int(steps), 0), max(count - 1, 0))
                        if dragPreviewIndex != target {
                            dragPreviewIndex = target
                        }
                    }
                    .onEnded { _ in
                        if let from = draggingIndex, let to = dragPreviewIndex, from != to {
                            onCommit(from, to)
                        }
                        draggingIndex = nil
                        dragPreviewIndex = nil
                        dragOffset = 0
                    }
            )
            .help("⌘ + clic y arrastra para reordenar")
    }

    /// Which edge (if any) `rowIndex` should paint a drop-line on right now
    /// — `nil` when nothing is dragging, when `rowIndex` isn't the current
    /// live target, or when the target is the dragged row's own original
    /// slot (dropping back where it started needs no line). Kept as a thin
    /// per-row overlay rather than moving any row's own content, since a
    /// `List` row on macOS clips anything drawn or offset outside its own
    /// bounds — see this type's own doc comment for how that broke an
    /// earlier "float the row with the cursor" version.
    static func dropIndicatorEdge(
        for rowIndex: Int,
        draggingIndex: Int?,
        dragPreviewIndex: Int?
    ) -> VerticalEdge? {
        guard let dragged = draggingIndex, let target = dragPreviewIndex,
              target == rowIndex, target != dragged else { return nil }
        return target > dragged ? .bottom : .top
    }

    /// The real on-screen distance from one row to the next — jensyleo's
    /// own report (2026-09-01): "su comportamiento es diferente al de los
    /// otros" (the ghost and the drop-line disagreeing about which row a
    /// drag was over, only in the two `Form`/`Section`-hosted lists). The
    /// bug: a row's own measured *height* (`rowFrames[index]?.height`,
    /// what an earlier fix used in place of a guessed constant) is NOT the
    /// same thing as the screen distance between two consecutive rows —
    /// confirmed live via a temporary debug label: every row's own content
    /// measured exactly 24pt tall, but `Form`'s `.formStyle(.grouped)`
    /// visibly inserts real extra spacing between rows that belongs to
    /// neither row's own frame, making the true on-screen pitch closer to
    /// 45pt. Diffing two adjacent rows' actual captured `minY` values
    /// (`rowFrames`, from `reportReorderFrame(_:)`) measures that real
    /// pitch directly instead of guessing at it a second way — works
    /// identically for `List`, `Form`, or a plain `VStack`, since none of
    /// them need to agree on how much of that gap "belongs" to which row.
    static func measuredRowPitch(
        at index: Int,
        rowFrames: [Int: CGRect],
        fallback: CGFloat
    ) -> CGFloat {
        if let here = rowFrames[index]?.minY, let next = rowFrames[index + 1]?.minY {
            return next - here
        }
        if let prev = rowFrames[index - 1]?.minY, let here = rowFrames[index]?.minY {
            return here - prev
        }
        return rowFrames[index]?.height ?? fallback
    }
}

/// Publishes each reorderable row's own on-screen frame (keyed by its
/// index) up to the shared container hosting `reorderGhostOverlay` — how
/// the ghost knows where the dragged row actually sits, in that
/// container's own coordinate space, without either view needing to know
/// the other's exact position ahead of time.
struct ReorderRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Paints a thin accent-colored line on the given edge of this row —
    /// the "you're about to drop it here" cue for whichever row currently
    /// sits under a ⌘-drag in progress (see `ReorderGripHandle.dropIndicatorEdge`).
    /// A no-op (no overlay at all) when `edge` is `nil`.
    @ViewBuilder
    func reorderDropIndicator(_ edge: VerticalEdge?) -> some View {
        switch edge {
        case .top:
            overlay(alignment: .top) { Rectangle().fill(Color.accentColor).frame(height: 2) }
        case .bottom:
            overlay(alignment: .bottom) { Rectangle().fill(Color.accentColor).frame(height: 2) }
        case nil:
            self
        }
    }

    /// Reports this row's own frame, in `.global` (window) coordinates, up
    /// to whichever ancestor hosts `reorderGhostOverlay` — call this on
    /// every row of a reorderable list, passing that row's own current
    /// index. Deliberately `.global` rather than a named coordinate space
    /// scoped to the container: a named space didn't reliably propagate
    /// across a `List` row's own `NSTableView`-backed cell boundary on
    /// macOS (confirmed live — the ghost landed nowhere near the actual
    /// dragged row), while `.global` reflects each row's real on-screen
    /// position regardless of how the row is hosted internally.
    func reportReorderFrame(_ index: Int) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ReorderRowFramePreferenceKey.self,
                    value: [index: geo.frame(in: .global)]
                )
            }
        )
    }

    /// Draws the floating "ghost" of whichever row is currently being
    /// ⌘-dragged, tracking the cursor smoothly via the gesture's raw
    /// `dragOffset` — the visual the menu bar's own icon reordering shows,
    /// achieved here as an overlay on the *container* (this view) rather
    /// than by moving the dragged row itself, since that row lives inside
    /// a `List`/`Form` that clips anything moved outside its own bounds
    /// (see `ReorderGripHandle`'s own doc comment). `rowFrames` (from
    /// `reportReorderFrame(_:)`) arrive in `.global` coordinates; this
    /// measures the container's own `.global` origin the same way and
    /// subtracts it, so the ghost lands at the right spot inside this
    /// specific view's own overlay regardless of where that view sits on
    /// screen.
    @ViewBuilder
    func reorderGhostOverlay<Ghost: View>(
        draggingIndex: Int?,
        dragOffset: CGFloat,
        rowFrames: [Int: CGRect],
        @ViewBuilder ghost: @escaping (Int) -> Ghost
    ) -> some View {
        overlay(
            GeometryReader { containerGeo in
                let containerOrigin = containerGeo.frame(in: .global).origin
                ZStack(alignment: .topLeading) {
                    if let dragged = draggingIndex, let frame = rowFrames[dragged] {
                        ghost(dragged)
                            .frame(width: frame.width, height: frame.height)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1))
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                            .position(
                                x: frame.midX - containerOrigin.x,
                                y: frame.midY - containerOrigin.y + dragOffset
                            )
                            .allowsHitTesting(false)
                    }
                }
            }
        )
    }
}

extension Array {
    /// Moves the element at `source` so it ends up at `destination` (an
    /// index into the array's *original* order, matching what
    /// `ReorderGripHandle`'s own `dragPreviewIndex` computes) — a real
    /// move, not the adjacent-swap the old ↑/↓ buttons used, so one
    /// continuous drag can relocate an item several rows in a single call.
    mutating func moveElement(from source: Int, to destination: Int) {
        guard indices.contains(source), source != destination else { return }
        let item = remove(at: source)
        insert(item, at: Swift.min(Swift.max(destination, 0), count))
    }
}
