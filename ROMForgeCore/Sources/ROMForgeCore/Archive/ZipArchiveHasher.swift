// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import ZIPFoundation

/// Computes CRC32/MD5/SHA1 for a file entry inside a ZIP archive by
/// streaming its decompressed content, without extracting it to disk first.
public enum ZipArchiveHasher {
    /// Zip-bomb guard: a ZIP's central directory declares each entry's
    /// uncompressed size, but that value is attacker-controlled — a
    /// maliciously crafted entry can decompress to far more actual bytes
    /// than it declares (the classic "42.zip" technique). Extraction is
    /// aborted once the running decompressed byte count exceeds the
    /// declared size by more than this factor, rather than trusting the
    /// declared size as a hard cap (real ROM/CD dumps can legitimately be
    /// many GB, so a fixed absolute limit would reject them).
    private static let maxOverDeclaredSizeFactor: Int64 = 10

    private static func overageLimit(for declaredSize: Int64) -> Int64 {
        max(1_048_576, declaredSize * maxOverDeclaredSizeFactor)
    }

    /// Same lowercase, zero-padded 8-digit hex format `StreamingHasher`
    /// already uses for a computed CRC32, so a checksum read straight from
    /// the zip's own metadata (the fast path below) is indistinguishable
    /// from one actually computed by hashing.
    private static func hexString(_ value: UInt32) -> String {
        String(format: "%08x", value)
    }


    /// Hashes an entry's full decompressed content, and — if a known
    /// copier-header signature is detected on it (`HeaderSkipRule`) — also
    /// hashes its header-stripped content, the same detection `FileHasher`
    /// applies to loose files. A header is only ever this rare, so the
    /// (otherwise wasteful) second extraction pass only happens when one is
    /// actually detected.
    public static func hash(_ file: ArchivedFile, algorithms: HashAlgorithms = .all) throws -> (hash: FileHash, headerStripped: HeaderStrippedHash?) {
        // `Archive(url:accessMode:preferredEncoding:)` (failable, deprecated)
        // → `Archive(url:accessMode:pathEncoding:)` (throwing) — 2026-08-13
        // cleanup pass, no behavior change: still surfaces our own
        // `.cannotOpenArchive` regardless of what ZIPFoundation itself threw.
        let archive: Archive
        do {
            archive = try Archive(url: file.archiveURL, accessMode: .read)
        } catch {
            throw ZipArchiveError.cannotOpenArchive(file.archiveURL)
        }
        guard let entry = archive[file.entryPath] else {
            throw ZipArchiveError.entryNotFound(entryPath: file.entryPath, archiveURL: file.archiveURL)
        }

        // Fast path: CRC32 is the *only* thing being computed, and this
        // isn't a Genesis-SMD file (deinterleaving needs the real
        // decompressed bytes, so it can't use this path). The ZIP format
        // itself already stores each entry's CRC32 in its own central
        // directory record — computed once, when the archive was built —
        // so it can be read directly, with no decompression at all.
        // Decompression (DEFLATE), not hashing, is what actually dominates
        // a real scan's cost: CRC32 itself is fast regardless of which
        // algorithm(s) are enabled, since every enabled algorithm's
        // `update()` still has to see every decompressed byte first. A
        // real user-reported case: leaving only CRC32 enabled for speed
        // (see `HashAlgorithms`) didn't actually speed up a scan of
        // compressed archives, because the app kept fully decompressing
        // every entry anyway just to feed CRC32 the bytes it needed —
        // bytes it turns out were already sitting in the zip's own
        // metadata, unread.
        //
        // This does mean a headered console dump (e.g. an iNES ROM with
        // its 16-byte copier header) never gets a header-stripped match
        // attempt in this mode, since that detection needs to actually
        // read the file's leading bytes — a real, deliberate trade-off
        // that only applies when the user has already opted into "CRC32
        // only" for maximum speed.
        if algorithms == .crc32, !file.name.lowercased().hasSuffix(".smd") {
            return (FileHash(crc32: Self.hexString(entry.checksum), md5: nil, sha1: nil), nil)
        }

        let limit = overageLimit(for: file.size)

        var hasher = StreamingHasher(algorithms: algorithms)
        var headBytes = Data()
        var extracted: Int64 = 0
        do {
            _ = try archive.extract(entry) { chunk in
                extracted += Int64(chunk.count)
                guard extracted <= limit else {
                    throw ZipArchiveError.suspectedZipBomb(entryPath: file.entryPath, declaredSize: file.size)
                }
                hasher.update(chunk)
                if headBytes.count < 64 {
                    headBytes.append(chunk.prefix(64 - headBytes.count))
                }
            }
        } catch let error as ZipArchiveError {
            throw error
        } catch {
            throw ZipArchiveError.extractionFailed(error.localizedDescription)
        }
        let rawHash = hasher.finalize()

        if file.name.lowercased().hasSuffix(".smd"), GenesisSMDConverter.isSMDInterleaved(fileSize: file.size) {
            var fullData = Data()
            do {
                _ = try archive.extract(entry) { chunk in
                    guard Int64(fullData.count + chunk.count) <= limit else {
                        throw ZipArchiveError.suspectedZipBomb(entryPath: file.entryPath, declaredSize: file.size)
                    }
                    fullData.append(chunk)
                }
            } catch let error as ZipArchiveError {
                throw error
            } catch {
                throw ZipArchiveError.extractionFailed(error.localizedDescription)
            }
            if let deinterleaved = GenesisSMDConverter.deinterleave(fullData) {
                return (rawHash, HeaderStrippedHash(rule: .genesisSMD, size: Int64(deinterleaved.count), hash: FileHasher.hash(data: deinterleaved, algorithms: algorithms)))
            }
        }

        guard let (rule, headerLength) = HeaderSkipRule.detect(fileSize: file.size, headBytes: headBytes) else {
            return (rawHash, nil)
        }

        var strippedHasher = StreamingHasher(algorithms: algorithms)
        var skipped: Int64 = 0
        var strippedExtracted: Int64 = 0
        do {
            _ = try archive.extract(entry) { chunk in
                strippedExtracted += Int64(chunk.count)
                guard strippedExtracted <= limit else {
                    throw ZipArchiveError.suspectedZipBomb(entryPath: file.entryPath, declaredSize: file.size)
                }
                guard skipped < Int64(headerLength) else {
                    strippedHasher.update(chunk)
                    return
                }
                let remaining = Int64(headerLength) - skipped
                if Int64(chunk.count) <= remaining {
                    skipped += Int64(chunk.count)
                } else {
                    strippedHasher.update(chunk.suffix(chunk.count - Int(remaining)))
                    skipped = Int64(headerLength)
                }
            }
        } catch let error as ZipArchiveError {
            throw error
        } catch {
            throw ZipArchiveError.extractionFailed(error.localizedDescription)
        }
        return (rawHash, HeaderStrippedHash(rule: rule, size: file.size - Int64(headerLength), hash: strippedHasher.finalize()))
    }
}
