// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import ZIPFoundation

/// Executes a `RebuildOperation` plan against the real filesystem. Never
/// overwrites an existing destination — a collision is always an error, not
/// a silent clobber.
public enum RebuildExecutor {
    public static func execute(_ operations: [RebuildOperation], fileManager: FileManager = .default) throws {
        for operation in operations {
            try perform(operation, fileManager: fileManager)
        }
    }

    private static func perform(_ operation: RebuildOperation, fileManager: FileManager) throws {
        switch operation {
        case .rename(let source, let destination), .move(let source, let destination):
            try relocate(from: source, to: destination, fileManager: fileManager) {
                try fileManager.moveItem(at: source, to: destination)
            }
        case .copy(let source, let destination):
            try relocate(from: source, to: destination, fileManager: fileManager) {
                try fileManager.copyItem(at: source, to: destination)
            }
        case .createArchive(let entries, let destination):
            try createArchive(entries: entries, at: destination, fileManager: fileManager)
        }
    }

    private static func createArchive(
        entries: [ArchiveEntrySource],
        at destination: URL,
        fileManager: FileManager
    ) throws {
        for entry in entries {
            guard fileManager.fileExists(atPath: entry.source.path) else {
                throw RebuildError.sourceMissing(entry.source)
            }
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw RebuildError.destinationExists(destination)
        }
        let parent = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        guard let archive = try? Archive(url: destination, accessMode: .create) else {
            throw RebuildError.underlying("Could not create ZIP archive at \(destination.path)")
        }
        do {
            for entry in entries {
                try archive.addEntry(with: entry.entryName, fileURL: entry.source, compressionMethod: .deflate)
            }
        } catch {
            throw RebuildError.underlying(error.localizedDescription)
        }
    }

    private static func relocate(
        from source: URL,
        to destination: URL,
        fileManager: FileManager,
        _ perform: () throws -> Void
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            throw RebuildError.sourceMissing(source)
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw RebuildError.destinationExists(destination)
        }
        let parent = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        do {
            try perform()
        } catch let error as RebuildError {
            throw error
        } catch {
            throw RebuildError.underlying(error.localizedDescription)
        }
    }
}
