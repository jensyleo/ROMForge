// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import ROMForgeCore

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

    /// Runs `ZipIntegrityAuditor` as a `fix()` pre-pass specifically.
    /// **Not yet connected to `fix()`** — the underlying bridge between
    /// `AuditReport` (Fase 1's flat, entry-based read-only audit) and
    /// `MatchReport` (`fix()`'s own input) does now exist (see
    /// `RebuildPlanner.planCorruptedFilesPolicy`, which uses exactly this
    /// bridge via `AuditReporter.generate(from:)`), but nothing wires THIS
    /// toggle specifically into `fix()`'s own rename pass yet — use the
    /// standalone "Handle Corrupted Files…" toolbar action
    /// (`corruptedFilesPolicyKey` below) to act on corrupted files today.
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
    /// That same action already covers BOTH loose files and a zip-internal
    /// entry uniformly (`RebuildPlanner.planRemoveUselessFiles` routes each
    /// through `.delete`/`.removeEntryFromZip` as appropriate) — there's no
    /// separate toggle to gate the archive-entry half specifically.
    public static let removeUselessFilesKey = "fixPreferences.removeUselessFiles"
    public static let removeUselessFilesDefault = false

    /// What happens to a file `ZipIntegrityAuditor` confirms is internally
    /// corrupt (local-header/central-directory CRC mismatch) — **wired**:
    /// `LibraryViewModel.applyCorruptedFilesPolicy(system:)` +
    /// `RebuildPlanner.planCorruptedFilesPolicy`, via the standalone
    /// "Handle Corrupted Files…" toolbar action (always confirms
    /// regardless of this toggle's own value — same relationship every
    /// other policy toggle on this tab has with its own action).
    public static let corruptedFilesPolicyKey = "fixPreferences.corruptedFilesPolicy"
    public static let corruptedFilesPolicyDefault = CorruptedFilesPolicy.moveTo
    /// Destination folder path for `.moveTo` — this app doesn't run
    /// App-Sandboxed (no security-scoped bookmark needed anywhere else in
    /// its codebase), so a plain path string persists like every other
    /// user-picked folder setting here.
    public static let corruptedFilesMoveToPathKey = "fixPreferences.corruptedFilesMoveToPath"

    /// Same underlying action as `removeUselessFilesKey` above — that
    /// toggle's own action already covers a zip-internal entry as well as
    /// a whole loose file, via `RebuildOperation.removeEntryFromZip`
    /// (`Archive.remove(_:)` under ZIPFoundation's `.update` access mode).
    /// Kept as its own separate `@AppStorage` key only to mirror
    /// ClrMamePro's own panel having two separate checkboxes here — there's
    /// no plan to actually gate anything differently between the two.
    public static let removeUselessRomsKey = "fixPreferences.removeUselessRoms"
    public static let removeUselessRomsDefault = false

    /// Renames a misnamed rom entry inside an otherwise-correctly-named zip
    /// (remove the old name, add the same bytes back under the new one) —
    /// **wired**: `LibraryViewModel.renameRomsInArchive(system:)` +
    /// `RebuildPlanner.planRenameRomsInArchive`. Its own standalone toolbar
    /// action ("Rename ROMs Inside Archives…") always confirms regardless
    /// of this toggle, same relationship `removeUselessFilesKey` above has
    /// with its own toolbar action.
    public static let renameRomsKey = "fixPreferences.renameRoms"
    public static let renameRomsDefault = false

    // MARK: - Shell only — not yet connected to any real action

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
