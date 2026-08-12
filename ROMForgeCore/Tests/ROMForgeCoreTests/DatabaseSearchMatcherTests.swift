// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("DatabaseSearchMatcher")
struct DatabaseSearchMatcherTests {
    @Test("a plain pattern matches only from the start of the text, case-insensitively")
    func plainPatternIsPrefixOnly() {
        #expect(DatabaseSearchMatcher.matches("Street Fighter", pattern: "street"))
        #expect(!DatabaseSearchMatcher.matches("64 Street", pattern: "street"))
    }

    @Test("* matches any run of characters anywhere")
    func starMatchesAnywhere() {
        #expect(DatabaseSearchMatcher.matches("64 Street", pattern: "*street*"))
        #expect(DatabaseSearchMatcher.matches("Street Fighter 64", pattern: "*64"))
        #expect(!DatabaseSearchMatcher.matches("Street Fighter", pattern: "*64"))
    }

    @Test("a single-sided * still means \"contains\", not \"starts/ends with\"")
    func oneSidedStarStillMeansContains() {
        // jensyleo's own report (2026-08-13): "*street" used to require the
        // text to END exactly with "street" (fully anchored `^...$`) — real
        // game names like "Street Fighter II" or "64th. Street: A Detective
        // Story" never actually end there, so this found nothing, contrary
        // to what a leading `*` intuitively promises: "match street
        // anywhere". Anchors were dropped entirely for any wildcard pattern
        // to fix this — `*street`/`street*`/`*street*` all behave the same
        // now, exactly like a plain "contains" search.
        #expect(DatabaseSearchMatcher.matches("Street Fighter II", pattern: "*street"))
        #expect(DatabaseSearchMatcher.matches("64th. Street: A Detective Story", pattern: "*street"))
        #expect(DatabaseSearchMatcher.matches("Street Fighter II", pattern: "street*"))
    }

    @Test("? matches exactly one character, anywhere in the text")
    func questionMarkMatchesOneCharacter() {
        #expect(DatabaseSearchMatcher.matches("18wheelr", pattern: "18wheel?"))
        // jensyleo's own report (2026-08-13): a wildcard pattern is no
        // longer anchored to the *whole* string — same fix, same reasoning,
        // as `*street` now finding "Street Fighter" instead of requiring
        // the text to end exactly there. "18wheel?" just needs "18wheel" +
        // one more character to appear *somewhere*, which "18wheeler"
        // satisfies (as a prefix, with "r" left over after) — this used to
        // be `false` under the old fully-anchored behavior.
        #expect(DatabaseSearchMatcher.matches("18wheeler", pattern: "18wheel?"))
    }
}
