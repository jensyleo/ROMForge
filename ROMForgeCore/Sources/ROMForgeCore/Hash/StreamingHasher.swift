// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import CryptoKit
import Foundation

/// Feeds successive chunks of a file's content (from disk or from inside an
/// archive) into whichever of CRC32/MD5/SHA1 `algorithms` selects,
/// simultaneously, so any streaming source only needs to be read once. A
/// disabled algorithm's own hasher is simply never fed any data — cheap to
/// have allocated but unused, versus the real cost (feeding potentially
/// hundreds of MB through it) this actually avoids. Shared by `FileHasher`
/// and the archive hashers.
struct StreamingHasher {
    private let algorithms: HashAlgorithms
    private var crc = CRC32.initial
    private var md5 = Insecure.MD5()
    private var sha1 = Insecure.SHA1()

    init(algorithms: HashAlgorithms = .all) {
        self.algorithms = algorithms
    }

    mutating func update(_ data: Data) {
        if algorithms.contains(.crc32) { crc = CRC32.update(crc, with: data) }
        if algorithms.contains(.md5) { md5.update(data: data) }
        if algorithms.contains(.sha1) { sha1.update(data: data) }
    }

    func finalize() -> FileHash {
        FileHash(
            crc32: algorithms.contains(.crc32) ? Self.hexString(CRC32.finalize(crc)) : nil,
            md5: algorithms.contains(.md5) ? Self.hexString(md5.finalize()) : nil,
            sha1: algorithms.contains(.sha1) ? Self.hexString(sha1.finalize()) : nil
        )
    }

    private static func hexString(_ value: UInt32) -> String {
        String(format: "%08x", value)
    }

    private static func hexString(_ digest: some Sequence<UInt8>) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
