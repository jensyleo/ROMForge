// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// A purely presentational read of the DAT's own parent/clone tree (MAME's
/// `cloneof`) against a completed scan's own per-game status — never a new
/// audit category, never anything `AuditReporter`/`GameStatusRollup` feed
/// into. Two facts only, both cheap in-memory aggregation over data a scan
/// already produced (`gameAggregateStatusByName`), never a re-scan:
/// - a parent's own clone family completeness ("3/5 clones present"), and
/// - a present clone whose own parent is missing/absent from the collection.
public struct ParentCloneSummary: Equatable, Sendable {
    /// How many of a parent's known clones (by DAT machine name) are
    /// present in the collection, out of how many the DAT declares.
    public struct CloneCompletion: Equatable, Sendable {
        public let present: Int
        public let total: Int
    }

    /// Keyed by parent machine name — only parents that actually have at
    /// least one clone in the DAT get an entry.
    public let cloneCompletionByParent: [String: CloneCompletion]
    /// Clone machine names that are themselves present but whose declared
    /// `cloneof` parent is not — the "missing parent" highlight.
    public let clonesMissingParent: Set<String>

    public init(cloneCompletionByParent: [String: CloneCompletion], clonesMissingParent: Set<String>) {
        self.cloneCompletionByParent = cloneCompletionByParent
        self.clonesMissingParent = clonesMissingParent
    }

    /// A game counts as "present" when the scan actually matched something
    /// for it (any status at all) rather than `.missing` — same meaning
    /// "present in the collection" already carries everywhere else in the
    /// app (e.g. `GameStatusRollup`'s own worst-first rollup), just read
    /// here from the already-computed per-game aggregate instead of raw
    /// entries.
    private static func isPresent(_ name: String, statusByName: [String: AuditStatus]) -> Bool {
        statusByName[name].map { $0 != .missing } ?? false
    }

    /// `games` should be the DAT's full machine list (every clone included,
    /// independent of Rom merge mode — same reasoning as `DATFile
    /// .hasClones`/`allMachineNames`, this must reflect the real DAT tree,
    /// not whatever a Merged-mode game list happens to still mention).
    /// `statusByName` is the scan's own rom-only aggregate per game name
    /// (`gameAggregateStatusByName` in the App layer) — empty (no scan yet)
    /// simply yields an empty summary, nothing to highlight.
    public static func compute(games: [DATGame], statusByName: [String: AuditStatus]) -> ParentCloneSummary {
        guard !statusByName.isEmpty else {
            return ParentCloneSummary(cloneCompletionByParent: [:], clonesMissingParent: [])
        }
        var totalByParent: [String: Int] = [:]
        var presentByParent: [String: Int] = [:]
        var clonesMissingParent: Set<String> = []

        for game in games {
            guard let parent = game.cloneOf else { continue }
            totalByParent[parent, default: 0] += 1
            let clonePresent = isPresent(game.name, statusByName: statusByName)
            if clonePresent {
                presentByParent[parent, default: 0] += 1
                if !isPresent(parent, statusByName: statusByName) {
                    clonesMissingParent.insert(game.name)
                }
            }
        }

        let completion = totalByParent.reduce(into: [String: CloneCompletion]()) { result, entry in
            result[entry.key] = CloneCompletion(present: presentByParent[entry.key] ?? 0, total: entry.value)
        }
        return ParentCloneSummary(cloneCompletionByParent: completion, clonesMissingParent: clonesMissingParent)
    }
}
