// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import ROMForgeCore

guard CommandLine.arguments.count > 1 else {
    print("usage: romforge-cli <path-to-dat.xml> [split|merged|nonmerged] [bios:split|bios:merged|bios:nonmerged]")
    exit(1)
}

let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path)
func parseMode(_ raw: String?) -> SetMergeMode {
    switch raw {
    case "merged": return .merged
    case "nonmerged": return .nonMerged
    default: return .split
    }
}
let mergeMode = parseMode(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil)
let biosMergeMode = parseMode((CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "").replacingOccurrences(of: "bios:", with: ""))

do {
    // Auto-detects Logiqx/ClrMamePro XML, MAME -listxml, or a MAME software
    // list — the same three-dialect fallback chain the app uses.
    let start = Date()
    let dat = try DATLoader.load(contentsOf: url, mergeMode: mergeMode, biosMergeMode: biosMergeMode)
    print("\(dat.header.name) — \(dat.header.description) (v\(dat.header.version))")
    print("\(dat.games.count) games, loaded in \(Date().timeIntervalSince(start))s")
} catch {
    print("error: \(error)")
    exit(1)
}
