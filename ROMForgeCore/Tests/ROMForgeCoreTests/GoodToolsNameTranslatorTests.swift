// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("GoodToolsNameTranslator")
struct GoodToolsNameTranslatorTests {
    @Test("translates a plain region tag")
    func translatesPlainRegionTag() {
        #expect(GoodToolsNameTranslator.candidateNames(forLocalName: "8 Eyes (U)") == ["8 Eyes (USA)"])
    }

    @Test("translates a combined region tag to both No-Intro orderings")
    func translatesCombinedRegionTag() {
        #expect(GoodToolsNameTranslator.candidateNames(forLocalName: "1942 (JU)") == ["1942 (Japan, USA)", "1942 (USA, Japan)"])
    }

    @Test("reorders a trailing article alongside the un-reordered stem")
    func reordersTrailingArticle() {
        let candidates = GoodToolsNameTranslator.candidateNames(forLocalName: "Addams Family The (U)")
        #expect(candidates.contains("Addams Family, The (USA)"))
        #expect(candidates.contains("Addams Family The (USA)"))
    }

    @Test("normalizedKey makes GoodTools' apostrophe-as-space convention compare equal to the real apostrophe")
    func normalizedKeyIgnoresApostropheVsSpace() {
        #expect(GoodToolsNameTranslator.normalizedKey("Gilligan's Island") == GoodToolsNameTranslator.normalizedKey("Gilligan s Island"))
    }

    @Test("candidateFileNames is extension-aware and tolerates a stray trailing space before the extension")
    func candidateFileNamesHandlesExtensionAndStraySpace() {
        #expect(GoodToolsNameTranslator.candidateFileNames(forRawFileName: "10-Yard Fight (U) .nes") == ["10-Yard Fight (USA).nes"])
    }

    @Test("returns nothing for a name with no recognized trailing tag")
    func returnsEmptyForUntaggedName() {
        #expect(GoodToolsNameTranslator.candidateNames(forLocalName: "Just A Title") == [])
        #expect(GoodToolsNameTranslator.candidateNames(forLocalName: "Something (NotARealTag123)") == [])
        #expect(GoodToolsNameTranslator.candidateFileNames(forRawFileName: "no_extension_here") == [])
    }
}
