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
    static func run(executableURL: URL, arguments: [String]) throws -> Data {
        let result = try invoke(executableURL: executableURL, arguments: arguments)
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
        arguments: [String]
    ) throws -> (standardOutput: Data, standardError: Data, exitCode: Int32) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let errorDrain = DispatchGroup()
        var errorData = Data()
        errorDrain.enter()
        DispatchQueue.global(qos: .utility).async {
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            errorDrain.leave()
        }

        do {
            try process.run()
        } catch {
            throw SevenZipError.processFailed(error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errorDrain.wait()

        return (outputData, errorData, process.terminationStatus)
    }
}
