// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("SimilarNameSuggester")
struct SimilarNameSuggesterTests {
    @Test("finds a one-character-typo match above the 90% threshold")
    func findsTypoMatch() throws {
        let suggestion = try #require(SimilarNameSuggester.bestMatch(
            forLocalName: "Contra (USA).zip",
            candidateNames: ["Contra (USA)", "Castlevania (USA)"]
        ))
        #expect(suggestion.suggestedName == "Contra (USA)")
        #expect(suggestion.confidence == 1.0)
    }

    @Test("finds a genuinely misspelled name above threshold")
    func findsMisspelledMatch() throws {
        // "Contrs" vs "Contra" — one substitution out of 6 characters.
        let suggestion = try #require(SimilarNameSuggester.bestMatch(
            forLocalName: "Contrs (USA).zip",
            candidateNames: ["Contra (USA)", "Castlevania (USA)"]
        ))
        #expect(suggestion.suggestedName == "Contra (USA)")
        #expect(suggestion.confidence >= 0.9)
    }

    @Test("returns nil when nothing clears the threshold — a different game must never be suggested")
    func returnsNilWhenNothingCloseEnough() {
        #expect(SimilarNameSuggester.bestMatch(
            forLocalName: "Totally Unrelated Title (USA).zip",
            candidateNames: ["Contra (USA)", "Castlevania (USA)"]
        ) == nil)
    }

    @Test("picks the closer of two candidates when both clear the threshold")
    func picksClosestCandidate() throws {
        let suggestion = try #require(SimilarNameSuggester.bestMatch(
            forLocalName: "Contra (USA).zip",
            candidateNames: ["Contra (Europe)", "Contra (USA)"]
        ))
        #expect(suggestion.suggestedName == "Contra (USA)")
    }

    @Test("prefers an available candidate over an equally-scoring one that's already taken (a genuine tie)")
    func prefersAvailableCandidateOnAGenuineTie() throws {
        // Both candidates are exactly one substitution away from the local
        // name — a true tie in score. Without the availability preference,
        // whichever happened to be found first would win arbitrarily.
        let suggestion = try #require(SimilarNameSuggester.bestMatch(
            forLocalName: "Foo (ABC)",
            candidateNames: ["Foo (ABD)", "Foo (ABX)"],
            threshold: 0.60,
            isAvailable: { $0 != "Foo (ABD)" }
        ))
        #expect(suggestion.suggestedName == "Foo (ABX)")
    }

    @Test("never substitutes a clearly-inferior available candidate for a much better-scoring taken one — real bug found live (2026-09-29): \"Duck Tales (U).zip\" (80% match for the already-claimed \"DuckTales (USA)\") must never be redirected to the unrelated \"DuckTales 2 (Europe)\" (60%, merely available)")
    func neverSubstitutesInferiorAvailableCandidate() throws {
        let suggestion = try #require(SimilarNameSuggester.bestMatch(
            forLocalName: "Duck Tales (U)",
            candidateNames: ["DuckTales (USA)", "DuckTales 2 (Europe)"],
            threshold: 0.50,
            isAvailable: { $0 != "DuckTales (USA)" }
        ))
        #expect(suggestion.suggestedName == "DuckTales (USA)")
    }

    @Test("falls back to the best-scoring taken candidate when nothing available clears the threshold")
    func fallsBackToTakenCandidateWhenNoneAvailable() throws {
        let suggestion = try #require(SimilarNameSuggester.bestMatch(
            forLocalName: "Contrs (USA)",
            candidateNames: ["Contra (USA)", "Castlevania (USA)"],
            isAvailable: { _ in false }
        ))
        #expect(suggestion.suggestedName == "Contra (USA)")
    }

    @Test("a custom, lower threshold accepts a match the default would reject")
    func respectsCustomThreshold() {
        #expect(SimilarNameSuggester.bestMatch(
            forLocalName: "Contrz Adventurez (USA).zip", candidateNames: ["Contra (USA)"]
        ) == nil)
        #expect(SimilarNameSuggester.bestMatch(
            forLocalName: "Contrz Adventurez (USA).zip", candidateNames: ["Contra (USA)"], threshold: 0.3
        ) != nil)
    }

    @Test("a title with an internal abbreviation period is never mistaken for a trailing extension — real bug found live (2026-09-30) against a genuine NES collection: \"P.O.W. - Prisoners of War (U)\" (already extension-free — its caller strips the real \".zip\") used to have everything after the LAST period (\"P.O.W.\"'s own) silently discarded, collapsing it to just \"P.O.W\" and scoring 16% against the correct \"P.O.W. - Prisoners of War (USA)\" instead of the true ~94%")
    func abbreviationPeriodNeverMistakenForExtension() throws {
        let suggestion = try #require(SimilarNameSuggester.bestMatch(
            forLocalName: "P.O.W. - Prisoners of War (U)",
            candidateNames: ["P.O.W. - Prisoners of War (USA)", "Contra (USA)"]
        ))
        #expect(suggestion.suggestedName == "P.O.W. - Prisoners of War (USA)")
        #expect(suggestion.confidence >= 0.9)
    }

    @Test("a genuine trailing extension on a loose file's own name is still stripped correctly")
    func genuineTrailingExtensionStillStripped() throws {
        let suggestion = try #require(SimilarNameSuggester.bestMatch(
            forLocalName: "Dr. Mario (Japan, USA).nes",
            candidateNames: ["Dr. Mario (Japan, USA)", "Contra (USA)"]
        ))
        #expect(suggestion.suggestedName == "Dr. Mario (Japan, USA)")
        #expect(suggestion.confidence == 1.0)
    }
}
