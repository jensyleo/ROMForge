// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import ROMForgeCore

/// Builds a single, self-contained, printable HTML report across every
/// configured system — jensyleo's own request (2026-08-18), one of the GUI
/// checklist items: "reporte imprimible/HTML... combina stats globales +
/// detalle por sistema, tipo 'Collection Report' de RomVault". Plain HTML
/// (no JS, no external resources) specifically so opening it in the
/// default browser and pressing ⌘P just works — that's the "printable"
/// part, no separate print pipeline of our own needed.
enum CollectionReportExporter {
    /// Reads each system's *last saved scan* straight from
    /// `AuditReportDatabase` (the same source `ContentView`'s sidebar dots
    /// already read from) rather than requiring every system to be
    /// re-scanned just to produce this report — a system with no scan yet
    /// simply shows as "Not scanned yet" instead of being skipped, so the
    /// report still accounts for every configured system.
    static func generate(systems: [RomSystem]) -> String {
        let db = try? AuditDatabaseLocation.open()
        let rows: [(system: RomSystem, report: AuditReport?, datName: String?, scannedAt: Date?)] = systems.map { system in
            guard let db else { return (system, nil, nil, nil) }
            let report = (try? db.loadReport(systemID: system.id.uuidString)).flatMap { $0 }
            let meta = (try? db.loadScanMeta(systemID: system.id.uuidString)).flatMap { $0 }
            return (system, report, meta?.datName, meta?.scannedAt)
        }

        let scannedRows = rows.filter { $0.report != nil }
        let totals = scannedRows.reduce(into: (correct: 0, incorrect: 0, badDump: 0, missing: 0, surplus: 0, unverifiable: 0)) { totals, row in
            guard let report = row.report else { return }
            totals.correct += report.correct
            totals.incorrect += report.incorrect
            totals.badDump += report.badDump
            totals.missing += report.missing
            totals.surplus += report.surplus
            totals.unverifiable += report.unverifiable
        }

        let generatedAt = DateFormatter.reportTimestamp.string(from: Date())
        let systemSections = rows.map(systemSectionHTML).joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>ROMForge Collection Report</title>
        <style>
        body { font-family: -apple-system, Helvetica, Arial, sans-serif; color: #1a1a1a; margin: 40px; }
        h1 { font-size: 22px; margin-bottom: 4px; }
        .subtitle { color: #666; margin-bottom: 24px; }
        h2 { font-size: 16px; border-bottom: 1px solid #ccc; padding-bottom: 4px; margin-top: 32px; }
        table { border-collapse: collapse; width: 100%; margin-top: 8px; }
        th, td { text-align: left; padding: 4px 10px; border-bottom: 1px solid #eee; font-size: 13px; }
        th { color: #666; font-weight: 600; }
        .totals td, .totals th { font-size: 14px; }
        .meta { color: #666; font-size: 12px; margin-top: 2px; }
        .not-scanned { color: #999; font-style: italic; margin-top: 8px; }
        @media print {
            body { margin: 0.5in; }
            h2 { page-break-after: avoid; }
        }
        </style>
        </head>
        <body>
        <h1>ROMForge Collection Report</h1>
        <div class="subtitle">Generated \(generatedAt) — \(systems.count) system\(systems.count == 1 ? "" : "s") configured, \(scannedRows.count) scanned</div>

        <h2>Totals across every scanned system</h2>
        <table class="totals">
        <tr><th>Correct</th><th>Incorrect</th><th>Bad dump</th><th>Missing</th><th>Surplus</th><th>Unverifiable</th></tr>
        <tr><td>\(totals.correct)</td><td>\(totals.incorrect)</td><td>\(totals.badDump)</td><td>\(totals.missing)</td><td>\(totals.surplus)</td><td>\(totals.unverifiable)</td></tr>
        </table>

        \(systemSections)
        </body>
        </html>
        """
    }

    private static func systemSectionHTML(_ row: (system: RomSystem, report: AuditReport?, datName: String?, scannedAt: Date?)) -> String {
        let title = "\(htmlEscape(row.system.name))\(row.system.category.isEmpty ? "" : " <span class=\"meta\">(\(htmlEscape(row.system.category)))</span>")"
        guard let report = row.report else {
            return """
            <h2>\(title)</h2>
            <div class="not-scanned">Not scanned yet.</div>
            """
        }
        let scannedAtText = row.scannedAt.map { DateFormatter.reportTimestamp.string(from: $0) } ?? "unknown date"
        let datText = row.datName.map { " — DAT: \(htmlEscape($0))" } ?? ""
        return """
        <h2>\(title)</h2>
        <div class="meta">Last scanned \(scannedAtText)\(datText)</div>
        <table>
        <tr><th>Correct</th><th>Incorrect</th><th>Bad dump</th><th>Missing</th><th>Surplus</th><th>Unverifiable</th></tr>
        <tr><td>\(report.correct)</td><td>\(report.incorrect)</td><td>\(report.badDump)</td><td>\(report.missing)</td><td>\(report.surplus)</td><td>\(report.unverifiable)</td></tr>
        </table>
        """
    }

    private static func htmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private extension DateFormatter {
    static let reportTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
