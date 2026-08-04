// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Lists the file entries inside a `.7z` archive by shelling out to the
/// system's 7-Zip (`7zz l -slt`) and parsing its machine-readable listing.
public enum SevenZipArchiveScanner {
    public static func scan(archive archiveURL: URL, fileManager: FileManager = .default) throws -> [ArchivedFile] {
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw SevenZipError.cannotOpenArchive(archiveURL)
        }
        let executable = try SevenZipLocator.locate(fileManager: fileManager)
        let outputData = try SevenZipRunner.run(executableURL: executable, arguments: ["l", "-slt", archiveURL.path])
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw SevenZipError.malformedListing("output was not valid UTF-8")
        }
        return parseEntries(from: output, archiveURL: archiveURL)
    }

    /// `-slt` prints one "Key = Value" block per entry, separated by blank
    /// lines, after a "----------" separator that marks the end of the
    /// archive-level header block.
    static func parseEntries(from output: String, archiveURL: URL) -> [ArchivedFile] {
        let lines = output.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let separatorIndex = lines.firstIndex(where: isSeparatorLine) else {
            return []
        }

        var files: [ArchivedFile] = []
        var currentBlock: [String: String] = [:]

        func flush() {
            defer { currentBlock = [:] }
            guard let path = currentBlock["Path"], !path.isEmpty else { return }
            if currentBlock["Folder"] == "+" { return }
            if let attributes = currentBlock["Attributes"], attributes.hasPrefix("D") { return }
            let size = Int64(currentBlock["Size"] ?? "") ?? 0
            files.append(ArchivedFile(archiveURL: archiveURL, entryPath: path, name: (path as NSString).lastPathComponent, size: size))
        }

        for line in lines[(separatorIndex + 1)...] {
            if line.isEmpty {
                flush()
                continue
            }
            guard let range = line.range(of: " = ") else { continue }
            currentBlock[String(line[line.startIndex..<range.lowerBound])] = String(line[range.upperBound...])
        }
        flush()

        return files
    }

    private static func isSeparatorLine(_ line: String) -> Bool {
        line.count >= 10 && line.allSatisfy { $0 == "-" }
    }
}
