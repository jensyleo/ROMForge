// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Computes CRC32/MD5/SHA1 for a file entry inside a `.7z` archive by
/// extracting it to stdout (`7zz e -so`) and hashing the resulting bytes.
public enum SevenZipArchiveHasher {
    public static func hash(_ file: ArchivedFile, fileManager: FileManager = .default) throws -> FileHash {
        let executable = try SevenZipLocator.locate(fileManager: fileManager)
        let data = try SevenZipRunner.run(
            executableURL: executable,
            arguments: ["e", "-so", "-y", file.archiveURL.path, file.entryPath]
        )
        return FileHasher.hash(data: data)
    }
}
