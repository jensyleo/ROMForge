// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import Foundation

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
    case nestopia
    case fceux
    case custom

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nestopia: return "Nestopia"
        case .fceux: return "FCEUX"
        case .custom: return "Custom…"
        }
    }

    /// The Homebrew command that installs it — shown directly in Settings
    /// so there's never a guessing game about how to get each option.
    /// Both confirmed real and currently installable (2026-09-29): OpenEmu
    /// was considered too (probably the most POPULAR multi-system option)
    /// but its own Homebrew cask is currently disabled upstream
    /// ("fails_gatekeeper_check", also `requires_rosetta`) — genuinely not
    /// installable via `brew` right now, so it's deliberately left off
    /// this list rather than offered as a choice that would just fail.
    var installCommand: String? {
        switch self {
        case .nestopia: return "brew install --cask nestopia"
        case .fceux: return "brew install fceux"
        case .custom: return nil
        }
    }

    /// `true` for a Homebrew **cask** (a `.app` bundle, opened via
    /// `NSWorkspace` by bundle identifier) vs. a **formula** (a plain CLI
    /// binary, run directly via `Process` — the same mechanism
    /// `MAMELauncher` already uses for MAME's own formula). Determines
    /// which half of `ConsoleEmulatorLauncher.launch` actually runs.
    ///
    /// `.custom` has no fixed answer — the user can point "Locate…" at
    /// either kind (`SystemSettingsView.locateCustomEmulator()`'s own doc
    /// comment) — so `ConsoleEmulatorSettings` decides that ONE case for
    /// itself, from the actual path's own `.app` extension, rather than
    /// this static property.
    var isAppBundle: Bool {
        switch self {
        case .nestopia: return true
        case .fceux, .custom: return false
        }
    }

    /// Nestopia's own bundle identifier — confirmed live (2026-09-29) via
    /// `mdls -name kMDItemCFBundleIdentifier` against a real `brew install
    /// --cask nestopia`. The capital "N" matters: bundle-id lookup is
    /// exact-match, and an initial guess inferred from the cask's own
    /// `zap` stanza (lowercase `nestopia`) turned out wrong once actually
    /// tested against the real installed app — `nil` for anything not
    /// resolved by bundle id.
    var bundleIdentifier: String? {
        switch self {
        case .nestopia: return "com.bannister.Nestopia"
        case .fceux, .custom: return nil
        }
    }

    /// The conventional Homebrew formula install location on Apple
    /// Silicon — same reasoning as `MAMELaunchSettings.homebrewDefaultPath`.
    /// `nil` for anything not resolved by a fixed path.
    var homebrewDefaultPath: String? {
        switch self {
        case .fceux: return "/opt/homebrew/bin/fceux"
        case .nestopia, .custom: return nil
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
    static let defaultEmulator: KnownConsoleEmulator = .nestopia

    static var selected: KnownConsoleEmulator {
        get {
            UserDefaults.standard.string(forKey: selectedEmulatorKey).flatMap(KnownConsoleEmulator.init(rawValue:)) ?? defaultEmulator
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: selectedEmulatorKey)
        }
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

    private static var resolvedIsAppBundle: Bool {
        selected == .custom ? customPathIsAppBundle : selected.isAppBundle
    }

    /// The resolved location to actually launch — an app bundle's own
    /// `URL` (found by bundle id, or the custom `.app` path itself) when
    /// `resolvedIsAppBundle` is `true`, `nil` otherwise. Re-resolved on
    /// every call, never cached — same "verified against the real file
    /// system, never assumed" reasoning `MAMELaunchSettings.executablePath`
    /// uses, so an uninstall/reinstall is picked up immediately.
    static var resolvedAppURL: URL? {
        guard resolvedIsAppBundle else { return nil }
        if selected == .custom {
            let path = customExecutablePath
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
        guard let bundleIdentifier = selected.bundleIdentifier else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    /// The resolved plain executable path — set only when
    /// `resolvedIsAppBundle` is `false`.
    static var resolvedExecutablePath: String? {
        guard !resolvedIsAppBundle else { return nil }
        if selected == .custom {
            let path = customExecutablePath
            return path.isEmpty ? nil : path
        }
        return selected.homebrewDefaultPath
    }

    /// `true` only when the CONFIGURED emulator is genuinely installed
    /// right now — jensyleo's own request (2026-09-29): "Play in
    /// <emulator>" should only ever appear when that emulator is actually
    /// installed, never just because some setting happens to be
    /// non-empty. Same reasoning as `MAMELaunchSettings.isInstalled`'s own
    /// doc comment.
    static var isInstalled: Bool {
        if resolvedIsAppBundle {
            return resolvedAppURL != nil
        }
        guard let path = resolvedExecutablePath else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
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

        var description: String {
            switch self {
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
    static func launch(romFileURL: URL, onFailure: @escaping @Sendable (String) -> Void) throws {
        let emulator = ConsoleEmulatorSettings.selected
        // Checks the ACTUAL resolved kind (`ConsoleEmulatorSettings`'s own
        // `resolvedIsAppBundle`, via which resolved property comes back
        // non-nil), not `emulator.isAppBundle` — for `.custom` that static
        // property has no real answer at all (`SystemSettingsView
        // .locateCustomEmulator()`'s own doc comment: either kind of path
        // is accepted there).
        if let appURL = ConsoleEmulatorSettings.resolvedAppURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = false
            NSWorkspace.shared.open([romFileURL], withApplicationAt: appURL, configuration: configuration) { _, error in
                guard let error else { return }
                onFailure(error.localizedDescription)
            }
            return
        }
        guard let executablePath = ConsoleEmulatorSettings.resolvedExecutablePath,
              FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw LaunchError.notInstalled(emulator: emulator)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [romFileURL.path]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        let stderrData = SendableBox(Data())
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrData.value.append(handle.availableData)
        }
        process.terminationHandler = { finished in
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            guard finished.terminationStatus != 0 else { return }
            let message = String(data: stderrData.value, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            onFailure(message?.isEmpty == false ? message! : "\(emulator.displayName) exited with status \(finished.terminationStatus) and no further output.")
        }
        try process.run()
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
