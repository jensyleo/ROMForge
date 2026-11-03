// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import Foundation
import ROMForgeCore

/// "Play in <emulator>" for a console/computer system — the counterpart to
/// `MAMELauncher`/`MAMELaunchSettings`, but configurable, unlike MAME.
/// jensyleo's own request (2026-09-29): "en el caso de NES y otros sistemas
/// donde el emulador no es único como en el caso de MAME hay que dejar
/// dinámica la elección del emulador para el usuario... coloques los más
/// utilizados en una lista." MAME genuinely has one canonical emulator;
/// a console system doesn't, so this is a real choice, not a hardcoded one.
///
/// `.custom` is his own explicit escape hatch for whoever wants an
/// emulator not on this list at all.
public enum KnownConsoleEmulator: String, CaseIterable, Identifiable, Sendable {
    case retroarch
    case custom

    public var id: String { rawValue }

    /// Emulators that can run a given `RomSystem.category`: RetroArch (one frontend
    /// with a libretro core per platform) for every platform with a known core, and
    /// `.custom` for any other emulator — from Homebrew or installed by hand.
    static func options(forCategory category: String) -> [KnownConsoleEmulator] {
        guard SystemCategoryKind(rawValue: category)?.canPlay ?? true else { return [] }
        return (RetroArchCores.defaultCore(forCategory: category) != nil ? [.retroarch] : []) + [.custom]
    }

    var displayName: String {
        switch self {
        case .retroarch: return "RetroArch"
        case .custom: return "Custom…"
        }
    }

    /// How to get it, shown in Settings. `retroarch` (no suffix) is the Intel build.
    var installCommand: String? {
        switch self {
        case .retroarch: return "brew install --cask retroarch-metal"
        case .custom: return nil
        }
    }

    /// RetroArch's own binary is launched as a process with `-L <core> <rom>`;
    /// it opens zip/7z content itself.
    var opensZipDirectly: Bool { self == .retroarch }

    /// `true` for a `.app` opened via `NSWorkspace`; RetroArch runs as a process, and
    /// `.custom` is decided from the chosen path's own extension.
    var isAppBundle: Bool { false }

    var homebrewDefaultPath: String? {
        switch self {
        case .retroarch: return RetroArchCores.executablePath
        case .custom: return nil
        }
    }
}

/// Which emulator is configured for every console/computer system, and
/// where to find it. One shared choice, not per-system — same reasoning
/// `MaintenanceFolderSettingsSection`'s own doc comment gives for the
/// Maintenance root being shared: a console system's own emulator isn't a
/// per-DAT concern any more than MAME's own executable path is.
enum ConsoleEmulatorSettings {
    static let selectedEmulatorKey = "ROMForge.consoleEmulator.selected"
    static let customExecutablePathKey = "ROMForge.consoleEmulator.customPath"

    /// The pre-per-system global choice — only a migration fallback for a
    /// system that never got its own `emulatorRaw`.
    private static var legacyGlobalChoice: KnownConsoleEmulator? {
        UserDefaults.standard.string(forKey: selectedEmulatorKey).flatMap(KnownConsoleEmulator.init(rawValue:))
    }

    /// The emulator `system` plays with: its own saved choice if it is
    /// valid for the platform, else the old global choice if valid, else the
    /// platform's first option (NES → Nestopia, SNES → Snes9x, others →
    /// Custom).
    static func emulator(for system: RomSystem) -> KnownConsoleEmulator {
        let options = KnownConsoleEmulator.options(forCategory: system.category)
        if let raw = system.emulatorRaw, let own = KnownConsoleEmulator(rawValue: raw), options.contains(own) { return own }
        if let legacy = legacyGlobalChoice, options.contains(legacy) { return legacy }
        return options.first ?? .custom
    }

    /// Only meaningful when `selected == .custom` — a user-picked `.app`
    /// bundle or plain executable, same "Locate…" pattern
    /// `MAMELaunchSettings` already uses.
    static var customExecutablePath: String {
        get { UserDefaults.standard.string(forKey: customExecutablePathKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: customExecutablePathKey) }
    }

    /// `true` when the configured choice should launch via `NSWorkspace`
    /// (a real `.app` bundle) rather than `Process` (a plain CLI binary) —
    /// `KnownConsoleEmulator.isAppBundle` for Nestopia/FCEUX, but decided
    /// from the ACTUAL picked path's own extension for `.custom`, since
    /// `locateCustomEmulator()` accepts either kind.
    static var customPathIsAppBundle: Bool {
        customExecutablePath.lowercased().hasSuffix(".app")
    }

    /// The custom emulator for `system`: its own path, else the older shared one.
    static func customPath(for system: RomSystem) -> String {
        if let own = system.customEmulatorPath, !own.isEmpty { return own }
        return customExecutablePath
    }

    private static func resolvedIsAppBundle(_ emulator: KnownConsoleEmulator, customPath: String?) -> Bool {
        emulator == .custom ? (customPath ?? customExecutablePath).lowercased().hasSuffix(".app") : emulator.isAppBundle
    }

    /// The resolved location to actually launch — an app bundle's own
    /// `URL` (found by bundle id, or the custom `.app` path itself) when
    /// `resolvedIsAppBundle` is `true`, `nil` otherwise. Re-resolved on
    /// every call, never cached — same "verified against the real file
    /// system, never assumed" reasoning `MAMELaunchSettings.executablePath`
    /// uses, so an uninstall/reinstall is picked up immediately.
    static func resolvedAppURL(for emulator: KnownConsoleEmulator, customPath: String? = nil) -> URL? {
        guard resolvedIsAppBundle(emulator, customPath: customPath) else { return nil }
        if emulator == .custom {
            let path = customPath ?? customExecutablePath
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
        return nil
    }

    /// The resolved plain executable path — set only when
    /// `resolvedIsAppBundle` is `false`.
    static func resolvedExecutablePath(for emulator: KnownConsoleEmulator, customPath: String? = nil) -> String? {
        guard !resolvedIsAppBundle(emulator, customPath: customPath) else { return nil }
        if emulator == .custom {
            let path = customPath ?? customExecutablePath
            return path.isEmpty ? nil : path
        }
        return emulator.homebrewDefaultPath
    }

    /// `true` only when the CONFIGURED emulator is genuinely installed
    /// right now — jensyleo's own request (2026-09-29): "Play in
    /// <emulator>" should only ever appear when that emulator is actually
    /// installed, never just because some setting happens to be
    /// non-empty. Same reasoning as `MAMELaunchSettings.isInstalled`'s own
    /// doc comment.
    static func isInstalled(_ emulator: KnownConsoleEmulator, customPath: String? = nil) -> Bool {
        if resolvedIsAppBundle(emulator, customPath: customPath) {
            return resolvedAppURL(for: emulator, customPath: customPath) != nil
        }
        guard let path = resolvedExecutablePath(for: emulator, customPath: customPath) else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// `isInstalled` for the emulator `system` is set to, with its own custom path.
    static func isInstalled(for system: RomSystem) -> Bool {
        let chosen = emulator(for: system)
        return isInstalled(chosen, customPath: chosen == .custom ? customPath(for: system) : nil)
    }
}

/// Launches a NES (or other console-system) rom file directly in whichever
/// emulator `ConsoleEmulatorSettings.selected` names — the console-system
/// counterpart to `MAMELauncher.launch`. A console game is always exactly
/// one file (no MAME-style multi-file romset/`-rompath` search across
/// several folders needed), so this only ever needs the one matched
/// file's own URL, unlike MAME's `machineName` + `romFolders`.
enum ConsoleEmulatorLauncher {
    enum LaunchError: Error, CustomStringConvertible {
        case notInstalled(emulator: KnownConsoleEmulator)
        case romNotFound(path: String)
        case extractionFailed(String)
        case coreMissing(core: String)
        case encryptedROM
        case unflaggedDecryptedROM

        var description: String {
            switch self {
            case .romNotFound(let path):
                return "The ROM file isn't reachable (\(path)) — if it lives on a network volume, make sure the volume is mounted."
            case .extractionFailed(let reason):
                return "Couldn't extract the zipped ROM to play it: \(reason)"
            case .unflaggedDecryptedROM:
                return "Not playable — Reason: this 3DS dump is decrypted, but its header doesn't carry the decrypted flag, and RetroArch's Azahar core trusts that flag and rejects it."
            case .encryptedROM:
                return "Not playable — Reason: this 3DS dump is Encrypted, and RetroArch's Azahar core only loads Decrypted dumps."
            case .coreMissing(let core):
                return "RetroArch needs the \"\(core)\" core for this platform. Install it from RetroArch's own Online Updater → Core Downloader (or pick another installed core in Settings → Systems → Consoles)."
            case .notInstalled(let emulator):
                if let installCommand = emulator.installCommand {
                    return "\(emulator.displayName) isn't installed — run `\(installCommand)`, then try again."
                }
                return "No custom emulator configured — locate one in Settings → Systems → Consoles first."
            }
        }
    }

    /// For an app bundle (Nestopia, or a custom `.app`): opens `romFileURL`
    /// via `NSWorkspace`, exactly like double-clicking the file in Finder
    /// and choosing that app — it runs as its own independent process and
    /// window, same as `MAMELauncher.launch`'s own MAME process. A GUI app
    /// opened this way gives no equivalent "why did this fail to actually
    /// run the game" signal beyond "the OS failed to launch the app at
    /// all" (`onFailure` only ever fires for that outer case).
    ///
    /// For a plain executable (FCEUX, or a custom CLI binary): runs it
    /// directly via `Process` with the rom file as its sole argument,
    /// capturing stderr — same mechanism, and same real-failure-reason
    /// reporting, as `MAMELauncher.launch`'s own MAME process.
    /// The core's own explanation (`SET_MESSAGE` lines) plus RetroArch's
    /// `[ERROR]` lines, instead of the whole verbose log.
    static func retroArchFailureSummary(_ output: String) -> String {
        var lines: [String] = []
        for line in output.split(separator: "\n") {
            var text = String(line)
            if let range = text.range(of: "SET_MESSAGE: ") { text = String(text[range.upperBound...]) }
            else if !text.hasPrefix("[ERROR]") { continue }
            if !lines.contains(text) { lines.append(text) }
        }
        return lines.joined(separator: "\n")
    }

    static func launch(romFileURL requestedURL: URL, emulator: KnownConsoleEmulator, system: RomSystem, onFailure: @escaping @Sendable (String) -> Void) throws {
        let customPath: String? = emulator == .custom ? ConsoleEmulatorSettings.customPath(for: system) : nil
        guard FileManager.default.fileExists(atPath: requestedURL.path) else {
            throw LaunchError.romNotFound(path: requestedURL.path)
        }
        let romFileURL = try playableURL(for: requestedURL, emulator: emulator)
        if emulator == .retroarch, system.category == "3DS", let state = (romFileURL.pathExtension.lowercased() == "zip"
                ? NintendoCTRHeader.readFirstCartridge(inZip: romFileURL) : NintendoCTRHeader.read(url: romFileURL))?.state {
            if state == .encrypted { throw LaunchError.encryptedROM }
            if state == .decryptedFlagMissing { throw LaunchError.unflaggedDecryptedROM }
        }
        // Checks the ACTUAL resolved kind (`ConsoleEmulatorSettings`'s own
        // `resolvedIsAppBundle`, via which resolved property comes back
        // non-nil), not `emulator.isAppBundle` — for `.custom` that static
        // property has no real answer at all (`SystemSettingsView
        // .locateCustomEmulator()`'s own doc comment: either kind of path
        // is accepted there).
        if let appURL = ConsoleEmulatorSettings.resolvedAppURL(for: emulator, customPath: customPath) {
            // Real bug found live (2026-10-04, Snes9x): a ROM handed to an
            // app that is NOT running yet is lost — the window opens empty
            // (even `open -a` does it); the same call works once the app
            // is already running. So launch the app first, wait until it
            // has finished launching, and only then open the ROM.
            DispatchQueue.global(qos: .userInitiated).async {
                let alreadyRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == appURL.standardizedFileURL }
                if !alreadyRunning {
                    let launched = DispatchSemaphore(value: 0)
                    NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                        if let error { onFailure(error.localizedDescription) }
                        launched.signal()
                    }
                    _ = launched.wait(timeout: .now() + 10)
                    let deadline = Date().addingTimeInterval(10)
                    while Date() < deadline {
                        let app = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == appURL.standardizedFileURL }
                        if app?.isFinishedLaunching == true { break }
                        Thread.sleep(forTimeInterval: 0.2)
                    }
                    Thread.sleep(forTimeInterval: 1.0)
                }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = false
                NSWorkspace.shared.open([romFileURL], withApplicationAt: appURL, configuration: configuration) { _, error in
                    guard let error else { return }
                    onFailure(error.localizedDescription)
                }
            }
            return
        }
        guard let executablePath = ConsoleEmulatorSettings.resolvedExecutablePath(for: emulator, customPath: customPath),
              FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw LaunchError.notInstalled(emulator: emulator)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        if emulator == .retroarch {
            guard let core = RetroArchCores.core(for: system) else { throw LaunchError.coreMissing(core: system.category) }
            guard RetroArchCores.isInstalled(core) else { throw LaunchError.coreMissing(core: core) }
            // --verbose makes the core's own messages (e.g. "ROM is encrypted") reach
            // stderr, so a failed launch can say why instead of just "failed".
            process.arguments = ["--verbose", "-L", RetroArchCores.coreURL(core).path, romFileURL.path]
        } else if emulator == .custom {
            process.arguments = ArgumentTemplate.expand(system.customEmulatorArguments, rom: romFileURL.path)
        } else {
            process.arguments = [romFileURL.path]
        }
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        let stderrData = SendableBox(Data())
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            // Verbose output of a long session must not grow without bound.
            if stderrData.value.count < 262_144 { stderrData.value.append(data) }
        }
        process.terminationHandler = { finished in
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            guard finished.terminationStatus != 0 else { return }
            let output = String(data: stderrData.value, encoding: .utf8) ?? ""
            // RetroArch can exit non-zero after a perfectly good session (quitting a
            // running core, a late shutdown error). Only a game that never started is a failure.
            if emulator == .retroarch,
               !output.contains("Failed to load content"), !output.contains("Failed to open libretro core") { return }
            let message = emulator == .retroarch ? retroArchFailureSummary(output) : output.trimmingCharacters(in: .whitespacesAndNewlines)
            onFailure(!message.isEmpty ? message : "\(emulator.displayName) exited with status \(finished.terminationStatus) and no further output.")
        }
        try process.run()
    }

    /// A `.zip` ROM for an emulator that can't open zips: extracts it into a
    /// per-ROM temporary folder (reused on later launches) and returns the
    /// largest extracted file. Anything else is returned unchanged.
    private static func playableURL(for url: URL, emulator: KnownConsoleEmulator) throws -> URL {
        guard url.pathExtension.lowercased() == "zip", !emulator.opensZipDirectly else { return url }
        let folderName = "\(url.deletingPathExtension().lastPathComponent)-\(abs(url.path.hashValue))"
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("ROMForge-Play", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        // Refuse a zip that would expand to an unreasonable size (zip bomb),
        // and sweep extractions left from earlier launches.
        try checkExpandedSize(of: url)
        pruneOldExtractions(in: destination.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", "-j", "-q", url.path, "-d", destination.path]
        let errorPipe = Pipe()
        unzip.standardError = errorPipe
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unzip exited with status \(unzip.terminationStatus)"
            throw LaunchError.extractionFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        func size(_ file: URL) -> Int { (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        guard let largest = files.max(by: { size($0) < size($1) }) else { throw LaunchError.extractionFailed("the archive is empty") }
        return largest
    }

    private static let maxExtractedBytes: Int64 = 1 << 30

    /// Total uncompressed size of `zip` per `unzip -Zt` ("N files, X bytes
    /// uncompressed, …"); throws when it exceeds 1 GiB.
    private static func checkExpandedSize(of zip: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Zt", zip.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard let match = output.range(of: #"(\d+) bytes uncompressed"#, options: .regularExpression),
              let bytes = Int64(output[match].split(separator: " ")[0]) else { return }
        if bytes > maxExtractedBytes {
            throw LaunchError.extractionFailed("the archive expands to \(bytes / 1_048_576) MB, more than the 1 GB limit")
        }
    }

    /// Deletes extraction folders older than a day.
    private static func pruneOldExtractions(in root: URL) {
        let fileManager = FileManager.default
        let cutoff = Date().addingTimeInterval(-86_400)
        for folder in (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
            if modified < cutoff { try? fileManager.removeItem(at: folder) }
        }
    }

    /// Same reasoning as `MAMELauncher`'s own identical private type —
    /// duplicated rather than shared across files since neither is meant
    /// to be exposed beyond its own launcher.
    private final class SendableBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Data
        init(_ value: Data) { _value = value }
        var value: Data {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }
}


/// RetroArch's per-platform libretro cores. One frontend plays every console;
/// the core is what emulates the platform. Defaults are the widely used,
/// maintained cores that exist for Apple Silicon on libretro's own build server.
enum RetroArchCores {
    /// RetroArch's executable, from Homebrew's cask or a hand-installed copy
    /// in /Applications or ~/Applications.
    static var executablePath: String {
        let candidates = ["/Applications/RetroArch.app/Contents/MacOS/RetroArch",
                          NSHomeDirectory() + "/Applications/RetroArch.app/Contents/MacOS/RetroArch"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
    }

    /// Where the Homebrew/`.dmg` RetroArch keeps its cores.
    static var coresDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/RetroArch/cores", isDirectory: true)
    }

    /// Core name without the `_libretro.dylib` suffix, per `RomSystem.category`.
    static func defaultCore(forCategory category: String) -> String? {
        switch category {
        case "NES", "Famicom Disk System": return "fceumm"
        case "SNES", "SNES-MSU1": return "snes9x"
        case "N64": return "mupen64plus_next"
        case "Game Boy", "Game Boy Color": return "gambatte"
        case "GBA": return "mgba"
        case "NDS": return "melonds"
        case "DSi": return "melondsds"
        case "3DS": return "azahar"
        case "Wii U": return "cemu"
        case "Virtual Boy": return "mednafen_vb"
        case "Pokemon Mini": return "pokemini"
        case "Atari 2600": return "stella"
        case "Atari 5200": return "a5200"
        case "Atari 7800": return "prosystem"
        case "Atari Jaguar": return "virtualjaguar"
        case "Atari Lynx": return "handy"
        case "Atari ST": return "hatari"
        case "Atari 8-bit": return "atari800"
        case "PC Engine": return "mednafen_pce_fast"
        case "PC Engine CD": return "mednafen_pce"
        case "SuperGrafx": return "mednafen_supergrafx"
        case "PC-FX": return "mednafen_pcfx"
        case "PC-98": return "np2kai"
        case "Neo Geo Pocket": return "mednafen_ngp"
        case "Neo Geo Pocket Color": return "mednafen_ngp"
        case "Neo Geo CD": return "neocd"
        case "WonderSwan": return "mednafen_wswan"
        case "WonderSwan Color": return "mednafen_wswan"
        case "ColecoVision": return "gearcoleco"
        case "Intellivision": return "freeintv"
        case "Vectrex": return "vecx"
        case "Magnavox Odyssey 2": return "o2em"
        case "Fairchild Channel F": return "freechaf"
        case "Watara Supervision": return "potator"
        case "Mega Duck": return "sameduck"
        case "Game & Watch": return "gw"
        case "Epoch Super Cassette Vision": return "emuscv"
        case "3DO": return "opera"
        case "Philips CD-i": return "same_cdi"
        case "Commodore 64": return "vice_x64"
        case "Commodore Amiga": return "puae"
        case "Commodore VIC-20": return "vice_xvic"
        case "Commodore Plus/4": return "vice_xplus4"
        case "Commodore 128": return "vice_x128"
        case "Commodore PET": return "vice_xpet"
        case "ZX Spectrum": return "fuse"
        case "ZX81": return "81"
        case "Amstrad CPC": return "cap32"
        case "MSX": return "bluemsx"
        case "MSX2": return "bluemsx"
        case "Apple II": return "applewin"
        case "Apple Macintosh": return "minivmac"
        case "DOS": return "dosbox_pure"
        case "Sharp X68000": return "px68k"
        case "Sharp X1": return "x1"
        case "FM Towns": return "geartowns"
        case "Thomson MO/TO": return "theodore"
        case "ScummVM": return "scummvm"
        case "GameCube", "Wii": return "dolphin"
        case "SEGA SG-1000", "SEGA Master System", "SEGA Game Gear", "SEGA Genesis", "SEGA CD": return "genesis_plus_gx"
        case "SEGA 32X": return "picodrive"
        case "SEGA Saturn": return "mednafen_saturn"
        case "SEGA Dreamcast": return "flycast"
        case "Sony PlayStation": return "pcsx_rearmed"
        case "Sony PlayStation 2": return "pcsx2"
        case "Sony PSP": return "ppsspp"
        default: return nil
        }
    }

    static func coreURL(_ core: String) -> URL {
        coresDirectory.appendingPathComponent("\(core)_libretro.dylib")
    }

    static func isInstalled(_ core: String) -> Bool {
        FileManager.default.fileExists(atPath: coreURL(core).path)
    }

    /// The core `system` plays with: its own choice when that core is
    /// installed, else the platform's suggested one (installed or not).
    static func core(for system: RomSystem) -> String? {
        if let own = system.retroArchCore, !own.isEmpty, isInstalled(own) { return own }
        return defaultCore(forCategory: system.category)
    }

    /// Every core the user has installed, names without the suffix.
    static func installedCores() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: coresDirectory.path)) ?? []
        return names.filter { $0.hasSuffix("_libretro.dylib") }
            .map { String($0.dropLast("_libretro.dylib".count)) }
            .sorted()
    }
}

/// Splits a user-written argument template for a custom emulator ("-f {rom}")
/// into arguments, honouring double quotes; `{rom}` becomes the game file. An
/// empty template means just the game file.
enum ArgumentTemplate {
    static func expand(_ template: String?, rom: String) -> [String] {
        let text = (template ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [rom] }
        var arguments: [String] = []
        var current = ""
        var inQuotes = false
        var hasToken = false
        for character in text {
            if character == "\"" { inQuotes.toggle(); hasToken = true; continue }
            if character == " ", !inQuotes {
                if hasToken { arguments.append(current); current = ""; hasToken = false }
                continue
            }
            current.append(character)
            hasToken = true
        }
        if hasToken { arguments.append(current) }
        let expanded = arguments.map { $0.replacingOccurrences(of: "{rom}", with: rom) }
        return expanded.contains(where: { $0.contains(rom) }) ? expanded : expanded + [rom]
    }
}
