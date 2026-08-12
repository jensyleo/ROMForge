// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Runs the configured MAME executable's own `-listxml` and saves its
/// output as a DAT file — jensyleo's own request (2026-08-13): "hay que
/// agregar la opción de sacar el DAT del binario del MAME instalado", so a
/// user doesn't need to separately track down a matching `-listxml` dump
/// for whichever MAME version they actually have installed. The XML
/// `-listxml` prints is *exactly* the same format `MAMEListXMLParser`
/// already reads (this only ever generates a file, never parses one
/// itself) — the generated file plugs straight into `AddSystemSheet`'s
/// existing "Select DAT…" flow with no format-specific handling needed.
///
/// Shares `MAMELaunchSettings.executablePath` with `MAMELauncher` (the
/// "Play" feature) — one configured MAME executable, two independent uses
/// of it.
enum MAMEDATGenerator {
    enum GeneratorError: Error, CustomStringConvertible {
        case notConfigured
        case executableNotFound(String)
        case processFailed(String)

        var description: String {
            switch self {
            case .notConfigured:
                return "No MAME executable configured — set one in Settings → Systems first."
            case .executableNotFound(let path):
                return "The configured MAME executable no longer exists at \(path)."
            case .processFailed(let message):
                return "MAME's own `-listxml` failed: \(message)"
            }
        }
    }

    /// Where the generated DAT is written — one fixed location, overwritten
    /// on every generation (not a user-chosen destination): the file is a
    /// disposable derivative of whatever MAME happens to be configured
    /// right now, not something meant to be kept/versioned by hand.
    static func generatedDATURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ROMForge", isDirectory: true)
            .appendingPathComponent("mame-listxml.xml")
    }

    /// Runs `mame -listxml`, streaming its stdout straight to disk (a full
    /// MAME driver list is easily hundreds of MB of XML — buffering it all
    /// in memory first would be wasteful when it's going to a file anyway).
    /// `onProgress` reports a running byte count as stdout arrives — there's
    /// no known total ahead of time (MAME never announces one), so this is
    /// a live counter rather than a determinate percentage, same rationale
    /// as `LibraryViewModel.folderScanFilesFound`'s own doc comment.
    static func generate(onProgress: @escaping @Sendable (Int) -> Void) async throws -> URL {
        guard let executablePath = MAMELaunchSettings.executablePath else {
            throw GeneratorError.notConfigured
        }
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw GeneratorError.executableNotFound(executablePath)
        }
        let outputURL = generatedDATURL()
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["-listxml"]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        let stderrData = SendableBox(Data())
        let bytesWritten = SendableBox(0)

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputHandle.write(data)
            bytesWritten.value += data.count
            onProgress(bytesWritten.value)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrData.value.append(handle.availableData)
        }

        try process.run()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? outputHandle.close()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderrData.value, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GeneratorError.processFailed(message?.isEmpty == false ? message! : "exit status \(process.terminationStatus)")
        }
        return outputURL
    }

    /// Same rationale as `MAMELauncher`'s own private `SendableBox` — a
    /// small mutable box so two separate `@Sendable` closures (the stdout/
    /// stderr readability handlers) can safely accumulate into shared
    /// state under Swift's strict concurrency checking. Duplicated rather
    /// than shared with `MAMELauncher`'s: small enough that a shared
    /// utility type wasn't worth the cross-file coupling for.
    private final class SendableBox<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Value
        init(_ value: Value) { _value = value }
        var value: Value {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }
}
