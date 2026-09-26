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
    // jensyleo's own request (2026-09-10): "Restore to Defaults" for the
    // Fix tab needs a real default to reset EVERY setting back to,
    // including this one — an empty path (no folder chosen) is exactly
    // what a fresh install already starts with.
    public static let corruptedFilesMoveToPathDefault = ""

    /// Same underlying action as `removeUselessFilesKey` above — that
    /// toggle's own action already covers a zip-internal entry as well as
    /// a whole loose file, via `RebuildOperation.removeEntryFromZip`
    /// (`Archive.remove(_:)` under ZIPFoundation's `.update` access mode).
    /// Kept as its own separate `@AppStorage` key only to mirror
    /// ClrMamePro's own panel having two separate checkboxes here — there's
    /// no plan to actually gate anything differently between the two.
    public static let removeUselessRomsKey = "fixPreferences.removeUselessRoms"
    public static let removeUselessRomsDefault = false

    /// Removed (2026-09-26, jensyleo's own request): "Find ROMs…" (formerly
    /// "Repair from Maintenance Folder…") always crosses ROM folders
    /// unconditionally whenever it isn't scoped to one specific
    /// folder/file — the "Maintenance Folder Only" vs "+ All ROM Folders"
    /// choice that used to live here never actually changed anything
    /// observable, so it was deleted outright rather than kept as a dead
    /// toggle. See `LibraryViewModel.planRepairFromMaintenanceFolderPreviewCount`'s own doc
    /// comment for the current, single behavior this replaces.

    /// Which physical copy counts as "correct" when the exact same CHD
    /// (same header sha1) exists more than once — jensyleo's own real case
    /// (2026-09-19), a `kinst2.chd` sitting BOTH directly in a ROM folder's
    /// root AND inside a same-named subfolder. See `CHDDuplicatePreference`'s
    /// own doc comment. **Wired** into `DiskAuditor.audit` via
    /// `LibraryViewModel.scan(system:folders:)`.
    public static let chdDuplicatePreferenceKey = "fixPreferences.chdDuplicatePreference"
    // jensyleo's own correction (2026-09-19): dropped the original
    // "No Preference" case entirely rather than just defaulting away from
    // it — an unpredictable, order-of-discovery pick is exactly the
    // ambiguity this setting exists to remove.
    //
    // jensyleo's own follow-up (2026-09-26): "Prefer Subfolder" is now the
    // default instead — his own real collection's actual layout (a CHD
    // inside a subfolder named after the game, not loose in the ROM
    // folder's root) is what this should assume out of the box.
    public static let chdDuplicatePreferenceDefault = CHDDuplicatePreference.preferSubfolder

    public static func currentCHDDuplicatePreference() -> CHDDuplicatePreference {
        CHDDuplicatePreference(rawValue: UserDefaults.standard.string(forKey: chdDuplicatePreferenceKey) ?? "") ?? chdDuplicatePreferenceDefault
    }

    /// One File-level case style, driving BOTH halves of one single "Fix"
    /// pass — **wired** into `RebuildPlanner.planRepair`'s own
    /// `filesCasePolicy` (a genuinely wrong name, fixed TO this style) AND
    /// `RebuildPlanner.planApplySetsCasePolicy` (an already-correct name,
    /// re-styled to it too), both run together by
    /// `LibraryViewModel.fix(system:)` ("Fix Mismatched Files") in one
    /// click. jensyleo's own decision (2026-09-10), after these two halves
    /// briefly lived behind two separate toolbar actions sharing this one
    /// setting: "o es una o es la otra" — unify into one action, since a
    /// mismatch fix was never really optional to begin with (matching the
    /// DAT is the whole point of the app); this setting only ever governs
    /// HOW a name is styled, on either side of that unconditional pass.
    /// `.dontTouch` means something slightly different for each half — for
    /// the already-correct one it genuinely means "leave its case alone";
    /// for a genuine mismatch there's always SOME real rename to make, so
    /// `.dontTouch` there falls back to `.datafileCase` (the DAT's own
    /// exact declared case) instead of leaving the wrong name in place —
    /// see `RebuildPlanner.mismatchFixName`'s own doc comment.
    public static let setsCasePolicyKey = "fixPreferences.setsCasePolicy"
    // jensyleo's own decision (2026-09-10), after Fix started working for
    // real: default to `.datafileCase` rather than `.dontTouch` — the
    // DAT's own exact declared case is the least surprising default for a
    // fresh install (it's what a mismatch fix already effectively falls
    // back to per `mismatchFixName`'s own doc comment; making it the
    // explicit default too means the already-correct re-styling half
    // behaves the same way out of the box, instead of silently doing
    // nothing until a user finds this setting).
    public static let setsCasePolicyDefault = FileCasePolicy.datafileCase
    /// The same unification, at the ROM-entry level — used by both
    /// `RebuildPlanner.planRenameRomsInArchive` and
    /// `RebuildPlanner.planApplyRomsCasePolicy`, both run together by
    /// `LibraryViewModel.renameRomsInArchive(system:)` ("Fix Misnamed ROMs
    /// Inside Their Archives…").
    public static let romsCasePolicyKey = "fixPreferences.romsCasePolicy"
    // Same default change and reasoning as `setsCasePolicyDefault` above.
    public static let romsCasePolicyDefault = FileCasePolicy.datafileCase

    // MARK: - Reading the current value

    /// The one-line `FileCasePolicy(rawValue: UserDefaults.standard
    /// .string(forKey:) ?? "") ?? default` pattern, factored out here after
    /// a code audit (2026-09-10) found it repeated identically at 6 call
    /// sites across `LibraryViewModel`/`LibraryDetailView` — a pure
    /// read-only refactor, no behavior change.
    public static func currentSetsCasePolicy() -> FileCasePolicy {
        FileCasePolicy(rawValue: UserDefaults.standard.string(forKey: setsCasePolicyKey) ?? "") ?? setsCasePolicyDefault
    }
    /// Same as `currentSetsCasePolicy()` above, for the ROM-entry-level key.
    public static func currentRomsCasePolicy() -> FileCasePolicy {
        FileCasePolicy(rawValue: UserDefaults.standard.string(forKey: romsCasePolicyKey) ?? "") ?? romsCasePolicyDefault
    }
}
