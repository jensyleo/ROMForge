// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Generates a "fixdat" — a normal Logiqx-shaped DAT containing only the
/// entries an audit found missing or incorrect (misnamed/wrong hash),
/// mirroring what ClrMamePro calls "Fix-DatFiles". Handing this to another
/// DAT-aware tool, or matching it against another source collection, finds
/// exactly the gap and nothing else.
///
/// There is no special fixdat header marker to reproduce — ClrMamePro's own
/// docs describe a fixdat as just a DAT holding fewer entries, so this
/// reuses the same `<datafile>/<game>/<rom>` shape `LogiqxDATParser` already
/// reads back (round-tripped by `FixDatExporterTests`).
public enum FixDatExporter {
    public static func generate(from report: AuditReport, datName: String) -> String {
        var gameOrder: [String] = []
        var entriesByGame: [String: [AuditEntry]] = [:]

        for entry in report.entries {
            guard entry.status == .missing || entry.status == .incorrect else { continue }
            guard let game = entry.game else { continue }
            if entriesByGame[game] == nil {
                gameOrder.append(game)
            }
            entriesByGame[game, default: []].append(entry)
        }

        var xml = """
        <?xml version="1.0"?>
        <datafile>
        \t<header>
        \t\t<name>fixDat_\(xmlEscape(datName))</name>
        \t\t<description>Missing/incorrect entries from \(xmlEscape(datName))</description>
        \t\t<version>1.0</version>
        \t</header>

        """

        for game in gameOrder {
            xml += "\t<game name=\"\(xmlEscape(game))\">\n"
            xml += "\t\t<description>\(xmlEscape(game))</description>\n"
            for entry in entriesByGame[game] ?? [] {
                xml += "\t\t<rom name=\"\(xmlEscape(entry.name))\""
                if let size = entry.expectedSize {
                    xml += " size=\"\(size)\""
                }
                if let crc = entry.expectedCRC {
                    xml += " crc=\"\(crc)\""
                }
                if let md5 = entry.expectedMD5 {
                    xml += " md5=\"\(md5)\""
                }
                if let sha1 = entry.expectedSHA1 {
                    xml += " sha1=\"\(sha1)\""
                }
                xml += "/>\n"
            }
            xml += "\t</game>\n"
        }

        xml += "</datafile>\n"
        return xml
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
