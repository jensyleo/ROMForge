// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Runs the 7-Zip executable and captures its output. Stderr is drained on a
/// background queue while stdout is read on the calling thread, so a large
/// listing or extraction can't deadlock on a full pipe buffer.
enum SevenZipRunner {
    /// Thrown by `run(_:arguments:maxOutputBytes:)` when a byte cap was
    /// given and stdout exceeded it — deliberately a distinct type from
    /// `SevenZipError`, since this file has no notion of "which archive
    /// entry" is being read (it only ever sees raw `argv`). The caller
    /// that supplied the cap (and does know the entry) is expected to
    /// catch this specifically and re-throw its own, better-contextualized
    /// error — see `SevenZipArchiveHasher`.
    struct OutputExceededLimit: Error {
        let limitBytes: Int
    }

    /// `maxOutputBytes` — see `OutputExceededLimit` and
    /// `SevenZipError.suspectedDecompressionBomb`'s own doc comments.
    /// `nil` (the default, used by the plain archive listing) preserves
    /// the original unbounded read; a decompression (`e -so`) call passes
    /// an explicit cap derived from the entry's own declared size.
    static func run(executableURL: URL, arguments: [String], maxOutputBytes: Int? = nil) throws -> Data {
        let result = try invoke(executableURL: executableURL, arguments: arguments, maxOutputBytes: maxOutputBytes)
        if let maxOutputBytes, result.outputExceededLimit {
            // The process was killed for over-producing — its exit code
            // and stderr reflect that abrupt termination, not the real
            // failure, so this takes priority over the generic exit-code
            // check below.
            throw OutputExceededLimit(limitBytes: maxOutputBytes)
        }
        guard result.exitCode == 0 else {
            let message = String(data: result.standardError, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SevenZipError.processFailed((message?.isEmpty == false ? message : nil) ?? "exit code \(result.exitCode)")
        }
        return result.standardOutput
    }

    /// Used only to probe a candidate binary's identity banner: 7-Zip prints
    /// its usage banner (and exits non-zero) when run with no arguments, so
    /// this ignores the exit code and combines both streams. Returns `nil`
    /// only if the binary could not be launched at all.
    static func captureOutputIgnoringExitCode(executableURL: URL, arguments: [String]) -> Data? {
        guard let result = try? invoke(executableURL: executableURL, arguments: arguments) else {
            return nil
        }
        return result.standardOutput + result.standardError
    }

    private static func invoke(
        executableURL: URL,
        arguments: [String],
        maxOutputBytes: Int? = nil
    ) throws -> (standardOutput: Data, standardError: Data, exitCode: Int32, outputExceededLimit: Bool) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // `SendableBox` instead of a plain captured `var` — Swift 6 strict
        // concurrency correctly flags a `var` mutated inside a `@Sendable`
        // `DispatchQueue.async` closure as a real data race on paper, even
        // though `errorDrain.wait()` below establishes a genuine
        // happens-before relationship before it's ever read. 2026-08-13
        // performance/cleanup pass — no behavior change, silences a real
        // compiler warning (fixed at the audit's own "Ciclo A" step).
        let errorDrain = DispatchGroup()
        let errorBox = SendableBox(Data())
        errorDrain.enter()
        DispatchQueue.global(qos: .utility).async {
            errorBox.value = errorPipe.fileHandleForReading.readDataToEndOfFile()
            errorDrain.leave()
        }

        do {
            try process.run()
        } catch {
            throw SevenZipError.processFailed(error.localizedDescription)
        }

        // See `OutputExceededLimit`'s own doc comment for why this exists.
        // Read in bounded chunks via `availableData` (blocks until at
        // least one byte or EOF, unlike a fixed-size `read` which could
        // spin) rather than `readDataToEndOfFile()`, so a decompression
        // bomb is caught — and the process killed — as soon as its output
        // crosses the limit, instead of only after it has already been
        // fully buffered into memory.
        var outputData = Data()
        var exceededLimit = false
        let outputHandle = outputPipe.fileHandleForReading
        while true {
            let chunk = outputHandle.availableData
            if chunk.isEmpty { break }
            outputData.append(chunk)
            if let maxOutputBytes, outputData.count > maxOutputBytes {
                exceededLimit = true
                // SIGTERM, not dependent on the pipe ever draining — 7zz
                // doesn't trap it, so this reliably kills the process even
                // though its stdout may still be blocked on a full pipe
                // buffer that nothing is reading anymore.
                process.terminate()
                break
            }
        }
        process.waitUntilExit()
        errorDrain.wait()

        return (outputData, errorBox.value, process.terminationStatus, exceededLimit)
    }

    /// Same rationale as `MAMEDATGenerator`/`MAMELauncher`'s own private
    /// `SendableBox` — a small mutable box so a background closure can
    /// safely write into shared state under Swift's strict concurrency
    /// checking. Duplicated rather than shared, same reasoning as those.
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
