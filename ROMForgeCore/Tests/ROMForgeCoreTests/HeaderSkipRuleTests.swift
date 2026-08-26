// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("HeaderSkipRule")
struct HeaderSkipRuleTests {
    @Test("detects an iNES header by its magic and reports 16 bytes to skip")
    func detectsINES() {
        let head = Data([0x4E, 0x45, 0x53, 0x1A]) // "NES\x1A"
        #expect(HeaderSkipRule.iNES.headerLength(fileSize: 48, headBytes: head) == 16)
    }

    @Test("does not match iNES without the magic bytes")
    func rejectsNonINES() {
        let head = Data([0x00, 0x00, 0x00, 0x00])
        #expect(HeaderSkipRule.iNES.headerLength(fileSize: 48, headBytes: head) == 0)
    }

    @Test("detects a Lynx header by its magic and reports 64 bytes to skip")
    func detectsLynx() {
        let head = Data("LYNX".utf8)
        #expect(HeaderSkipRule.lynx64.headerLength(fileSize: 192, headBytes: head) == 64)
    }

    @Test("detects a 512-byte copier header purely by file size")
    func detectsCopierHeaderBySize() {
        #expect(HeaderSkipRule.copier512.headerLength(fileSize: 1024 + 512, headBytes: Data()) == 512) // 1536 % 1024 == 512
    }

    @Test("does not flag a plain, evenly-sized file as having a copier header")
    func rejectsEvenlySizedFile() {
        #expect(HeaderSkipRule.copier512.headerLength(fileSize: 1024, headBytes: Data()) == 0)
    }

    @Test("detect tries every rule and returns the first match")
    func detectFindsFirstMatch() throws {
        let head = Data([0x4E, 0x45, 0x53, 0x1A])
        let result = try #require(HeaderSkipRule.detect(fileSize: 48, headBytes: head))
        #expect(result.rule == .iNES)
        #expect(result.headerLength == 16)
    }

    @Test("detect returns nil when no rule's signature matches")
    func detectReturnsNilForPlainFile() {
        #expect(HeaderSkipRule.detect(fileSize: 1024, headBytes: Data(repeating: 0xFF, count: 4)) == nil)
    }
}
