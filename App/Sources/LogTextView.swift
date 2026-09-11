// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import SwiftUI

/// A real, native multi-line text view for the Log panel — jensyleo's own
/// report (2026-09-10): SwiftUI's `.textSelection(.enabled)` on separate
/// `Text` views (one per log line, inside a `LazyVStack`) only ever lets
/// you select text WITHIN one line at a time; dragging a selection across
/// several lines silently loses part of it — "eso de que me deje
/// seleccionar algunas partes sí y otras no... no está bien". A genuine
/// `NSTextView` (read-only, but fully selectable) is what actually
/// supports selecting — and copying (⌘C) — an arbitrary range spanning
/// any number of lines, exactly like every other macOS text view. Native
/// right-click already offers "Copy" for whatever's selected; the
/// toolbar's own "Copy Log" button (`LibraryDetailView.copyLogToClipboard`)
/// stays as the one-click "just give me everything" shortcut.
struct LogTextView: NSViewRepresentable {
    let lines: [LogLine]

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Rebuilding the whole attributed string is real work on a long
        // log — skip it entirely when the line count hasn't actually
        // changed (a sibling view re-rendering shouldn't reset this one's
        // scroll position or momentarily drop the user's own selection).
        guard lines.count != context.coordinator.lastLineCount else { return }
        context.coordinator.lastLineCount = lines.count

        let wasAtBottom = isScrolledToBottom(scrollView)
        textView.textStorage?.setAttributedString(Self.attributedString(for: lines))
        if wasAtBottom {
            textView.scrollToEndOfDocument(nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastLineCount = -1
    }

    private func isScrolledToBottom(_ scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        // Within a small margin, not pixel-exact — a scan that's still
        // actively appending lines shouldn't make the view feel like it
        // stopped auto-scrolling over a few points of rounding error.
        return scrollView.contentView.bounds.maxY >= documentView.bounds.maxY - 24
    }

    private static func attributedString(for lines: [LogLine]) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(for: line.kind)]
            result.append(NSAttributedString(string: line.text, attributes: attributes))
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }
        return result
    }

    /// Same four colors `LibraryDetailView.logLineColor(for:)` uses for
    /// `Color` — this is the `NSColor` equivalent, since an `NSTextView`
    /// takes its per-run color as an `NSAttributedString` attribute, not a
    /// SwiftUI `.foregroundStyle`.
    private static func color(for kind: LogLineKind) -> NSColor {
        switch kind {
        case .info: return .labelColor
        case .success: return .systemGreen
        case .warning: return .systemOrange
        case .error: return .systemRed
        }
    }
}
