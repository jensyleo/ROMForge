// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// How a confirmed-bad archive is handled — the "Corrupted files" three-way
/// policy from ClrMamePro's own Fix panel (see ROADMAP.md's own review of
/// it). Persisted as its raw string, same pattern as every other enum
/// setting in this app.
public enum CorruptedFilesPolicy: String, CaseIterable, Identifiable, Sendable {
    case dontTouch
    case delete
    case moveTo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dontTouch: return "Don't Touch"
        case .delete: return "Delete"
        case .moveTo: return "Move to…"
        }
    }
}

/// How a rename target's case is chosen — applied independently to
/// archive-level names ("Sets case") and entry-level names inside an
/// archive ("Roms case"). "Datafile case" means: whatever case the DAT's
/// own declared name already uses, verbatim — distinct from "Don't touch"
/// (leave the existing on-disk name's case alone, even if it disagrees with
/// the DAT).
public enum FileCasePolicy: String, CaseIterable, Identifiable, Sendable {
    case dontTouch
    case uppercase
    case lowercase
    case datafileCase

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dontTouch: return "Don't Touch"
        case .uppercase: return "Uppercase"
        case .lowercase: return "Lowercase"
        case .datafileCase: return "Datafile Case"
        }
    }
}

/// Every persisted preference behind the Settings → "Fix" tab (Fase 2 Step
/// 5) — one flat namespace of `UserDefaults` keys, same shape as every
/// other `*Settings` enum in this app (e.g. `ModificationsEnabledSettings`,
/// `RegionOrderSettings`). Deliberately holds keys for items not wired to
/// any real action yet (see each key's own doc comment for status) — the
/// plan (ROADMAP.md, "ClrMamePro's own 'Fix' preferences panel") calls for
/// building this shell first so every toggle exists and persists, then
/// wiring each one to its real action as that gets built, one at a time,
/// rather than adding UI and behavior together per-item.
public enum FixPreferencesSettings {
    // MARK: - Wired to a real action

    /// Runs `ZipIntegrityAuditor` as a Fix pre-pass. **Not yet connected**
    /// — `ZipIntegrityAuditor` operates on the flat, entry-based
    /// `AuditReport` (Fase 1's read-only audit), while `fix()` operates on
    /// `MatchReport` (the per-rom match result Fase 2 writes from); bridging
    /// the two is real work not yet done, so this toggle persists but
    /// nothing reads it yet.
    public static let testArchivesKey = "fixPreferences.testArchives"
    public static let testArchivesDefault = false

    /// Renames a misnamed *archive* (loose file, not an entry inside one) to
    /// match the DAT's declared name — **wired**: this is exactly what
    /// `RebuildPlanner.planRepair` + the existing "Fix" toolbar button
    /// already do; this toggle just lets that be turned off without
    /// disabling the whole Fix action.
    public static let renameFilesKey = "fixPreferences.renameFiles"
    public static let renameFilesDefault = true

    /// Deletes every file the DAT recognizes nothing about at all —
    /// **wired**: `LibraryViewModel.removeUselessFiles(system:)` +
    /// `RebuildPlanner.planRemoveUselessFiles`. Always has its own separate
    /// confirmation dialog (`LibraryDetailView`'s own "Remove Useless
    /// Files…" toolbar action) — this toggle only exists so the *auto*-Fix
    /// pass can optionally skip prompting for it every single time; the
    /// standalone toolbar action always confirms regardless of this value.
    public static let removeUselessFilesKey = "fixPreferences.removeUselessFiles"
    public static let removeUselessFilesDefault = false

    /// What happens to a file `ZipIntegrityAuditor` confirms is internally
    /// corrupt (local-header/central-directory CRC mismatch). **Not yet
    /// connected** — blocked on the same `AuditReport`/`MatchReport`
    /// bridging gap as `testArchivesKey` above.
    public static let corruptedFilesPolicyKey = "fixPreferences.corruptedFilesPolicy"
    public static let corruptedFilesPolicyDefault = CorruptedFilesPolicy.moveTo
    /// Destination folder path for `.moveTo` — this app doesn't run
    /// App-Sandboxed (no security-scoped bookmark needed anywhere else in
    /// its codebase), so a plain path string persists like every other
    /// user-picked folder setting here.
    public static let corruptedFilesMoveToPathKey = "fixPreferences.corruptedFilesMoveToPath"

    // MARK: - Shell only — not yet connected to any real action

    /// Rewriting a ZIP's own central directory to rename one entry in place
    /// — needs new low-level ZIP-writing code beyond what `TorrentZipWriter`
    /// exposes today. **Not yet connected.**
    public static let renameRomsKey = "fixPreferences.renameRoms"
    public static let renameRomsDefault = false

    /// Same delete action as `removeUselessFilesKey`, but for one entry
    /// inside an otherwise-kept archive rather than a whole loose file —
    /// needs the same central-directory rewrite `renameRomsKey` is blocked
    /// on. **Not yet connected.**
    public static let removeUselessRomsKey = "fixPreferences.removeUselessRoms"
    public static let removeUselessRomsDefault = false

    /// Searching user-configured "scavenging" folders for a same-hash file
    /// before reporting a rom missing — needs a new scavenging-folder-list
    /// setting and matcher variant, neither built yet. **Not yet connected.**
    public static let findMissingRomsKey = "fixPreferences.findMissingRoms"
    public static let findMissingRomsDefault = false

    /// Generating placeholder files for a frontend's game list — low
    /// priority per [[feedback_romforge_mame_first]]/the "never a launcher"
    /// scope decision. **Not yet connected.**
    public static let createDummyRomsKey = "fixPreferences.createDummyRoms"
    public static let createDummyRomsDefault = false

    /// Blocked entirely on the missing sample-scanning infrastructure noted
    /// in the project's own pending items. **Not yet connected.**
    public static let fixSamplesKey = "fixPreferences.fixSamples"
    public static let fixSamplesDefault = false

    /// Clearing a ZIP's end-of-central-directory comment field — small
    /// addition to the binary ZIP writer path, not yet built. **Not yet
    /// connected.**
    public static let removeZipCommentsKey = "fixPreferences.removeZipComments"
    public static let removeZipCommentsDefault = false

    /// Forcing every archive through a full extract + rewrite regardless of
    /// whether anything is wrong with it — needs a batch-mode entry point
    /// into the rebuild engine not built yet. **Not yet connected.**
    public static let unzipAndRezipKey = "fixPreferences.unzipAndRezip"
    public static let unzipAndRezipDefault = false

    /// Choosing an output container besides ZIP when rebuilding/fixing —
    /// meaningless until a second write path (7z? raw loose files?) exists
    /// beyond the current TorrentZip-only writer. **Not yet connected.**
    public static let allowMultipleRomFormatsKey = "fixPreferences.allowMultipleRomFormats"
    public static let allowMultipleRomFormatsDefault = false

    /// A user-facing concurrency slider for the Fix pass specifically —
    /// meaningless before the Fix engine itself has a concurrency primitive
    /// to expose. **Not yet connected.**
    public static let numberOfThreadsKey = "fixPreferences.numberOfThreads"
    public static let numberOfThreadsDefault = 4

    public static let setsCasePolicyKey = "fixPreferences.setsCasePolicy"
    public static let setsCasePolicyDefault = FileCasePolicy.dontTouch
    /// **Not yet connected** — needs the same central-directory rewrite
    /// concern as `renameRomsKey` for the archive-level case, plus the
    /// underlying case-transform rename operation.
    public static let romsCasePolicyKey = "fixPreferences.romsCasePolicy"
    public static let romsCasePolicyDefault = FileCasePolicy.dontTouch
}
