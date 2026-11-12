// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import SwiftUI

/// "ROMForge Help" window (`CommandGroup(replacing: .help)` in
/// `ROMForgeApp`) — jensyleo's own request (2026-08-12): "la app debe tener
/// un about y un help donde explique cosas como esas... colócalos con lo
/// básico de la app". Rebuilt 2026-09-03 as a searchable sidebar of topics
/// instead of one long scrolling page, matching jensyleo's own
/// HardwareSentry `HelpView`/`HelpTopic` exactly ("ponle la documentacion
/// de ayuda como la que usa hardwareSentry. Es mas profesional") — same
/// `NavigationSplitView` + `.searchable` sidebar, same term-row styling for
/// enumerable actions/settings. Content in `HelpTopic.swift` covers the
/// app end to end, Fase 1 (read-only audit) and Fase 2 (write actions)
/// alike — not exhaustive API documentation.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var topics: [HelpTopic] = HelpLibrary.topics
    @State private var selection: HelpTopic.ID? = HelpLibrary.topics.first?.id
    @State private var query = ""

    private var matches: [HelpTopic] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return topics }
        return topics.filter { topic in
            if topic.title.lowercased().contains(needle) { return true }
            return topic.sections.contains { section in
                (section.heading?.lowercased().contains(needle) ?? false)
                    || section.paragraphs.contains { $0.lowercased().contains(needle) }
                    || section.rows.contains {
                        $0.term.lowercased().contains(needle) || $0.detail.lowercased().contains(needle)
                    }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $selection) {
                    ForEach(matches) { topic in
                        Label(topic.title, systemImage: topic.symbol).tag(topic.id)
                    }
                }
                .searchable(text: $query, placement: .sidebar, prompt: "Search help")
                .navigationSplitViewColumnWidth(min: 220, ideal: 240)
                .overlay {
                    if matches.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
            } detail: {
                if let topic = topics.first(where: { $0.id == selection }) {
                    TopicPage(topic: topic)
                } else {
                    ContentUnavailableView("Pick a topic", systemImage: "book")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            // jensyleo's own request (2026-09-03): a visible "Done" button
            // to close the window, alongside — not instead of — the native
            // red traffic-light close button, plus Escape as a second way
            // to close it (same pattern as `AppSettingsView`'s own
            // "Done"/hidden "Close" pair).
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

private struct TopicPage: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(topic.title)
                    .font(.largeTitle.weight(.semibold))
                    .textSelection(.enabled)

                ForEach(topic.sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        if let heading = section.heading {
                            Text(heading).font(.title3.weight(.semibold))
                        }

                        ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            HelpText(paragraph, font: .body, nsFont: .systemFont(ofSize: NSFont.systemFontSize))
                        }

                        if !section.rows.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                                    if index > 0 { Divider() }
                                    TermRow(row: row)
                                }
                            }
                            .background(.quinary, in: .rect(cornerRadius: 8))
                        }
                    }
                }
            }
            // Kept near 65 characters of running text; a help page read
            // edge to edge on a wide window is a help page nobody finishes.
            .frame(maxWidth: 620, alignment: .leading)
            .textSelection(.enabled)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TermRow: View {
    let row: HelpSection.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.term).font(.body.weight(.medium))
                if let note = row.note {
                    Text(note)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                }
            }
            HelpText(row.detail, font: .callout, nsFont: .preferredFont(forTextStyle: .callout))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// Makes every web address in Help text clickable, without interpreting any other
/// markup (the help text uses `*` and backticks literally).
enum HelpLinks {
    /// Dat-o-Matic's download page, not its home page: that site's front page answers a
    /// request without a page parameter with a block of the visitor's address.
    static let datomaticDownloadPage = "https://datomatic.no-intro.org/index.php?page=download&s=64"

    private static let domainTargets: [(text: String, url: String)] = [
        ("datomatic.no-intro.org", datomaticDownloadPage),
        ("redump.org", "https://redump.org/downloads/"),
        ("tosecdev.org", "https://www.tosecdev.org/"),
    ]

    private static let urlPattern = try? NSRegularExpression(pattern: #"https?://[^\s)\]"`]+"#)

    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let nsText = text as NSString
        var linked: [NSRange] = []
        // Full addresses first (trailing punctuation is not part of the link).
        for match in urlPattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? [] {
            var range = match.range
            while range.length > 1, ".,;:".contains(nsText.substring(with: NSRange(location: range.location + range.length - 1, length: 1))) {
                range.length -= 1
            }
            apply(nsText.substring(with: range), range, in: text, to: &result, linked: &linked)
        }
        // Then well-known sites written without a scheme.
        for (domain, url) in domainTargets {
            var searchRange = NSRange(location: 0, length: nsText.length)
            while true {
                let found = nsText.range(of: domain, options: .caseInsensitive, range: searchRange)
                if found.location == NSNotFound { break }
                if !linked.contains(where: { NSIntersectionRange($0, found).length > 0 }) {
                    apply(url, found, in: text, to: &result, linked: &linked)
                }
                let next = found.location + found.length
                searchRange = NSRange(location: next, length: nsText.length - next)
            }
        }
        return result
    }

    private static func apply(_ target: String, _ range: NSRange, in text: String, to result: inout AttributedString, linked: inout [NSRange]) {
        guard let url = URL(string: target), let swiftRange = Range(range, in: text),
              let lower = AttributedString.Index(swiftRange.lowerBound, within: result),
              let upper = AttributedString.Index(swiftRange.upperBound, within: result) else { return }
        result[lower..<upper].link = url
        linked.append(range)
    }
}

/// Secondary help text. A paragraph with a link is drawn by AppKit, which shows
/// the pointing-hand cursor over the link (SwiftUI's `Text` keeps the arrow).
private struct HelpText: View {
    let text: String
    let font: Font
    let nsFont: NSFont

    init(_ text: String, font: Font, nsFont: NSFont) {
        self.text = text
        self.font = font
        self.nsFont = nsFont
    }

    var body: some View {
        let attributed = HelpLinks.attributed(text)
        if attributed.runs.contains(where: { $0.link != nil }) {
            LinkLabel(text: attributed, font: nsFont)
        } else {
            Text(attributed)
                .font(font)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LinkLabel: NSViewRepresentable {
    let text: AttributedString
    let font: NSFont

    func makeNSView(context: Context) -> LinkTextView {
        let view = LinkTextView()
        view.isEditable = false
        view.isSelectable = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        return view
    }

    func updateNSView(_ view: LinkTextView, context: Context) {
        let string = NSMutableAttributedString(text)
        let whole = NSRange(location: 0, length: string.length)
        string.addAttribute(.font, value: font, range: whole)
        string.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: whole)
        string.enumerateAttribute(.link, in: whole) { value, range, _ in
            guard value != nil else { return }
            string.addAttributes([.foregroundColor: NSColor.linkColor, .underlineStyle: 0], range: range)
        }
        view.textStorage?.setAttributedString(string)
        view.window?.invalidateCursorRects(for: view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: LinkTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 480
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(layout.usedRect(for: container).height))
    }
}

/// Non-selectable text whose links show the pointing hand and open on click.
final class LinkTextView: NSTextView {
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {}
    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func mouseEntered(with event: NSEvent) { updateCursor(event) }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    private func updateCursor(_ event: NSEvent) {
        (link(at: event) != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    private func link(at event: NSEvent) -> URL? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let glyph = layout.glyphIndex(for: point, in: container)
        guard layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(point) else { return nil }
        switch storage.attribute(.link, at: layout.characterIndexForGlyph(at: glyph), effectiveRange: nil) {
        case let url as URL: return url
        case let text as String: return URL(string: text)
        default: return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let url = link(at: event) { NSWorkspace.shared.open(url) }
    }
}
