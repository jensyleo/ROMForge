// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// The region names this compares a `DATGame.description`'s parenthesized
/// tokens against, and the order that's preferred absent any user choice —
/// jensyleo's own spec (2026-08-19): World, USA, Europe, Japan, Asia first,
/// then everything else. The "everything else" tail's own internal order
/// has no real user-facing meaning (nothing about MAME set naming ranks
/// Brazil above Korea, say) — it only exists so `RegionOrderSettings`
/// (App layer) has a full, stable list to start a user's own reorder from,
/// rather than silently dropping any region this doesn't already know
/// about.
public enum RegionCatalog {
    public static let defaultOrder: [String] = [
        "World", "USA", "Europe", "Japan", "Asia",
        "Australia", "Brazil", "Canada", "China", "France", "Germany",
        "Hong Kong", "Italy", "Korea", "Netherlands", "Spain", "Sweden", "Taiwan", "UK",
    ]
}

/// A purely presentational 1G1R (One Game One ROM) read over an already-
/// loaded DAT's parent/clone families — never touches a scan result, never
/// deletes/hides a real file, just which `DATGame.name`s a "Show only 1G1R"
/// toggle would hide and which one a family's own preferred-region star
/// belongs to. See `LibraryDetailView`'s own doc comments for where this
/// feeds the Games table.
public struct OneGameOneROMSummary: Equatable, Sendable {
    /// The winning `DATGame.name` of every family that had at least one
    /// member with a recognized region — shown with a star regardless of
    /// whether the toggle itself is on.
    public let preferredGameNames: Set<String>
    /// Every OTHER member of one of those same families — what "Show only
    /// 1G1R" actually hides. A family with no recognized region at all
    /// never contributes any name here (see `OneGameOneROMSelector
    /// .compute(games:regionOrder:)`'s own doc comment).
    public let hiddenWhenFilteredNames: Set<String>

    public init(preferredGameNames: Set<String>, hiddenWhenFilteredNames: Set<String>) {
        self.preferredGameNames = preferredGameNames
        self.hiddenWhenFilteredNames = hiddenWhenFilteredNames
    }

    public static let empty = OneGameOneROMSummary(preferredGameNames: [], hiddenWhenFilteredNames: [])
}

public enum OneGameOneROMSelector {
    /// The best (lowest-index in `order`) region token found among every
    /// parenthesized group in `description` — `nil` when none of them
    /// match a name in `order` at all, meaning this variant simply doesn't
    /// participate in 1G1R (jensyleo's own call: it stays visible always,
    /// never hidden, never competes for the star).
    public static func detectedRegion(inDescription description: String, order: [String]) -> String? {
        guard !order.isEmpty else { return nil }
        var bestIndex: Int?
        var bestRegion: String?
        for group in parenthesizedGroups(in: description) {
            for rawToken in group.split(separator: ",") {
                let token = rawToken.trimmingCharacters(in: .whitespaces)
                guard !token.isEmpty else { continue }
                guard let index = order.firstIndex(where: { $0.compare(token, options: .caseInsensitive) == .orderedSame }) else { continue }
                if bestIndex == nil || index < bestIndex! {
                    bestIndex = index
                    bestRegion = order[index]
                }
            }
        }
        return bestRegion
    }

    /// Every `(...)`-delimited group's own inner text, in appearance order
    /// — e.g. `"Sonic the Hedgehog (World) (Rev A)"` yields `["World", "Rev A"]`.
    /// Nested parens (never actually seen in a real MAME description, but
    /// cheap to handle correctly) just widen the outer group rather than
    /// producing a separate nested one.
    private static func parenthesizedGroups(in text: String) -> [String] {
        var groups: [String] = []
        var depth = 0
        var current = ""
        for character in text {
            if character == "(" {
                if depth == 0 { current = "" }
                depth += 1
                continue
            }
            if character == ")" {
                guard depth > 0 else { continue }
                depth -= 1
                if depth == 0 { groups.append(current) }
                continue
            }
            if depth > 0 { current.append(character) }
        }
        return groups
    }

    /// `games` should be the DAT's full machine list, same reasoning as
    /// `ParentCloneSummary.compute(games:statusByName:)` — every clone
    /// must be present regardless of Rom merge mode for the family
    /// grouping below to be real. Grouped by `cloneOf ?? name` — a parent
    /// (`cloneOf == nil`) is its own family's key, and every clone
    /// declaring that same parent joins it under the identical key, so no
    /// separate merge step is needed to fold the two together.
    ///
    /// A family only contributes to the summary once at least two members
    /// exist (nothing to prefer over a lone game) AND at least one member
    /// has a recognized region — a family where nothing is recognized
    /// hides nothing and stars nothing, exactly jensyleo's spec ("si
    /// NINGUNA variante de la familia tiene región reconocida, no ocultar
    /// nada de esa familia"). Ties (two members sharing the same best
    /// region) break on `DATGame.name` alphabetically — an arbitrary but
    /// deterministic choice, since the spec doesn't cover it.
    public static func compute(games: [DATGame], regionOrder: [String]) -> OneGameOneROMSummary {
        guard !regionOrder.isEmpty, !games.isEmpty else { return .empty }
        var familyMembers: [String: [DATGame]] = [:]
        for game in games {
            familyMembers[game.cloneOf ?? game.name, default: []].append(game)
        }

        var preferred: Set<String> = []
        var hidden: Set<String> = []
        for members in familyMembers.values {
            guard members.count > 1 else { continue }
            let recognized = members.compactMap { game -> (game: DATGame, regionIndex: Int)? in
                guard let region = detectedRegion(inDescription: game.description, order: regionOrder),
                      let index = regionOrder.firstIndex(of: region)
                else { return nil }
                return (game, index)
            }
            guard let winner = recognized.min(by: { lhs, rhs in
                lhs.regionIndex != rhs.regionIndex ? lhs.regionIndex < rhs.regionIndex : lhs.game.name < rhs.game.name
            }) else { continue }
            preferred.insert(winner.game.name)
            // Only a recognized-but-not-winning member ever gets hidden —
            // an unrecognized one never competed for the star in the
            // first place, so it stays visible regardless (see this
            // function's own doc comment).
            for candidate in recognized where candidate.game.name != winner.game.name {
                hidden.insert(candidate.game.name)
            }
        }
        return OneGameOneROMSummary(preferredGameNames: preferred, hiddenWhenFilteredNames: hidden)
    }
}
