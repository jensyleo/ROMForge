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

// `switch-dat <rom folder> <titledb folder> <output.dat> [depth]`: builds the
// Switch DAT the app's own "Generate from TitleDB" action builds.
if CommandLine.arguments[1] == "switch-dat" {
    guard CommandLine.arguments.count >= 5 else {
        print("usage: romforge-cli switch-dat <rom folder> <titledb folder> <output.dat> [depth]")
        exit(1)
    }
    let titleDBFolder = URL(fileURLWithPath: CommandLine.arguments[3])
    do {
        let titleDB = try SwitchTitleDB(
            namesJSON: Data(contentsOf: titleDBFolder.appendingPathComponent("US.en.json")),
            versionsText: String(contentsOf: titleDBFolder.appendingPathComponent("versions.txt"), encoding: .utf8)
        )
        let depth = CommandLine.arguments.count > 5 ? Int(CommandLine.arguments[5]) ?? 2 : 2
        let files = SwitchCollectionScanner.files(in: [URL(fileURLWithPath: CommandLine.arguments[2])], maxDepth: depth)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let result = SwitchDATGenerator.generate(files: files, titleDB: titleDB, version: formatter.string(from: Date()))
        try SwitchDATGenerator.xml(for: result.dat).write(toFile: CommandLine.arguments[4], atomically: true, encoding: .utf8)
        print("\(files.count) files, \(result.dat.games.count) games, \(result.availableUpdates.count) with a newer update, \(result.unidentifiedFiles.count) unidentified")
        result.unidentifiedFiles.forEach { print("  unidentified: \($0)") }
        exit(0)
    } catch {
        print("error: \(error)")
        exit(1)
    }
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
