// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// XXE hardening shared by every DAT `XMLParser` (Logiqx, MAME `-listxml`,
/// MAME Software List) — never fetch/resolve an external DTD or entity a
/// malicious/corrupt DAT might declare. Found duplicated verbatim across
/// all three parsers (same three lines, same comment) during a 2026-08-18
/// code audit; centralized here so a future hardening change only needs
/// applying once.
enum XMLParserHardening {
    static func harden(_ parser: XMLParser) {
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.externalEntityResolvingPolicy = .never
    }
}
