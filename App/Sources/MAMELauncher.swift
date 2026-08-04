// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import Foundation

/// The `@AppStorage` key `SystemSettingsView`'s MAME executable path field
/// uses, mirrored here as a plain string constant so `LibraryDetailView`
/// (not a place that otherwise touches Settings state) can read the same
/// `UserDefaults` value without importing SwiftUI's property wrapper for
/// it — the same pattern `HashAlgorithmSettings` already uses.
enum MAMELaunchSettings {
    static let executablePathKey = "ROMForge.mame.executablePath"

    /// The conventional Homebrew install location on Apple Silicon —
    /// jensyleo's own call (2026-07-30): this is where a `brew install
    /// mame` puts the real executable on every current Mac, so the
    /// Settings field's own "Default" button can offer it directly
    /// instead of making every user locate it by hand via a file panel.
    static let homebrewDefaultPath = "/opt/homebrew/bin/mame"

    /// `nil` when nothing's configured yet — the feature (context menu
    /// item, "Play" toolbar button) stays hidden/disabled rather than
    /// offered with nothing to actually launch.
    static var executablePath: String? {
        let path = UserDefaults.standard.string(forKey: executablePathKey) ?? ""
        return path.isEmpty ? nil : path
    }
}

/// Launches a MAME machine directly — "does this actually run/boot in the
/// real emulator", the one thing ROMForge's own audit (hash-correctness)
/// can't answer on its own. Deliberately MAME-only for now (not a generic
/// "launch in any emulator" feature) and entirely opt-in: nothing here
/// runs unless a real `mame` executable has been located in Settings.
enum MAMELauncher {
    enum LaunchError: Error, CustomStringConvertible {
        case notConfigured
        case executableNotFound(String)

        var description: String {
            switch self {
            case .notConfigured:
                return "No MAME executable configured — set one in Settings → Systems first."
            case .executableNotFound(let path):
                return "The configured MAME executable no longer exists at \(path)."
            }
        }
    }

    /// Launches `machineName` (the DAT's own internal name, e.g. "pacman"
    /// — never its human-readable description) with every one of the
    /// system's configured ROM folders on MAME's own `-rompath`
    /// (semicolon-separated, MAME's own convention for searching more than
    /// one location) — regardless of merge mode, since MAME itself already
    /// knows how to resolve parent/clone/BIOS archives across whichever
    /// folders it's given. MAME still runs as its own independent process
    /// and window — this doesn't wait for it to quit — but its stderr is
    /// captured and, if it exits with a non-zero status (jensyleo's own
    /// report: a bad/non-working driver quits back to ROMForge immediately
    /// with no visible explanation), handed to `onFailure` so the caller
    /// can actually show the user *why* — MAME's own stderr always names
    /// the real reason (bad dump, unemulated protection, etc.), it just
    /// otherwise vanishes together with the process. A clean exit (the
    /// user closing MAME normally) never calls `onFailure` at all.
    static func launch(machineName: String, romFolders: [URL], onFailure: @escaping @Sendable (String) -> Void) throws {
        guard let executablePath = MAMELaunchSettings.executablePath else {
            throw LaunchError.notConfigured
        }
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw LaunchError.executableNotFound(executablePath)
        }
        let rompath = romFolders.map(\.path).joined(separator: ";")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [machineName, "-rompath", rompath]
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
            onFailure(message?.isEmpty == false ? message! : "MAME exited with status \(finished.terminationStatus) and no further output.")
        }
        try process.run()
    }

    /// A tiny mutable box to accumulate `stderrPipe`'s bytes across the
    /// readability handler's repeated callbacks — `Data` itself isn't a
    /// problem to mutate, but capturing a plain `var` across two separate
    /// `@Sendable` closures (the readability handler and the termination
    /// handler) needs an explicit reference type for Swift's concurrency
    /// checker to allow the shared mutation.
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
