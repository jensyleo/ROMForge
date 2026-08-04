// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import ZIPFoundation

/// Lists the file entries inside a ZIP archive, without decompressing them.
public enum ZipArchiveScanner {
    public static func scan(archive archiveURL: URL) throws -> [ArchivedFile] {
        guard let archive = try? Archive(url: archiveURL, accessMode: .read) else {
            throw ZipArchiveError.cannotOpenArchive(archiveURL)
        }

        return archive
            .filter { $0.type == .file }
            .map { entry in
                ArchivedFile(
                    archiveURL: archiveURL,
                    entryPath: entry.path,
                    name: (entry.path as NSString).lastPathComponent,
                    size: Int64(entry.uncompressedSize)
                )
            }
    }
}
