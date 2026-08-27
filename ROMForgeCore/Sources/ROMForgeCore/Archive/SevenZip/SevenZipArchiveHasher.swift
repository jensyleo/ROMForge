// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Computes CRC32/MD5/SHA1 for a file entry inside a `.7z` archive by
/// extracting it to stdout (`7zz e -so`) and hashing the resulting bytes.
public enum SevenZipArchiveHasher {
    /// Same heuristic as `ZipArchiveHasher`'s own `overageLimit(for:)` — a
    /// legitimate entry's decompressed size is never wildly larger than
    /// what the archive's own listing declares, so an entry that
    /// decompresses to more than 10× its declared size (floor 1 MiB, for
    /// tiny declared sizes) is treated as a suspected decompression bomb.
    private static let maxOverDeclaredSizeFactor: Int64 = 10

    public static func hash(_ file: ArchivedFile, fileManager: FileManager = .default) throws -> FileHash {
        let executable = try SevenZipLocator.locate(fileManager: fileManager)
        let limit = max(1_048_576, file.size * maxOverDeclaredSizeFactor)
        let data: Data
        do {
            data = try SevenZipRunner.run(
                executableURL: executable,
                // jensyleo's own report (2026-08-26, security audit):
                // `file.entryPath` comes verbatim from the archive's own
                // listing (`SevenZipArchiveScanner`), so a crafted `.7z`
                // could name an entry starting with `-` (e.g. `-p…`,
                // `-o…`) that 7zz's own argument parser might interpret as
                // a switch rather than a filename, letting the archive
                // influence 7zz's own behavior beyond just what gets
                // decompressed. `--` tells 7zz's argument parser that
                // everything after it is a positional filename, never a
                // switch, closing that off.
                arguments: ["e", "-so", "-y", "--", file.archiveURL.path, file.entryPath],
                maxOutputBytes: Int(min(limit, Int64(Int.max)))
            )
        } catch is SevenZipRunner.OutputExceededLimit {
            throw SevenZipError.suspectedDecompressionBomb(entryPath: file.entryPath, declaredSize: file.size)
        }
        return FileHasher.hash(data: data)
    }
}
