// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import Foundation
import Observation
import ROMForgeCore
import UniformTypeIdentifiers

/// Drives the audit workflow for one configured `RomSystem`: scan, review
/// the report, export. Repairing (renaming/moving files) is temporarily
/// disabled at the user's request — ROMForge only scans and reports for
/// now, it never touches a ROM file. Re-enable by flipping
/// `modificationsEnabled`.
/// What kind of information one `LogLine` reports — jensyleo's own request
/// (2026-08-27, "otro rezago de fase 1"), extending the original
/// error-only red highlight (2026-08-17) into a full set: `.error` stays
/// red, `.warning` is orange (a problem that doesn't stop the operation —
/// a skipped too-deep subfolder, a results-persistence failure that
/// doesn't affect what's on screen), `.success` is green (a whole
/// operation's own completion summary, not every intermediate progress
/// line), and `.info` (the default) is the ordinary progress narration
/// most log lines still are. The color is purely a hint — nothing reads
/// `kind` back to decide behavior.
enum LogLineKind: Sendable {
    case info
    case success
    case warning
    case error
}

/// One line of the Log panel — `kind` picks the text color (see
/// `LogLineKind`).
struct LogLine: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let kind: LogLineKind
}

@Observable
@MainActor
final class LibraryViewModel {
    /// Single switch gating every file-modifying operation. `fix()` checks
    /// this before doing anything, so there's no path to a rename/move even
    /// if the disabled Fix button were somehow triggered anyway. Reads live
    /// from `UserDefaults` (via `ModificationsEnabledSettings`) so toggling
    /// it in Settings takes effect immediately without restart.
    static var modificationsEnabled: Bool { ModificationsEnabledSettings.isEnabled }

    var datHeader: DATHeader?
    var auditReport: AuditReport?
    var isBusy = false
    /// True from the start of a scan until the DAT finishes parsing — a
    /// large MAME DAT can take a noticeable while to load in an unoptimized
    /// build, and without this the overlay/log would misleadingly say
    /// "scanning folders" for a phase that hasn't touched a folder yet.
    var isLoadingDAT = false
    /// True only during the brief up-front byte-count pass
    /// `MAMEListXMLParser` does to learn a total before the real parse
    /// starts — distinct from `isLoadingDAT` alone so the overlay can say
    /// "Counting machines…" instead of a generic "Loading DAT…" for
    /// this specific sub-phase, which has no known total/progress of its
    /// own (it's what produces the total `datLoadProgress` then uses).
    /// (bytesRead, totalBytes) while reading the DAT file off disk, before
    /// any parsing/counting phase even starts — a real full MAME
    /// driver-set DAT is hundreds of MB, and this raw read alone (worse and
    /// less predictable if the file lives under iCloud Drive, like this
    /// app's own ROM folders do) used to show nothing but a bare, generic
    /// spinner with no indication of what was actually happening or how
    /// long it'd take. `nil` once counting/parsing starts or when idle.
    var datFileReadProgress: (read: Int64, total: Int64)?
    var isCountingDATMachines = false
    /// (bytesScanned, totalBytes) during the counting pass itself — used to
    /// give it a real determinate bar instead of a bare spinner, since a
    /// hundreds-of-MB DAT can make even this "cheap" pass take a few real
    /// seconds. `nil` before the first throttled report arrives.
    var datCountingProgress: (scanned: Int, total: Int)?
    /// (machinesParsed, totalMachines) while parsing a MAME `-listxml` DAT
    /// specifically — `nil` for other DAT formats (no progress reported)
    /// or once parsing finishes.
    var datLoadProgress: (parsed: Int, total: Int)?
    /// Running count of files found so far while walking the folder tree —
    /// `nil` once hashing starts (`scanProgress` takes over) or when idle.
    /// There's no known total during enumeration, so this is a live count
    /// rather than a determinate bar, but it's real feedback where before
    /// there was total silence for however long the folder walk itself took.
    var folderScanFilesFound: Int?
    /// Which of the system's ROM folders (or single forced-rescan file) the
    /// walk is currently inside — jensyleo's own request (2026-08-12): with
    /// several folders (especially via "Scan All Folders"), the running
    /// `folderScanFilesFound` count alone gave no way to tell *which*
    /// folder that count was even coming from. `nil` once the walk phase
    /// ends (hashing/matching progress takes over instead) or when idle.
    var currentlyScanningFolder: URL?
    /// (archivesRead, totalArchives) while `CollectionHasher` reads each
    /// zip's central directory, before any hashing progress exists — `nil`
    /// once hashing starts or when idle. Fills what used to be a silent gap
    /// between "files found on disk" and the first "Hashing X of Y" update,
    /// which for many/large archives could itself take a long time.
    var archiveListingProgress: (read: Int, total: Int)?
    var scanProgress: ScanProgress?
    /// True from the moment hashing finishes until `ROMMatcher.match`
    /// itself returns — on a large multi-folder MAME system this
    /// comparison-against-the-full-DAT step is a real, separately timed
    /// phase (measured as long as ~13 minutes before this session's own
    /// parallelization fix), but `scanProgress` had nothing to show for it
    /// once hashing hit 100%, so the overlay looked stuck at a complete bar
    /// for however long matching then took. Distinct from `scanProgress`
    /// so the overlay can say something honest ("Comparing against the
    /// database…") instead of a frozen 100% bar.
    var isMatching = false
    /// (gamesProcessed, totalGames) while `ROMMatcher.match` works through
    /// its expensive phase 1 — `nil` while `isMatching` itself is false, or
    /// before the first throttled progress callback arrives. Lets the
    /// overlay show a real determinate bar instead of just a spinner for
    /// however long this phase takes on a large DAT.
    var matchProgress: (completed: Int, total: Int)?
    private(set) var logLines: [LogLine] = []

    /// Which long-running phase the user cancelled, if any — drives a
    /// one-time alert explaining the consequence of stopping partway
    /// (an incomplete/stale audit), since silently leaving the user with a
    /// half-finished report and no explanation would look like a bug
    /// rather than something they chose to do. Set by `cancelCurrentOperation()`
    /// based on what's visibly in progress *at the moment Cancel is
    /// pressed* (the most reliable signal — by the time a `catch` block
    /// runs, `isLoadingDAT` may already have been cleared by whichever
    /// phase was mid-transition), cleared once the alert's been shown.
    enum CancelledPhase {
        case datLoad
        case hashing
    }
    var cancelledPhase: CancelledPhase?
    /// The in-flight `scan`/`preloadDAT` operation, if any — cancelling it
    /// only works because both now check `Task.isCancelled`/
    /// `Task.checkCancellation()` cooperatively at several points (DAT
    /// parsing, folder walking, hashing); merely cancelling this handle
    /// wouldn't otherwise interrupt those synchronous, non-`await`ing
    /// stretches of work.
    private var runningTask: Task<Void, Never>?
    /// `scan()`/`preloadDAT()` do their real work inside a `Task.detached`
    /// (to run off the main actor) — a *detached* task is unstructured, so
    /// cancelling `runningTask` (the plain `Task { await scan(...) }`
    /// wrapper awaiting it) does **not** propagate to it automatically.
    /// This closure is set to cancel that specific detached task directly,
    /// which is what actually makes the `Task.checkCancellation()`/
    /// `Task.isCancelled` checks threaded through `DATLoader`/
    /// `FolderScanner`/`FileHasher`/`CollectionHasher` see it.
    private var cancelDetachedWork: (@Sendable () -> Void)?
    /// Real bug found live by jensyleo (2026-08-04): cancelling
    /// `runningTask`/`cancelDetachedWork` above showed the cancellation
    /// warning immediately, but `scan()` kept running all the way to
    /// completion regardless — `ROMMatcher`'s own slowest phase
    /// (`computePerGameCandidates`, often multiple minutes on a full MAME
    /// DAT) dispatches its work onto raw `DispatchQueue.concurrentPerform`
    /// GCD threads, which are never "inside" any `Task` at all, so
    /// `Task.isCancelled` there always reads `false` no matter what — see
    /// `CancellationFlag`'s own doc comment. Set fresh at the start of each
    /// `scan()` (there's only ever one in flight at a time — `startScan`
    /// already cancels any previous `runningTask` first) and threaded
    /// straight into `ROMMatcher.match`; `cancelCurrentOperation()` below
    /// signals it directly, independent of `Task` cancellation entirely.
    private var matchCancellationFlag: CancellationFlag?

    private var matchReport: MatchReport?

    /// What scope the MOST RECENT successful `scan()` actually covered —
    /// jensyleo's own explicit rule (2026-09-10): "si le doy rescan file a
    /// un archivo y le doy fix a otro. Esta acción no debería permitirse" —
    /// confirmed as a deliberately universal, strict rule: the LAST scan is
    /// what applies for Fix purposes, full stop, regardless of what any
    /// EARLIER scan (in the same session) covered. `scan()` itself always
    /// re-matches every folder in one pass and `ScanCache` already
    /// auto-detects a changed file via size+mtime even OUTSIDE a scoped
    /// scan's own forced-rehash set (see `scan()`'s own doc comment) — so
    /// this gate is a deliberate workflow safeguard on top of that, not a
    /// patch for an actual data-correctness gap. `nil` means no successful
    /// scan yet this session; `fix()`/`renameRomsInArchive()` already
    /// refuse separately via `requireMatchReport()` in that case.
    private enum ScanScope: Equatable {
        case wholeSystem
        case paths([URL])
    }
    private var lastScanScope: ScanScope?

    /// Whether `scopeFolders` (a Fix action's own target — empty means "the
    /// whole system") is fully covered by `lastScanScope`. A scoped last
    /// scan can only ever cover a scoped Fix whose every target path falls
    /// inside one of the scanned paths (`Self.urlIsInScope`'s own
    /// prefix/equality test) — never a whole-system Fix, and never a Fix
    /// target the last scan simply never touched.
    private func scopeCoveredByLastScan(_ scopeFolders: [URL]) -> Bool {
        switch lastScanScope {
        case .none: return false
        case .wholeSystem: return true
        case .paths(let scannedPaths):
            guard !scopeFolders.isEmpty else { return false }
            return scopeFolders.allSatisfy { Self.urlIsInScope($0, scopeFolders: scannedPaths) }
        }
    }

    /// A user-facing refusal for `scopeCoveredByLastScan` failing — logged
    /// instead of running `fix()`/`renameRomsInArchive()` on possibly-stale
    /// data the user hasn't actually re-looked-at since their last, more
    /// targeted Scan.
    private func logRescanRequiredForFix(scopeFolders: [URL]) {
        let message = "Rescan required\(Self.scopeSuffixForLog(scopeFolders)) — the last Scan didn't cover this scope. Rescan it, then try Fix again."
        logError(message)
        // jensyleo's own decision (2026-09-10): a log line alone is easy to
        // miss (same reasoning `scanRequiredAlertIsPresented` was added
        // for) — a visible alert on click makes the block impossible to
        // overlook, without hiding the Fix option itself (which would read
        // as a mystery disappearance, same complaint that already happened
        // once with "Fix Mismatched File").
        rescanRequiredAlertMessage = message
    }
    /// Set by `requireMatchReport()` below whenever a write action is
    /// attempted without a live `matchReport` — `true` only once a REAL
    /// scan has run THIS session. Deliberately distinct from
    /// `auditReport != nil`: `loadPersistedReport(system:)` restores
    /// `auditReport` from a PAST session's saved results the moment a
    /// previously-scanned system is opened (so its rows show immediately),
    /// but there's no serialized form of `matchReport` to restore alongside
    /// it — every write action actually operates on `matchReport`, not
    /// `auditReport`. Every Fix button stays enabled once `auditReport`
    /// exists (deliberately NOT also gated on this — a silently-disabled
    /// button explains nothing), so `LibraryDetailView` binds an `.alert`
    /// to this instead of the Log panel, which was too easy to miss.
    /// jensyleo's own reports (2026-09-09): first, that a "Scan first."
    /// log line went unnoticed after opening an already-scanned system;
    /// then, once that got fixed by disabling the buttons instead, that a
    /// disabled button with no explanation "no es intuitivo" either — a
    /// visible message on click is what actually resolves both.
    var scanRequiredAlertIsPresented = false

    /// Non-nil while the "Rescan Required" alert should be showing — set by
    /// `logRescanRequiredForFix` alongside its own Log line, same
    /// "message on click, not just a log line nobody was watching" reasoning
    /// as `scanRequiredAlertIsPresented` right above (jensyleo's own
    /// decision, 2026-09-10: "aparte del mensaje de log muestra una ventana
    /// emergente"). Carries the actual text (unlike the plain `Bool` above)
    /// because which File(s)/scope weren't covered by the last Scan varies
    /// per call, and a fixed alert title can't say that on its own.
    var rescanRequiredAlertMessage: String?

    /// Every Fase 2 write action needs a live `matchReport` before doing
    /// anything — this centralizes that guard so each action gets the same
    /// user-visible alert (not just a log line) rather than repeating the
    /// same `guard let matchReport else { ... }` with slightly different
    /// wording twenty separate times (both a preview-count function and
    /// its own execute function need this check).
    private func requireMatchReport() -> MatchReport? {
        guard let matchReport else {
            scanRequiredAlertIsPresented = true
            return nil
        }
        return matchReport
    }

    /// Side-effect-free peek at whether a real scan has run this session —
    /// jensyleo's own bug report (2026-09-10), screenshot of "Scan Required"
    /// popping up from a plain RIGHT-CLICK on a row, before Fix was even
    /// asked for: `LibraryDetailView`'s own context menus call
    /// `planFixPreviewCount`/`planRenameRomsInArchivePreviewCount` just to
    /// decide whether to SHOW a Fix button at all — but both go through
    /// `requireMatchReport()`, whose whole job is to trigger the "Scan
    /// Required" alert as a SIDE EFFECT when there's no `matchReport` yet
    /// (only a persisted `auditReport` from a past session, which shows
    /// real rows on screen without a live scan). SwiftUI evaluates a
    /// context menu's content closure just from opening the menu, so
    /// merely right-clicking a row was enough to alert. Callers building a
    /// menu (not attempting a real Fix) must check this FIRST and skip
    /// calling any `planXPreviewCount` function entirely when it's `false`,
    /// rather than let one of them alert on their behalf.
    var hasMatchReport: Bool { matchReport != nil }
    /// The last DAT successfully parsed, keyed by its file's URL — a real
    /// MAME DAT can take over a minute to parse in an unoptimized build,
    /// and it almost never changes between one scan and the next of the
    /// *same* system, so re-parsing it from scratch every single Scan (as
    /// this used to do) wasted that entire minute repeatedly for no
    /// reason. Re-parsed whenever `system.datURL`, `mergeMode`, or
    /// `biosMergeMode` changes (a different system, the same system
    /// pointed at a new DAT file, or its merge-mode setting changed) —
    /// each affects the actual games/roms `DATLoader.load` produces, so a
    /// cache keyed on URL alone would silently serve a DAT built under the
    /// wrong mode.
    private struct DATCacheKey: Equatable {
        let url: URL
        let mergeMode: SetMergeMode
        let biosMergeMode: SetMergeMode
    }
    private var cachedDATKey: DATCacheKey?

    /// Shared across every `LibraryViewModel` instance, keyed by system —
    /// jensyleo's own report (2026-08-03): "Loading DAT…" was flashing
    /// seemingly at random. Root cause: `LibraryDetailView` is given
    /// `.id(system.id)` (`ContentView.swift`), so switching to another
    /// system and back tears down and recreates its `LibraryViewModel`
    /// from scratch — including the instance-level `cachedDATKey`/
    /// `cachedDATFile` above, which only ever lived for as long as one
    /// particular `LibraryViewModel` did. Every re-visit therefore looked
    /// exactly like the first time to `preloadDAT`, which unconditionally
    /// flipped `isLoadingDAT = true` and went through the (real, visible)
    /// disk-cache-decode path — for a DAT that, from the user's
    /// perspective, only just finished loading moments earlier. This
    /// `static` cache survives that teardown/recreation, so re-visiting
    /// the *same* system with unchanged settings hits it immediately, with
    /// no loading UI at all — the disk cache (`DATFileCache`) stays as the
    /// fallback for the *first* visit each app launch, or after a real
    /// change.
    private static var sharedDATCache: [UUID: (key: DATCacheKey, file: DATFile)] = [:]

    /// A DAT file's identity for the purpose of deciding whether a cached
    /// *raw parse* (`ParsedDAT`, mode-independent) still applies — its own
    /// (size, mtime), deliberately WITHOUT `mergeMode`/`biosMergeMode` at
    /// all, unlike `DATCacheKey` above. That's the entire point: the same
    /// parse serves every mode.
    private struct RawDATIdentity: Equatable {
        let url: URL
        let sourceSize: Int64
        let sourceModificationDate: Date
    }

    /// Shared across every `LibraryViewModel` instance, keyed by system,
    /// same rationale as `sharedDATCache` just above (survives a
    /// `LibraryDetailView.id(system.id)` teardown/recreation) — but this one
    /// caches the (slow) raw *parse* independently of Rom/Bios merge mode,
    /// rather than the (fast, mode-dependent) final `DATFile` derived from
    /// it.
    ///
    /// jensyleo's own request (2026-08-11), after reporting that switching
    /// Rom/Bios merge mode mid-session re-triggered the full, slow DAT
    /// reload: measured separately against a real MAME 0.288 dump (50,097
    /// machines) — the raw XML parse alone takes ~9.4s, while re-deriving a
    /// `DATFile` from an already-parsed dataset under a different mode
    /// takes ~0.2-0.9s (see `ParsedDAT`/`DATLoader.build(from:mergeMode:biosMergeMode:)`'s
    /// own doc comments in Core for the full reasoning and numbers). Before
    /// this cache existed, `DATFileCache` (the on-disk cache of the final,
    /// mode-baked `DATFile`) was the ONLY cache in the whole chain, and it's
    /// keyed by mode too — so changing mode was a guaranteed miss there AND
    /// nowhere else remembered the expensive part (the parse) independently
    /// of it, forcing a full ~9.4s re-parse for a file that hadn't changed
    /// by a single byte. This cache is what lets `loadDAT` skip straight to
    /// the cheap derivation step instead.
    ///
    /// `Optional` `ParsedDAT` at the call site (not stored) rather than a
    /// non-optional value here: `loadDAT` only returns a fresh one to store
    /// when it genuinely had to parse — a `DATFileCache` (final-`DATFile`)
    /// hit skips parsing entirely and has no raw dataset to offer, so this
    /// dictionary simply keeps whatever it already had (possibly nothing
    /// yet, until the first real parse this session) rather than being
    /// overwritten with nothing.
    private static var sharedRawDatasetCache: [UUID: (identity: RawDATIdentity, parsed: ParsedDAT)] = [:]

    /// Backs the in-memory cache above with a disk-persisted one
    /// (`DATFileCache`) — the in-memory cache only lives for as long as this
    /// `LibraryViewModel` does, so it's already empty again on every fresh
    /// app launch, and `preloadDAT`/`scan` would otherwise silently re-parse
    /// the same DAT from scratch every single time the app opens even
    /// though nothing about it changed. Runs off the main actor (called
    /// from inside a `Task.detached`), so it only touches `FileManager`/
    /// `DATFileCache`, never `self`.
    /// `reusableParsed` is the caller's own `sharedRawDatasetCache` entry
    /// for this system, passed in (rather than read from the `static var`
    /// directly here) so every touch of that dictionary stays on the main
    /// actor — this function itself runs detached, and reading/writing a
    /// plain `static var` from a genuinely concurrent context is exactly
    /// the kind of data race Swift's strict concurrency checking exists to
    /// catch. Returning the freshly-parsed `ParsedDAT` (when one had to
    /// happen at all — see `sharedRawDatasetCache`'s own doc comment for
    /// when it doesn't) lets the caller store it back the same safe way.
    private nonisolated static func loadDAT(
        datURL: URL,
        mergeMode: SetMergeMode,
        biosMergeMode: SetMergeMode,
        diskCacheURL: URL,
        reusableParsed: (identity: RawDATIdentity, parsed: ParsedDAT)?,
        onFileReadProgress: @escaping @Sendable (Int64, Int64) -> Void,
        onCountingStarted: @escaping @Sendable () -> Void,
        onCountingProgress: @escaping @Sendable (Int, Int) -> Void,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) throws -> (dat: DATFile, freshlyParsed: ParsedDAT?, identity: RawDATIdentity) {
        let attributes = try FileManager.default.attributesOfItem(atPath: datURL.path)
        let sourceSize = (attributes[.size] as? Int64) ?? Int64((attributes[.size] as? Int) ?? 0)
        let sourceModificationDate = (attributes[.modificationDate] as? Date) ?? Date.distantPast
        let identity = RawDATIdentity(url: datURL, sourceSize: sourceSize, sourceModificationDate: sourceModificationDate)
        // Fastest path: the final, mode-baked `DATFile` itself is still
        // valid — nothing to parse OR derive at all.
        if let cached = try? DATFileCache.load(contentsOf: diskCacheURL),
           cached.isValid(sourceSize: sourceSize, sourceModificationDate: sourceModificationDate, mergeMode: mergeMode, biosMergeMode: biosMergeMode) {
            return (cached.dat, nil, identity)
        }
        // Second-fastest: the mode changed (or this is the very first
        // request this session for a mode not yet cached on disk), but the
        // raw file itself is byte-identical to a parse already sitting in
        // memory — skip straight to the cheap, mode-dependent derivation.
        if let reusableParsed, reusableParsed.identity == identity {
            let dat = try DATLoader.build(from: reusableParsed.parsed, mergeMode: mergeMode, biosMergeMode: biosMergeMode)
            try? DATFileCache(sourceSize: sourceSize, sourceModificationDate: sourceModificationDate, mergeMode: mergeMode, biosMergeMode: biosMergeMode, dat: dat).save(to: diskCacheURL)
            return (dat, nil, identity)
        }
        // Cold path: genuinely nothing to reuse — parse for real.
        let parsed = try DATLoader.parse(
            contentsOf: datURL,
            onFileReadProgress: onFileReadProgress, onCountingStarted: onCountingStarted, onCountingProgress: onCountingProgress, onProgress: onProgress
        )
        let dat = try DATLoader.build(from: parsed, mergeMode: mergeMode, biosMergeMode: biosMergeMode)
        try? DATFileCache(sourceSize: sourceSize, sourceModificationDate: sourceModificationDate, mergeMode: mergeMode, biosMergeMode: biosMergeMode, dat: dat).save(to: diskCacheURL)
        return (dat, parsed, identity)
    }
    /// The most recently loaded/scanned DAT — not `private` so the detail
    /// view can browse the DAT's own game catalog (`preloadedGames`) as
    /// soon as it's loaded, before the user has ever pressed "Scan Folder".
    /// Database browsing shouldn't depend on having scanned a ROM folder
    /// (a real bug — see `CHANGELOG.md`), and this is what lets it not.
    var cachedDATFile: DATFile?
    /// `cachedDATFile.games`, or empty before any DAT has loaded — the
    /// catalog `LibraryDetailView` shows under "Database" once a DAT is
    /// loaded but no scan has run yet.
    var preloadedGames: [DATGame] { cachedDATFile?.games ?? [] }

    /// Hard cap on how many lines the Log panel keeps at once — jensyleo's
    /// own request (2026-09-11): "al log ponerle un limite, para evitar
    /// desborde." A single "Scan All Folders" against a large real
    /// collection can genuinely produce thousands of lines (one per
    /// folder walked, one per archive-listing batch, etc.); left
    /// unbounded across an entire session, that's an ever-growing
    /// `[LogLine]` array (and the `NSTextView` rebuilt from it — see
    /// `LogTextView`'s own doc comment) with no ceiling at all.
    static let maxLogLines = 2000

    func log(_ message: String, kind: LogLineKind = .info) {
        let timestamp = DateFormatter.logTimestamp.string(from: Date())
        logLines.append(LogLine(text: "[\(timestamp)] \(message)", kind: kind))
        if logLines.count > Self.maxLogLines {
            logLines.removeFirst(logLines.count - Self.maxLogLines)
        }
    }

    /// "Copy Log" (`LibraryDetailView.copyLogToClipboard`) already covers
    /// getting everything out before it's gone — jensyleo's own request
    /// (2026-09-11) for a way to explicitly start fresh without needing
    /// to run a whole new scan (which already clears it as a side effect
    /// — see `scan(system:folders:)`'s own `logLines.removeAll()`).
    func clearLog() {
        logLines.removeAll()
    }

    /// Convenience for the (much rarer) error case — same timestamped
    /// format as `log(_:)`, just flagged so the Log panel can render it in
    /// red. jensyleo's own request (2026-08-17): an error (e.g. MAME
    /// failing to launch a game) belongs in the Log panel like everything
    /// else this view model reports, not in a separate modal — the Log
    /// panel is "where by logic it should appear." Not `private` — the App
    /// layer (`LibraryDetailView`) reports MAME's own launch failures
    /// through this too, not just this file's own scan/fix code.
    func logError(_ message: String) {
        log(message, kind: .error)
    }

    /// Convenience for a problem that doesn't stop the operation it
    /// happened during (a skipped too-deep subfolder, a results-save that
    /// failed even though the scan itself succeeded) — orange, distinct
    /// from both the ordinary `.info` narration and a real `.error`.
    func logWarning(_ message: String) {
        log(message, kind: .warning)
    }

    /// Convenience for a whole operation's own completion summary (a
    /// finished scan, a clean integrity check) — green, deliberately not
    /// used for every intermediate progress line, only the "this whole
    /// thing is done, and done well" moment.
    func logSuccess(_ message: String) {
        log(message, kind: .success)
    }

    /// Drops every in-memory trace of the last scan — jensyleo's own report
    /// (2026-08-12): "Purge Database View" (`ViewOptionsSettingsView`)
    /// cleared the on-disk `AuditReportDatabase` row and `ScanCache` file,
    /// but a `LibraryDetailView` already open at the time kept showing its
    /// existing in-memory `auditReport` regardless — "esto no debería
    /// pasar", correctly, since the whole point of purging was to force a
    /// fresh scan before anything shows again, not just for the *next*
    /// launch. Called from `LibraryDetailView` in response to
    /// `SavedViewStatePurger.scanResultsPurgedNotification` (see that
    /// notification's own doc comment) so an already-open window reflects
    /// the purge immediately, not only once relaunched. `loadPersistedReport`
    /// only ever loads when `auditReport == nil` — clearing it here (not
    /// just leaving the disk row gone) is what lets that guard actually
    /// re-fire usefully if this same session ever calls it again.
    func clearScanResults() {
        auditReport = nil
        datHeader = nil
        matchReport = nil
        lastScanScope = nil
        cachedDATKey = nil
        cachedDATFile = nil
    }

    /// Loads the last persisted audit for `system`, if any, so opening a
    /// previously-scanned system shows its last results immediately instead
    /// of an empty view until the user hits Scan again. A real Scan always
    /// re-derives the truth from disk and overwrites this.
    /// Real slowness found live (2026-08-13, same pass that found
    /// `removeFolder`'s): this read `AuditReportDatabase`'s entire
    /// persisted report for a system — hundreds of thousands of rows for a
    /// real MAME collection, same scale `removeFolder` was fixed for —
    /// synchronously on `@MainActor`, from `LibraryDetailView`'s own
    /// `.onAppear`. That's the single most common path in the whole app:
    /// it fires every time a system is opened/reselected in the sidebar.
    /// Moved onto a detached task, `[weak self]`, same pattern as
    /// `removeFolder`/`loadDAT`'s own progress handlers — the `auditReport
    /// == nil` guard is re-checked once more on the main actor before
    /// assigning, so a scan that finishes (or another call to this same
    /// function) while the read was in flight can never be stomped by a
    /// stale result arriving late.
    func loadPersistedReport(system: RomSystem) {
        guard auditReport == nil else { return }
        let systemID = system.id.uuidString
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let db = try AuditDatabaseLocation.open()
                guard let report = try db.loadReport(systemID: systemID) else { return }
                let meta = try? db.loadScanMeta(systemID: systemID)
                Task { @MainActor in
                    guard let self, self.auditReport == nil else { return }
                    self.auditReport = report
                    if let meta, let name = meta.datName {
                        self.datHeader = DATHeader(name: name, description: "", version: meta.datVersion ?? "", author: "")
                    }
                }
            } catch {
                // A missing/corrupt database just means no cached results to
                // show yet — not worth surfacing as a user-facing error.
            }
        }
    }

    /// Purges everything tied to one removed ROM folder — jensyleo's own
    /// report (2026-07-30): removing a folder used to leave the persisted
    /// audit report and scan cache untouched, so reopening the system (or
    /// even just the "Database" view refreshing) still showed that
    /// folder's old, now-untrue results until a full rescan happened to
    /// overwrite them. Called right when the folder is removed (before
    /// any rescan), not after:
    /// - In-memory `auditReport`: entries whose `path` falls under
    ///   `folderURL` are dropped immediately, so the UI reflects the
    ///   removal on the spot rather than waiting for a rescan.
    /// - Persisted `AuditReportDatabase`: the same pruned report is saved
    ///   back, so relaunching the app (or reselecting this system) doesn't
    ///   resurrect the old data from disk.
    /// - `ScanCache`: dropped entirely for this system rather than
    ///   surgically pruned — `ScanCache`'s own keys aren't structured for
    ///   cheap prefix-removal, and losing the cache benefit for the
    ///   system's *other*, unaffected folders until the next scan is a
    ///   fair trade for correctness on what's an infrequent action.
    /// Real slowness reported live by jensyleo (2026-08-13, testing with a
    /// larger real collection, twice in a row):
    /// 1. First found doing the in-memory filter AND a full
    ///    `saveReport` rewrite (`DELETE`+re-`INSERT` of every SURVIVING
    ///    row too, not just the removed ones — hundreds of thousands of
    ///    them for a real MAME system) synchronously on `@MainActor`,
    ///    directly from the button click.
    /// 2. Moving that whole thing into a background task ("eliminar los
    ///    folders sigue igual" [de lento], reported right after) didn't
    ///    actually fix the *feel* of it — the total wall-clock work was
    ///    unchanged, just no longer freezing the main thread, so the visible
    ///    list still took just as long to update.
    ///
    /// Real fix, in two parts:
    /// - The in-memory filter+recount is genuinely cheap (a single O(n)
    ///   pass over already-in-memory structs, no I/O) — kept synchronous,
    ///   right here, so `auditReport` updates and the UI reflects the
    ///   removal *instantly*, the same way it did before any of this was
    ///   ever a problem.
    /// - The actually-slow part was never the filter — it was
    ///   `saveReport` rewriting every unrelated surviving row just to drop
    ///   one folder's worth. `AuditReportDatabase.removeEntries(systemID:
    ///   pathPrefix:)` (new) deletes only the rows that need to go and
    ///   touches nothing else — genuinely fast regardless of how large the
    ///   rest of the system's report is. That part still runs in the
    ///   background (it's real disk I/O, and its own result — whether it
    ///   succeeded — has no bearing on what the UI already shows), but it
    ///   no longer needs to finish before the visible list updates.
    func removeFolder(_ folderURL: URL, system: RomSystem) {
        ScanCacheLocation.remove(for: system)
        guard let previous = auditReport else { return }
        // Trailing slash added deliberately — a bare `hasPrefix` on
        // `URL.path` (no trailing slash) would also match a *sibling*
        // folder whose name happens to start with this one's, e.g.
        // removing "CPS1" would wrongly sweep up "CPS10"'s entries too.
        // Pre-existing edge case, spotted while touching this exact
        // comparison for the I/O fix below — fixed here since it's the
        // same line.
        let folderPath = folderURL.path.hasSuffix("/") ? folderURL.path : folderURL.path + "/"
        let prunedEntries = previous.entries.filter { entry in
            guard let path = entry.path else { return true }
            return !path.path.hasPrefix(folderPath)
        }
        guard prunedEntries.count != previous.entries.count else { return }
        var correct = 0, incorrect = 0, badDump = 0, missing = 0, surplus = 0, unverifiable = 0, duplicateSets = 0
        for entry in prunedEntries {
            switch entry.status {
            case .correct: correct += 1
            case .incorrect: incorrect += 1
            case .badDump: badDump += 1
            case .missing: missing += 1
            case .surplus, .surplusInArchive, .unknownFile: surplus += 1
            case .unverifiable: unverifiable += 1
            case .duplicateSet: duplicateSets += 1
            }
        }
        auditReport = AuditReport(entries: prunedEntries, correct: correct, incorrect: incorrect, badDump: badDump, missing: missing, surplus: surplus, unverifiable: unverifiable, duplicateSets: duplicateSets)

        let systemID = system.id.uuidString
        Task.detached(priority: .utility) { [weak self] in
            do {
                try AuditDatabaseLocation.open().removeEntries(systemID: systemID, pathPrefix: folderPath)
            } catch {
                Task { @MainActor in
                    self?.logWarning("Couldn't persist the folder removal: \(error)")
                }
            }
        }
    }

    /// Starts (or restarts) scanning `system` as a cancellable operation —
    /// the `Task` handle is kept so `cancelCurrentOperation()` has
    /// something to actually cancel. Fire-and-forget from the UI's
    /// perspective (a plain, non-`async` call), same as tapping a button
    /// always was.
    func startScan(system: RomSystem, folders: [URL]? = nil) {
        runningTask?.cancel()
        runningTask = Task { await scan(system: system, folders: folders) }
    }

    /// Starts DAT preloading as a cancellable operation — see `startScan`.
    /// Guarded by `preloadDAT` itself already being a no-op when busy or
    /// already cached, so this is safe to call opportunistically (e.g. from
    /// `onAppear`) without checking state first.
    func startPreloadDAT(system: RomSystem) {
        runningTask = Task { await preloadDAT(system: system) }
    }

    /// Cancels whichever scan/DAT-load is currently running, recording
    /// *which* phase was interrupted (read from current state before
    /// cancelling, the only reliable moment to know) so the UI can explain
    /// the consequence: no DAT loaded means nothing can be audited yet; an
    /// interrupted hash means the resulting report is incomplete/stale for
    /// whatever wasn't reached.
    func cancelCurrentOperation() {
        guard isBusy else { return }
        cancelledPhase = (isLoadingDAT || isCountingDATMachines) ? .datLoad : .hashing
        cancelDetachedWork?()
        matchCancellationFlag?.cancel()
        runningTask?.cancel()
    }

    /// Loads (and caches) `system`'s DAT on its own, independent of
    /// scanning any folder — called as soon as a system's DAT/folders are
    /// available (right when its detail view first appears), so the DAT is
    /// already parsed and cached by the time the user actually presses
    /// "Scan Folder". Before this, loading the DAT only ever happened as
    /// the first phase of a real scan, meaning it silently depended on
    /// folder scanning happening at all — selecting a system and DAT did
    /// nothing on its own. A no-op if the DAT for this exact URL is
    /// already cached, or if something else (a real scan) is already busy.
    func preloadDAT(system: RomSystem) async {
        let mergeMode = MAMEMergeModeSettings.current
        let biosMergeMode = MAMEMergeModeSettings.currentBios
        let key = DATCacheKey(url: system.datURL, mergeMode: mergeMode, biosMergeMode: biosMergeMode)
        guard !isBusy, cachedDATKey != key else { return }
        if let shared = Self.sharedDATCache[system.id], shared.key == key {
            cachedDATKey = key
            cachedDATFile = shared.file
            datHeader = shared.file.header
            return
        }
        // jensyleo's own report (2026-08-03): why does changing Rom merge
        // mode always reload the whole DAT? For a system confirmed to have
        // zero clone games anywhere (`system.hasClones == false` —
        // `RomSystem.hasClones`'s own doc comment), it provably doesn't
        // need to: `MAMESetLayoutPlanner`'s own no-op fix plus
        // `ROMMatcher`'s per-game `strictOwnArchiveOnly` gating (both fixed
        // the same day, for the same underlying reason) mean Rom merge
        // mode literally cannot change this DAT's output when no game in
        // it has a clone/parent relationship for it to act on — only Bios
        // merge mode still can (BIOS folding is a separate, real axis).
        // Whenever only `mergeMode` differs from what's already cached
        // (same DAT file, same Bios merge mode) on such a system, the
        // already-cached `DATFile` is reused outright instead of a real
        // reload — cheap, and correct because the *output* would be
        // identical anyway.
        if system.hasClones == false, let cachedDATFile, let cachedDATKey,
           cachedDATKey.url == key.url, cachedDATKey.biosMergeMode == key.biosMergeMode {
            self.cachedDATKey = key
            Self.sharedDATCache[system.id] = (key, cachedDATFile)
            return
        }
        isBusy = true
        isLoadingDAT = true
        datLoadProgress = nil
        logLines.removeAll()
        defer { isBusy = false }

        log("Loading DAT for \(system.name)…")
        let datURL = system.datURL
        let fileReadProgressHandler: @Sendable (Int64, Int64) -> Void = { [weak self] read, total in
            Task { @MainActor in self?.datFileReadProgress = (read, total) }
        }
        let countingStartedHandler: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                self?.datFileReadProgress = nil
                self?.isCountingDATMachines = true
            }
        }
        let countingProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] scanned, total in
            Task { @MainActor in self?.datCountingProgress = (scanned, total) }
        }
        let datLoadProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] parsed, total in
            Task { @MainActor in
                self?.isCountingDATMachines = false
                self?.datCountingProgress = nil
                self?.datLoadProgress = (parsed, total)
            }
        }
        let diskCacheURL = DATCacheLocation.url(for: system)
        // Read on the main actor, passed into the detached task rather than
        // read from inside it — see `loadDAT`'s own doc comment for why.
        let reusableParsed = Self.sharedRawDatasetCache[system.id]
        do {
            let datLoadStart = Date()
            let detached = Task.detached(priority: .userInitiated) {
                try Self.loadDAT(
                    datURL: datURL, mergeMode: mergeMode, biosMergeMode: biosMergeMode, diskCacheURL: diskCacheURL,
                    reusableParsed: reusableParsed,
                    onFileReadProgress: fileReadProgressHandler, onCountingStarted: countingStartedHandler, onCountingProgress: countingProgressHandler, onProgress: datLoadProgressHandler
                )
            }
            cancelDetachedWork = { detached.cancel() }
            let result = try await detached.value
            let dat = result.dat
            cachedDATKey = key
            cachedDATFile = dat
            datHeader = dat.header
            Self.sharedDATCache[system.id] = (key, dat)
            if let freshlyParsed = result.freshlyParsed {
                Self.sharedRawDatasetCache[system.id] = (result.identity, freshlyParsed)
            }
            isLoadingDAT = false
            datFileReadProgress = nil
            isCountingDATMachines = false
            datCountingProgress = nil
            datLoadProgress = nil
            log(String(format: "Loaded DAT in %.1fs — ready to scan.", Date().timeIntervalSince(datLoadStart)))
        } catch is CancellationError {
            isLoadingDAT = false
            datFileReadProgress = nil
            isCountingDATMachines = false
            datCountingProgress = nil
            datLoadProgress = nil
            logWarning("DAT loading cancelled.")
        } catch {
            isLoadingDAT = false
            datFileReadProgress = nil
            isCountingDATMachines = false
            datCountingProgress = nil
            datLoadProgress = nil
            logError("Failed to load DAT: \(String(describing: error))")
        }
    }

    /// Scans `system`'s ROM folders and rebuilds the audit — by default,
    /// every configured folder (`folders: nil`, "Scan All Folders").
    /// Passing a subset ("Scan Folder" on one folder, "Scan File"/"Rescan
    /// This File" on one archive) genuinely restricts disk access to just
    /// that subset — jensyleo's own request (2026-09-11) that the three
    /// actually behave differently, after a stretch (2026-08-06, see the
    /// history in this function's own body below) where every one of them
    /// walked and matched the ENTIRE system regardless of what was asked
    /// for, to sidestep a real class of cross-folder reconciliation bugs.
    /// Genuine separation returns here without reopening that class of
    /// bug: the matcher still always sees every folder's files at once
    /// (never a partial, blind subset) — a scoped scan just sources
    /// everything OUTSIDE its own scope from `ScanCache` (already on
    /// disk, no fresh read) instead of a fresh walk, rather than actually
    /// not looking at it at all. See `ScanCache.reconstructedHashedFiles()`'s
    /// own doc comment for exactly how.
    func scan(system: RomSystem, folders: [URL]? = nil) async {
        isBusy = true
        // A cache hit skips the whole "Loading DAT" phase outright — there's
        // nothing to show progress for, and no point pretending otherwise.
        let datCacheKey = DATCacheKey(url: system.datURL, mergeMode: MAMEMergeModeSettings.current, biosMergeMode: MAMEMergeModeSettings.currentBios)
        let reusableDAT: DATFile? = (cachedDATKey == datCacheKey) ? cachedDATFile : nil
        isLoadingDAT = reusableDAT == nil
        datFileReadProgress = nil
        isCountingDATMachines = false
        datCountingProgress = nil
        datLoadProgress = nil
        scanProgress = nil
        isMatching = false
        matchProgress = nil
        folderScanFilesFound = nil
        currentlyScanningFolder = nil
        archiveListingProgress = nil
        let cancellationFlag = CancellationFlag()
        matchCancellationFlag = cancellationFlag
        logLines.removeAll()
        defer { isBusy = false }

        let scanStart = Date()
        // ─── History (kept for whoever touches this next) ──────────────
        // 2026-08-06: scoped scans used to hand `ROMMatcher` only the
        // selected folder's OWN files, then reconcile that partial result
        // against the previous report afterward. That reconciliation was
        // inherently guesswork: a matcher that can't see the other
        // folders cannot know that `ghouls.zip` also sits in one of them,
        // so it claimed whichever copy it was shown and the merge step
        // had to decide, blind, what to keep — producing the
        // game-vanishes-from-the-other-folder flip-flop (TESTING.md §9.2
        // scenario #4) and three earlier live-found bugs before it. The
        // fix at the time: make EVERY scan walk and match EVERY folder,
        // always, regardless of what was actually asked for — scope would
        // only control what got force-rehashed vs served from
        // `ScanCache`, never what got matched. Real measurements
        // (jensyleo's own collection, 5 folders, 161 archives, ~1.8 GB,
        // MAME 0.288 → 50,097 games) showed this was affordable: hashing
        // cold (408.7s) dwarfs matching everything (11.3s) by ~35×, so
        // the always-walk-everything cost was mostly hidden behind
        // `ScanCache` doing its job on the unchanged 99% of files anyway.
        //
        // 2026-09-11: jensyleo's own follow-up report — "Scan Folder"
        // reading, in the Log, as indistinguishable from "Scan All
        // Folders" (every configured folder announced "Scanning X…"
        // regardless of scope) was worse than the 2026-08-06 fix was
        // worth, and explicitly asked to set that call aside: "olvida lo
        // de mi decisión... separa los diferentes tipos de escaneo."
        // Genuine separation returns below WITHOUT reopening the
        // reconciliation bug this whole history is about: the matcher
        // still always sees every folder's files in one call — a scoped
        // scan just sources everything outside its own scope from
        // `ScanCache` (see `reconstructedHashedFiles()`) rather than a
        // blind, partial subset with nothing known about the rest at all.
        // ─────────────────────────────────────────────────────────────
        let allFolders = system.romFolderURLs
        // Paths the user explicitly asked to re-read ("Scan Folder" on one
        // folder, "Rescan This File" on one archive) — their cached hashes
        // are dropped so they're genuinely rehashed even if size+mtime are
        // unchanged, which is the whole point of asking.
        // Reviewed 2026-09-10 at jensyleo's own request (take the now-working
        // scan separation as the Fase 1 reference): the old test also
        // required `folders != allFolders`, which silently collapsed the
        // one real case where the two are equal — a system with exactly ONE
        // configured folder, selected — back onto the unscoped path. Same
        // walk either way, but the cache was then NOT dropped for it, so
        // "Scan Folder" quietly lost its force-rehash guarantee on the very
        // files the user explicitly asked to re-read (a copy tool that
        // preserves size+mtime is exactly why that guarantee exists). What
        // makes a scan scoped is that a scope was PASSED, nothing else.
        let forcedRescanPaths = folders ?? []
        log(
            forcedRescanPaths.isEmpty
                ? "Scanning \(system.name) (\(allFolders.count) folder\(allFolders.count == 1 ? "" : "s"))…"
                : "Reading only \(forcedRescanPaths.map(\.lastPathComponent).joined(separator: ", ")) from disk — the other \(max(allFolders.count - forcedRescanPaths.count, 0)) folder(s) keep their last known results…"
        )

        do {
            let datURL = system.datURL
            // Read on the main actor (both a plain `UserDefaults`-backed
            // global setting — see `MAMEMergeModeSettings` — and an
            // `@AppStorage`-backed one, below), then captured as plain
            // values the detached task can use without touching
            // `UserDefaults` off the main actor.
            let mergeMode = MAMEMergeModeSettings.current
            let biosMergeMode = MAMEMergeModeSettings.currentBios
            // Read on the main actor (an `@AppStorage`-backed, app-wide
            // preference — see `GeneralSettingsView`), then captured as a
            // plain value the detached task below can use without
            // touching `UserDefaults` off the main actor.
            let hashAlgorithms = HashAlgorithmSettings.current
            let cacheURL = ScanCacheLocation.url(for: system)
            let datDiskCacheURL = DATCacheLocation.url(for: system)
            // Read on the main actor, passed into the detached task rather
            // than read from inside it — see `loadDAT`'s own doc comment
            // for why.
            let reusableParsed = Self.sharedRawDatasetCache[system.id]
            let fileReadProgressHandler: @Sendable (Int64, Int64) -> Void = { [weak self] read, total in
                Task { @MainActor in self?.datFileReadProgress = (read, total) }
            }
            let countingStartedHandler: @Sendable () -> Void = { [weak self] in
                Task { @MainActor in
                    self?.datFileReadProgress = nil
                    self?.isCountingDATMachines = true
                }
            }
            let countingProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] scanned, total in
                Task { @MainActor in self?.datCountingProgress = (scanned, total) }
            }
            let datLoadProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] parsed, total in
                Task { @MainActor in
                    self?.isCountingDATMachines = false
                    self?.datCountingProgress = nil
                    self?.datLoadProgress = (parsed, total)
                }
            }
            let folderProgressHandler: @Sendable (Int) -> Void = { [weak self] count in
                Task { @MainActor in self?.folderScanFilesFound = count }
            }
            let folderStartedHandler: @Sendable (URL) -> Void = { [weak self] url in
                Task { @MainActor in
                    self?.currentlyScanningFolder = url
                    // jensyleo's own report (2026-08-12): the overlay's own
                    // "Scanning <folder>…" text flashed by too fast to
                    // read — walking a folder tree (just listing files, no
                    // hashing yet) is fast enough on most collections that
                    // the phase can be over before a human eye catches it,
                    // especially for a small/already-cached folder. The Log
                    // panel doesn't have that problem: every line stays put
                    // once written, so this is where the per-folder record
                    // actually survives to be read, even for a folder whose
                    // own walk took under a second.
                    //
                    // jensyleo's own follow-up request (2026-09-11): genuinely
                    // separate "Scan Folder"/"Scan File" from "Scan All
                    // Folders" — this handler only ever fires for a URL
                    // already inside `pathsToWalk`, which now IS the
                    // requested scope (see this function's own doc comment),
                    // so every call here is on-scope by construction.
                    self?.log("Scanning \(url.lastPathComponent)…")
                }
            }
            // jensyleo's own request (2026-08-05): a subfolder nested past
            // `FolderScanner.maxSubfolderDepth` is skipped, not fatal to the
            // whole scan — logged so it's still visible (rather than
            // silently never-mentioned) that ROMForge never looked inside
            // it at all.
            let skippedTooDeepHandler: @Sendable (URL) -> Void = { [weak self] url in
                Task { @MainActor in self?.logWarning("Skipped (nested too deep, not scanned): \(url.path)") }
            }
            let archiveListedHandler: @Sendable (Int, Int) -> Void = { [weak self] read, total in
                Task { @MainActor in self?.archiveListingProgress = (read, total) }
            }
            let progressHandler: @Sendable (ScanProgress) -> Void = { [weak self] progress in
                Task { @MainActor in
                    // First hashing update means the folder walk and archive
                    // listing pass are both done — clear their live counts
                    // so the overlay/log switch phases.
                    self?.folderScanFilesFound = nil
                    self?.currentlyScanningFolder = nil
                    self?.archiveListingProgress = nil
                    self?.scanProgress = progress
                }
            }
            let walkLogHandler: @Sendable (Int, TimeInterval) -> Void = { [weak self] count, duration in
                Task { @MainActor in
                    self?.log(String(format: "Found %d files on disk in %.1fs — reading archive listings…", count, duration))
                }
            }
            let reconstructionLogHandler: @Sendable (Int, Int) -> Void = { [weak self] fresh, reconstructed in
                Task { @MainActor in
                    self?.log("\(fresh) file(s) read fresh from the selected scope; \(reconstructed) file(s) in other folders reused from the last scan (not re-read).")
                }
            }
            let matchingStartedHandler: @Sendable () -> Void = { [weak self] in
                Task { @MainActor in
                    self?.scanProgress = nil
                    self?.isMatching = true
                    self?.matchProgress = nil
                }
            }
            let matchProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] completed, total in
                Task { @MainActor in
                    self?.matchProgress = (completed, total)
                }
            }
            let datLoadLogHandler: @Sendable (TimeInterval) -> Void = { [weak self] duration in
                Task { @MainActor in
                    self?.isLoadingDAT = false
                    self?.datFileReadProgress = nil
                    self?.isCountingDATMachines = false
                    self?.datCountingProgress = nil
                    self?.datLoadProgress = nil
                    self?.log(String(format: "Loaded DAT in %.1fs — scanning folders…", duration))
                }
            }
            let cachedDATLogHandler: @Sendable () -> Void = { [weak self] in
                Task { @MainActor in self?.log("Using already-loaded DAT — scanning folders…") }
            }
            let detached = Task.detached(priority: .userInitiated) {
                // Auto-detects Logiqx/ClrMamePro XML vs. MAME -listxml. A
                // large MAME DAT is tens/hundreds of MB of XML, and parsing
                // it can itself take long enough in an unoptimized build to
                // look like a hang before the folder walk has even started —
                // worth its own timed log line rather than silently folding
                // into whatever the next phase's message says. Skipped
                // entirely on a cache hit (`reusableDAT`), the whole point
                // of caching it in the first place.
                let dat: DATFile
                var freshlyParsed: ParsedDAT?
                var freshlyParsedIdentity: RawDATIdentity?
                if let reusableDAT {
                    dat = reusableDAT
                    cachedDATLogHandler()
                } else {
                    let datLoadStart = Date()
                    let result = try Self.loadDAT(
                        datURL: datURL, mergeMode: mergeMode, biosMergeMode: biosMergeMode, diskCacheURL: datDiskCacheURL,
                        reusableParsed: reusableParsed,
                        onFileReadProgress: fileReadProgressHandler, onCountingStarted: countingStartedHandler, onCountingProgress: countingProgressHandler, onProgress: datLoadProgressHandler
                    )
                    dat = result.dat
                    freshlyParsed = result.freshlyParsed
                    freshlyParsedIdentity = result.identity
                    datLoadLogHandler(Date().timeIntervalSince(datLoadStart))
                }
                let walkStart = Date()
                // Genuinely scoped now — jensyleo's own request (2026-09-11)
                // to actually separate "Scan Folder"/"Scan File" from "Scan
                // All Folders", after weighing (and then explicitly setting
                // aside) the 2026-08-06 always-walk-everything call above:
                // a real disk walk only ever covers `forcedRescanPaths`
                // when there's a genuine scope, never every folder just to
                // list files nothing asked to see re-read. `paths` (not
                // `folders`) since `FolderScanner.scan(paths:)` handles a
                // whole folder or an individual file per entry.
                let pathsToWalk = forcedRescanPaths.isEmpty ? allFolders : forcedRescanPaths
                let scannedFiles = try FolderScanner.scan(paths: pathsToWalk, onFileFound: folderProgressHandler, onSkippedTooDeep: skippedTooDeepHandler, onFolderStarted: folderStartedHandler)
                walkLogHandler(scannedFiles.count, Date().timeIntervalSince(walkStart))
                let loadedCache = (try? ScanCache.load(contentsOf: cacheURL)) ?? ScanCache()
                // A file whose size/mtime match a previous scan's cache
                // entry is served from there instead of rehashed — a real
                // collection can be tens of thousands of files, most of
                // which never change between scans. `removingEntries(under:)`
                // drops just what this scan is genuinely re-reading, so an
                // explicit "Scan Folder"/"Scan File" always rehashes for
                // real even if size+mtime happen to be unchanged (some copy
                // tools preserve both) — the whole point of asking.
                let scopedCache = loadedCache.removingEntries(under: forcedRescanPaths)
                // Loose files are hashed directly; .zip archives are expanded
                // and their entries hashed individually, since that's where
                // most ROM sets actually keep each game.
                let freshHashedFiles = try await CollectionHasher.hash(scannedFiles: scannedFiles, cache: scopedCache, algorithms: hashAlgorithms, onProgress: progressHandler, onArchiveListed: archiveListedHandler)
                // Every OTHER folder's own files — reconstructed straight
                // from the cache already on disk, with NO fresh walk/read
                // of its own, for a genuinely scoped scan. Combined with
                // `freshHashedFiles` above, the matcher below still sees
                // the WHOLE system at once (the actual fix the 2026-08-06
                // change was for — a matcher that can't see every folder
                // can't correctly resolve a rom duplicated across two of
                // them), it's just that everything outside the requested
                // scope comes from what was already known rather than a
                // fresh re-read. `scopedCache` (loaded cache with the
                // scope's own entries already dropped, above) is exactly
                // "everything else" — reusing it here means the exclusion
                // goes through `removingEntries(under:)`'s own tested
                // path-boundary matching rather than a second, separately
                // written prefix check. An unscoped scan
                // (`forcedRescanPaths` empty) has nothing left to
                // reconstruct — `pathsToWalk` already covered everything,
                // and `scopedCache` there is just the untouched
                // `loadedCache` in full.
                let reconstructedOthers = forcedRescanPaths.isEmpty ? [] : scopedCache.reconstructedHashedFiles()
                // jensyleo's own report (2026-09-10): "Scan Folder sigue
                // haciendo escaneo a todas las carpetas" — the Log gave no
                // way to see that only the scope was actually read from
                // disk, since the matcher legitimately still reports on
                // every game in the DAT afterwards. This line states the
                // split outright.
                if !reconstructedOthers.isEmpty {
                    reconstructionLogHandler(freshHashedFiles.count, reconstructedOthers.count)
                }
                // Sorted, NOT just concatenated — jensyleo's own report
                // (2026-09-10) on a Nintendo folder holding both `nss.7z`
                // and `nss.zip`: "Rescan This File" on `nss.7z` made its
                // row vanish, and only "Scan Folder" brought it back. His
                // own log showed why: the archive went from Incorrect (a
                // surplus duplicate bucket) to "6 correct, 0 surplus".
                //
                // `ROMMatcher` resolves each rom to `scopedCandidates
                // .first(where: { !consumed[$0] && matches(...) })` — so
                // for two byte-identical archives, ARRAY ORDER alone
                // decides which becomes the game's claimed set and which
                // is reported as the redundant duplicate. Concatenating
                // fresh-first put whatever was just rescanned at the head,
                // so rescanning `nss.7z` handed the game's set to the
                // `.7z` and demoted `nss.zip` — a verdict that flipped
                // purely because of WHICH file the user asked to re-read.
                // (`reconstructedOthers` is sorted for the same reason;
                // see `ScanCache.reconstructedHashedFiles`' own doc
                // comment.)
                //
                // Sorting by (container path, entry name) makes the order
                // — and therefore every claim decision — identical no
                // matter what scope produced the scan, which is exactly
                // the property a scoped rescan must not change.
                let hashedFiles = (freshHashedFiles + reconstructedOthers).sorted {
                    ($0.file.url.path, $0.file.name) < ($1.file.url.path, $1.file.name)
                }
                // CHDs come from the WALK, never from `hashedFiles` — see
                // `chdFiles` below for why. In-scope ones are whatever the
                // walk just found; every other folder's come from the
                // cache, exactly mirroring `reconstructedOthers` above.
                let freshCHDPaths = scannedFiles.map(\.url).filter { $0.pathExtension.lowercased() == "chd" }
                let reconstructedCHDPaths = forcedRescanPaths.isEmpty ? [] : scopedCache.reconstructedCHDPaths()
                let chdFiles = freshCHDPaths + reconstructedCHDPaths
                try? ScanCache.build(from: hashedFiles, chdPaths: chdFiles).save(to: cacheURL)
                matchingStartedHandler()
                let matchReport = try ROMMatcher.match(dat: dat, hashedFiles: hashedFiles, onProgress: matchProgressHandler, cancellationFlag: cancellationFlag)
                var auditReport = try AuditReporter.generate(from: matchReport)
                // CHDs never go through `ROMMatcher` at all (a disk isn't a
                // `DATRom`) — audited separately here, by each CHD's own
                // header SHA1 (`DiskAuditor`/`CHDMatcher`), then folded into
                // the same report so a scanned folder of MAME discs shows
                // up as real Correct/Incorrect/Missing rows instead of
                // silently vanishing from the audit entirely.
                //
                // `chdFiles` is built above, from the WALK plus the cache —
                // NOT from `hashedFiles`. jensyleo's own instruction
                // (2026-09-10) to check Fase 1's read path survived the
                // scoping work is how the bug here was found: this line
                // used to read `hashedFiles.map(\.file.url).filter { .chd }`,
                // which is UNCONDITIONALLY EMPTY.
                // `CollectionHasher.hash` excludes `.chd` on purpose (a
                // CHD's whole-file hash matches no `DATRom`, so hashing one
                // only wastes time), so a CHD never appears in a
                // `[HashedFile]` — nor in `ScanCache.entries`, which is
                // built from them. Disk auditing was therefore receiving an
                // empty list every single scan and reporting every disk in
                // the DAT missing. The 2026-07-30 report it was trying to
                // honor (a scoped scan must not mark OTHER folders' disks
                // missing) is satisfied instead by `ScanCache.chdPaths`,
                // which persists CHD paths deliberately outside `entries`
                // so they reach `DiskAuditor` without ever reaching
                // `ROMMatcher`.
                if dat.games.contains(where: { !$0.disks.isEmpty }) {
                    let diskEntries = try DiskAuditor.audit(dat: dat, chdFiles: chdFiles)
                    auditReport = try AuditReporter.merging(diskEntries: diskEntries, into: auditReport)
                }
                // Several ROM folders per system is common (different
                // drives, region subfolders) — this flags a game whose set
                // is physically duplicated across more than one of them,
                // with its own dedicated row rather than only the scattered
                // per-rom "Not needed here" surplus reporting that already
                // exists. Run last, after every other pass has settled the
                // real per-rom statuses this reads.
                auditReport = try AuditReporter.addingDuplicateSets(to: auditReport, rootFolders: system.romFolderURLs)
                // Flags a BIOS archive nothing currently present actually
                // needs (e.g. `neogeo.zip` sitting unused once every
                // Neo-Geo game that used to depend on it was removed) — a
                // pure flag on rows this same report already computed, so
                // it can run after every other pass has settled them.
                auditReport = AuditReporter.markingOrphanedBIOS(in: auditReport)
                // Flags a TOSEC/GoodTools embedded-filename-CRC vs
                // actual-content mismatch — cheap enough (filename parsing
                // plus a string compare against a hash already computed
                // above, no extra file reads) to run on every scan, unlike
                // the ZIP-internal-CRC check below.
                auditReport = AuditReporter.markingFilenameCRCMismatches(in: auditReport)
                // jensyleo's own report (2026-09-10): "Rescan This File"
                // right after a case-only rename (e.g. "Fix Mismatched
                // Files" with "Sets case" = Uppercase) could log "Done in
                // Xs: 0 correct, 0 incorrect..." even though the file was
                // genuinely there and correct — `forcedRescanPaths` still
                // holds the STALE (pre-rename) case, but every entry in
                // this fresh `auditReport` now carries the file's TRUE,
                // corrected on-disk path (`FolderScanner.scanSingleFile`'s
                // own `.nameKey` fix, this same report). `scopedSummary`'s
                // path-based matching below never found any entry under
                // the OLD path, so it summarized nothing. Passed out here
                // so the call site can match against BOTH the path this
                // rescan was actually asked for AND whatever real path the
                // walk/hash pass just found things under — cache eviction
                // (`scopedCache`, above) deliberately keeps using the
                // ORIGINAL `forcedRescanPaths` alone; only the audit-side
                // "which entries did this rescan touch" question needs the
                // corrected path too.
                let freshlyObservedPaths = Set(freshHashedFiles.map(\.file.url.path)).map { URL(fileURLWithPath: $0) }
                return (dat.header, matchReport, auditReport, dat, freshlyParsed, freshlyParsedIdentity, freshlyObservedPaths)
            }
            cancelDetachedWork = { detached.cancel() }
            let (header, report, audit, dat, freshlyParsed, freshlyParsedIdentity, freshlyObservedPaths) = try await detached.value
            let effectiveRescannedPaths = forcedRescanPaths.isEmpty ? [] : forcedRescanPaths + freshlyObservedPaths
            if let freshlyParsed, let freshlyParsedIdentity {
                Self.sharedRawDatasetCache[system.id] = (freshlyParsedIdentity, freshlyParsed)
            }

            cachedDATKey = datCacheKey
            cachedDATFile = dat
            datHeader = header
            // `audit` itself is used verbatim for persistence — every scan
            // now matches every folder (see this function's own doc comment
            // above), so it's already the complete truth for the whole
            // system, with no reconciliation against any previous report.
            // The merge step this replaced was the source of four separate
            // live-found bugs, the last of which (a game vanishing from
            // whichever folder wasn't just scanned) is what prompted
            // removing the partial-scan design outright rather than
            // patching it a fifth time.
            //
            // What actually gets *displayed*, though, is narrower for a
            // targeted rescan ("Rescan This File", or "Scan Folder" on one
            // folder): jensyleo's own request (2026-08-17) is that only the
            // rescanned file's own row visually updates — every other row
            // should look exactly as it did a moment ago, with no
            // whole-table flicker for a spot check on one file (e.g. after
            // changing BIOS merge mode). `replacingRescannedEntries` folds
            // `audit`'s fresh, complete result down to just the rescanned
            // game(s)' own entries, keeping every other entry as the exact
            // value it already had. This only affects this session's live
            // display — the database below always gets the full, correct
            // `audit`, so reopening this system fresh never shows anything
            // artificially held back by this.
            let displayedAudit = AuditReporter.replacingRescannedEntries(in: auditReport, with: audit, rescannedPaths: effectiveRescannedPaths)
            matchReport = report
            // jensyleo's own rule (2026-09-10): "el último scan es el que
            // aplica" for Fix purposes — recorded here, at the exact same
            // success point `matchReport` itself is updated, so the two can
            // never drift apart.
            lastScanScope = folders.map { .paths($0) } ?? .wholeSystem
            auditReport = displayedAudit
            scanProgress = nil
            folderScanFilesFound = nil
            currentlyScanningFolder = nil
            archiveListingProgress = nil
            let totalDuration = Date().timeIntervalSince(scanStart)
            // jensyleo's own report (2026-09-11): this completion line read
            // whole-SYSTEM totals even for a scoped "Scan File"/"Scan
            // Folder" ("esta línea no tiene nada que ver con la acción de
            // scan file") — `audit` is always the full, freshly-matched
            // report regardless of scope (see this function's own doc
            // comment on why matching always covers everything). For a
            // scoped scan, summarize only what was actually asked for
            // instead — the same game(s) `displayedAudit` above already
            // narrows the visible rows down to.
            let summary = AuditReporter.scopedSummary(in: audit, rescannedPaths: effectiveRescannedPaths) ?? audit
            log(
                String(
                    format: "Done in %.1fs: %d correct, %d incorrect, %d missing, %d surplus.", totalDuration, summary.correct,
                    summary.incorrect, summary.missing, summary.surplus
                ),
                // A green "Done" when the scan actually found problems would
                // read as "everything's fine" when it isn't — success only
                // when nothing needs the user's attention.
                kind: (summary.incorrect > 0 || summary.missing > 0) ? .warning : .success
            )
            do {
                try AuditDatabaseLocation.open().saveReport(
                    audit, systemID: system.id.uuidString, datName: header.name, datVersion: header.version, scannedAt: Date()
                )
            } catch {
                logWarning("Couldn't persist this scan's results: \(error)")
            }
        } catch is CancellationError {
            isLoadingDAT = false
            datFileReadProgress = nil
            isCountingDATMachines = false
            datCountingProgress = nil
            datLoadProgress = nil
            folderScanFilesFound = nil
            currentlyScanningFolder = nil
            archiveListingProgress = nil
            scanProgress = nil
            isMatching = false
            matchProgress = nil
            logWarning("Scan cancelled.")
        } catch {
            isLoadingDAT = false
            datFileReadProgress = nil
            isCountingDATMachines = false
            datCountingProgress = nil
            datLoadProgress = nil
            folderScanFilesFound = nil
            currentlyScanningFolder = nil
            archiveListingProgress = nil
            scanProgress = nil
            isMatching = false
            matchProgress = nil
            logError("Failed: \(String(describing: error))")
        }
    }

    /// Explicit, on-demand ZIP structural check — reads every scanned `.zip`
    /// archive's own central directory a second time to cross-check each
    /// entry's local-header CRC32 against it (`ZipIntegrityAuditor`/
    /// `ZipLocalHeaderCRCVerifier`). Never run automatically as part of
    /// `scan` above — see `ZipIntegrityAuditor`'s own doc comment for why
    /// this is a separate, user-triggered action instead: real cost for a
    /// large collection, for a check that only matters when something is
    /// actually already damaged.
    func verifyZipIntegrity(system: RomSystem) async {
        guard let report = auditReport else {
            logError("Scan first.")
            return
        }
        isBusy = true
        log("Verifying ZIP integrity…")
        let detached = Task.detached(priority: .userInitiated) {
            AuditReporter.verifyingZipIntegrity(in: report)
        }
        let verified = await detached.value
        auditReport = verified
        let mismatchCount = verified.entries.filter(\.hasInternalZipCRCMismatch).count
        log(
            mismatchCount == 0
                ? "ZIP integrity check done: no internal CRC inconsistencies found."
                : "ZIP integrity check done: \(mismatchCount) entr\(mismatchCount == 1 ? "y" : "ies") with an internal CRC mismatch.",
            kind: mismatchCount == 0 ? .success : .warning
        )
        do {
            if let meta = try AuditDatabaseLocation.open().loadScanMeta(systemID: system.id.uuidString) {
                try AuditDatabaseLocation.open().saveReport(
                    verified, systemID: system.id.uuidString, datName: meta.datName, datVersion: meta.datVersion, scannedAt: meta.scannedAt
                )
            }
        } catch {
            logWarning("Couldn't persist the ZIP integrity check's results: \(error)")
        }
        isBusy = false
    }

    /// How many File renames "Fix Mismatched Files" would actually plan,
    /// without touching disk — same preview-before-confirm pattern as
    /// `planRenameRomsInArchivePreviewCount`'s own ROM-level counterpart,
    /// added for the same reason (2026-09-10): a confirmation dialog needs
    /// a real, accurate count to show, and (via `LibraryDetailView`'s own
    /// `currentSetsCasePolicyRisksCaseMismatch`) to decide whether it's
    /// even worth showing at all. Combines BOTH halves `fix()` itself
    /// runs together — `planRepair` (a genuine mismatch) and
    /// `planApplySetsCasePolicy` (an already-correct name re-styled) — so
    /// this count always matches what actually happens.
    func planFixPreviewCount(scopeFolders: [URL] = []) -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        let filesCasePolicy = FixPreferencesSettings.currentSetsCasePolicy()
        let mismatchOperations = RebuildPlanner.planRepair(matchReport: matchReport, filesCasePolicy: filesCasePolicy)
        let caseOnlyOperations = RebuildPlanner.planApplySetsCasePolicy(matchReport: matchReport, policy: filesCasePolicy)
        return Self.restrictToScope(mismatchOperations + caseOnlyOperations, scopeFolders: scopeFolders).count
    }

    /// A short " inside …" clause naming the scope for a Log message —
    /// empty for "the whole system", the one File/folder's own name for a
    /// single-element scope (unchanged from before multi-selection), and a
    /// plain count for several at once (jensyleo's own request, 2026-09-10:
    /// "la app no permite selección múltiple" — naming every single one of
    /// a large multi-selection wouldn't read as a short clause anymore).
    /// Not `private` — `LibraryDetailView`'s own context-menu handlers
    /// (`fixMismatchedFile`/`startContextMenuRenameRomsInArchive`) build
    /// the exact same clause for their OWN "nothing to fix" messages,
    /// before `fix()`/`renameRomsInArchive()` themselves ever run.
    nonisolated static func scopeSuffixForLog(_ scopeFolders: [URL]) -> String {
        switch scopeFolders.count {
        case 0: return ""
        case 1: return " inside \"\(scopeFolders[0].lastPathComponent)\""
        default: return " inside \(scopeFolders.count) selected File(s)"
        }
    }

    func fix(system: RomSystem, scopeFolders: [URL] = []) async {
        guard Self.modificationsEnabled else {
            logError("Repairing ROMs is disabled for now — ROMForge only scans and reports, it won't touch your files.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        isBusy = true
        defer { isBusy = false }

        // jensyleo's own decision (2026-09-10): correcting a name the DAT
        // disagrees with is the whole reason this action — and this app —
        // exists; it was never really optional the way, say, "Remove
        // Useless Files" (destructive) or "Handle Corrupted Files"
        // (judgment call) genuinely are. A toggle that could turn off
        // "Fix Mismatched Files" from actually fixing mismatches invited
        // exactly the confusion it caused live: Uppercase configured, a
        // collection full of wrong names, and a silent no-op with no
        // visible reason why. The only real knob left is HOW the
        // corrected name is styled — `filesCasePolicy` below, always
        // applied.
        let filesCasePolicy = FixPreferencesSettings.currentSetsCasePolicy()

        // jensyleo's own report (2026-09-10): a single `try
        // RebuildExecutor.execute(eligible)` call over the WHOLE array
        // meant one early failure (e.g. a genuine destination collision)
        // aborted every operation after it in the same batch, silently —
        // the catch below only ever logged one generic error string, with
        // no way to tell "nothing was eligible" apart from "50 renames
        // were eligible and none of them ran because #1 collided". Every
        // OTHER Fix action already executes its own operations one at a
        // time, tracking succeeded/failed independently, for exactly this
        // reason — this one was the odd one out.
        let outcome = await Task.detached(priority: .userInitiated) {
            // `planRepair` itself now only ever plans a genuine File-level
            // rename (a loose file's own name, or a whole misnamed
            // archive's own container name) — an entry mismatch INSIDE an
            // otherwise-correctly-named archive is never touched by it at
            // all (see `planRepair`'s own doc comment), so every operation
            // it returns is eligible here, no separate filtering needed.
            let mismatchOperations = RebuildPlanner.planRepair(matchReport: matchReport, filesCasePolicy: filesCasePolicy)
            // jensyleo's own report (2026-09-10): 26 loose lowercase
            // archives, "Sets case" set to Uppercase, ran "Fix Mismatched
            // Files" and got "nothing to fix" — correctly, by this
            // action's OLD, narrower definition (nothing there disagreed
            // with the DAT), but not by his own, which matches
            // ClrMamePro's actual model: one "Fix" pass applies every
            // configured policy at once, including re-styling a name
            // that's already otherwise correct. That was split into a
            // separate "Apply Case Policy…" action instead — technically
            // reachable, but two buttons sharing one Settings toggle
            // ("Sets case") reads as a collision rather than two distinct
            // features. Folding `planApplySetsCasePolicy` into THIS same
            // pass makes "Fix Mismatched Files" match ClrMamePro's model
            // for real: it repairs a wrong name AND re-cases an
            // already-correct one, in one click, exactly as its own doc
            // comment on `applyCasePolicy` already claimed the app does.
            // The two plans never target the same File: `planRepair` only
            // ever touches a `.misnamed` anchor, `planApplySetsCasePolicy`
            // only ever a `.correct` one whose OWN name already matches
            // the DAT apart from case (see that function's own doc
            // comment) — mutually exclusive by construction, so there's
            // no double-rename risk in combining them.
            let caseOnlyOperations = RebuildPlanner.planApplySetsCasePolicy(matchReport: matchReport, policy: filesCasePolicy)
            let allOperations = mismatchOperations + caseOnlyOperations
            let scopedEligible = Self.restrictToScope(allOperations, scopeFolders: scopeFolders)
            var succeeded = 0
            var failed = 0
            // jensyleo's own report (2026-09-10, again): "la opción de fix
            // sigue sin funcionar" — with every error swallowed by the
            // `catch` below there was no way to tell a planner that found
            // nothing apart from a rename that failed on every single file,
            // even though the summary line already promised "see above for
            // which". Each failure's own reason is collected here and
            // logged for real after the verification rescan (which clears
            // the Log, so logging from inside this task would be erased).
            var failureLines: [String] = []
            for operation in scopedEligible {
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    if case .rename(let from, let to) = operation {
                        failureLines.append("Could not rename \"\(from.lastPathComponent)\" → \"\(to.lastPathComponent)\": \(error.localizedDescription)")
                    } else {
                        failureLines.append("Operation failed: \(error.localizedDescription)")
                    }
                }
            }
            // Counted separately from `matchReport` itself (not from
            // `planRepair`'s output, which no longer includes these at
            // all) purely to keep pointing the user at "Fix Misnamed ROMs
            // Inside Their Archives…" for a rom whose ENTRY name (not its
            // container's) is what's actually wrong.
            // jensyleo's own instruction (2026-09-10) to keep File and ROM
            // strictly apart: what makes a mismatch entry-level is that the
            // rom is an ENTRY INSIDE a container, which is exactly
            // `file.url.lastPathComponent != file.name` (the same test
            // `ScanCache.key(for:)`/`ROMMatcher.annotateMisnamedArchives`/
            // `RebuildPlanner.isArchivedEntry` use). The extension test
            // this used instead also matched a LOOSE `.zip`/`.7z` that is
            // itself a misnamed rom — a genuine File-level rename that
            // `planRepair` does handle — so such a file was renamed
            // correctly and then ALSO reported as "left as-is, use Fix
            // Misnamed ROMs Inside Their Archives instead", which is both
            // wrong and self-contradicting.
            let entryLevelMismatchCount = matchReport.games.flatMap(\.matches).filter { match in
                guard case .misnamed(let hashedFile, _) = match.status,
                      hashedFile.file.url.lastPathComponent != hashedFile.file.name
                else { return false }
                return Self.urlIsInScope(hashedFile.file.url, scopeFolders: scopeFolders)
            }.count
            return (
                succeeded: succeeded, failed: failed, skippedCount: entryLevelMismatchCount,
                plannedCount: allOperations.count, inScopeCount: scopedEligible.count,
                failureLines: failureLines
            )
        }.value
        let (succeeded, failed, skippedCount) = (outcome.succeeded, outcome.failed, outcome.skippedCount)

        // jensyleo's own report (2026-09-11): the messages above already
        // named the scope ("Fixed N mismatched File(s)" said nothing about
        // WHICH folder), but the automatic verification rescan below always
        // re-ran unscoped ("Scanning <system> (N folders)…") regardless —
        // right after an action that was itself genuinely scoped, directly
        // contradicting the scan-separation work this same request started.
        // A scoped Fix only ever touches files under `scopeFolder`, so a
        // scoped rescan is both sufficient to verify it and consistent with
        // what the Log already said just happened.
        //
        // jensyleo's own report (2026-09-10, follow-up): "el fix del nombre
        // del archivo... no se actualiza en pantalla, pero sí queda el
        // archivo [renombrado]" — deterministic, not random: it happened
        // whenever `scopeFolder` was a single FILE (the context menu's own
        // per-file Fix) AND the rename changed more than just case. A
        // pure case-only rename still resolves under the OLD path on the
        // default case-insensitive-but-case-preserving volume (APFS), so
        // rescanning it worked — but a genuinely different name (the
        // PRIMARY case "Fix Mismatched Files" exists for) means the old
        // path is simply gone. `scan(folders: [scopeFolder])` below would
        // call `FolderScanner.scanSingleFile(scopeFolder)`, which throws
        // `ScannerError.folderNotFound` for a path that no longer exists
        // at all — that error propagates out of `scan()`'s own detached
        // task, aborting the WHOLE verification silently (`scan()`'s own
        // outer `catch` just logs "Failed: ..." and returns without
        // touching `matchReport`/`auditReport`). The rename itself had
        // already fully succeeded by this point; only the app's own
        // on-screen refresh was ever at risk.
        //
        // Falling back to the renamed File's own PARENT FOLDER is always
        // safe here: only the File itself changed, never its containing
        // directory, and a folder-level walk (`FileManager`'s enumerator)
        // always yields the real, current on-disk name regardless of what
        // it used to be called.
        // A multi-selection can mix Files whose rename genuinely changed
        // more than just case (now-gone old path — substitute its parent)
        // with ones that didn't (still resolvable, scan it directly) —
        // each File's own fallback is independent of every other's.
        var seenEffectivePaths: Set<String> = []
        let effectiveScopeFolders = scopeFolders.compactMap { folder -> URL? in
            let resolved = FileManager.default.fileExists(atPath: folder.path) ? folder : folder.deletingLastPathComponent()
            // De-duplicated by path — two different Files whose renames
            // both genuinely changed their own name (not just case) can
            // fall back to the SAME parent folder; walking it twice would
            // be redundant, not incorrect, but there's no reason to pay
            // for it.
            return seenEffectivePaths.insert(resolved.path).inserted ? resolved : nil
        }
        let scopeSuffix = Self.scopeSuffixForLog(scopeFolders)
        await scan(system: system, folders: effectiveScopeFolders.isEmpty ? nil : effectiveScopeFolders)
        // Always states what was actually planned, so "nothing happened" is
        // never ambiguous between "the planner found no mismatched File" and
        // "it found some but the selected folder filtered every one out".
        log("Planned \(outcome.plannedCount) File rename(s) from this scan (mismatches + \"Sets case\" re-styling); \(outcome.inScopeCount) of them\(scopeSuffix.isEmpty ? "" : scopeSuffix).")
        for line in outcome.failureLines {
            logWarning(line)
        }
        if succeeded > 0 {
            logSuccess("Fixed \(succeeded) mismatched File(s)\(scopeSuffix).")
        }
        if failed > 0 {
            logWarning("\(failed) mismatched File(s)\(scopeSuffix) failed to rename (see the lines just above for which).")
        }
        if outcome.plannedCount > 0, outcome.inScopeCount == 0 {
            let where_ = scopeFolders.count == 1 ? scopeFolders[0].lastPathComponent : "the selected folder/File(s)"
            logWarning("Every one of the \(outcome.plannedCount) mismatched File(s) this scan found lives OUTSIDE \(where_) — select the folder/File they're actually in (or \"Database\" for the whole system) and run this again.")
        }
        if skippedCount > 0 {
            logWarning("\(skippedCount) misnamed ROM(s)\(scopeSuffix) left as-is — their content lives INSIDE an otherwise-correctly-named archive (a zip/7z entry, not the archive's own filename). Use \"Fix Misnamed ROMs Inside Their Archives…\" for those instead — \"Fix Mismatched Files\" only ever renames a File's own name, never one entry inside it (see \"Terminology: File vs ROM\" in Help).")
        }
        if succeeded == 0, failed == 0, skippedCount == 0 {
            // Now genuinely means what it says: this pass covers BOTH a
            // wrong name (mismatch repair) AND an already-correct one that
            // "Sets case" would re-style — see `mismatchOperations`/
            // `caseOnlyOperations` above. Nothing planned means nothing
            // for either half to do, uppercase or not.
            logWarning("Nothing to fix\(scopeSuffix) — every File name already matches the DAT, styled exactly per \"Sets case\" (\(filesCasePolicy.rawValue)).")
        }
    }

    /// How many file operations a "Rebuild to Folder…" against `destination`
    /// would actually plan, without touching disk — used to show the user a
    /// real count ("Rebuild 214 files?") before they commit, same caution
    /// pattern as everything else Phase 2 writes. Returns `0` before any
    /// scan has run, same as every other write action's own "scan first"
    /// guard.
    func planRebuildPreviewCount(destination: URL, move: Bool) -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        return RebuildPlanner.planRebuild(matchReport: matchReport, destination: destination, move: move).count
    }

    /// Copies (or moves, if `move`) every matched ROM into
    /// `destination/<game name>/<rom name>` — Fase 2 Step 1's "classic
    /// rebuild". Each planned operation is executed independently so one
    /// failure (e.g. a pre-existing file at the destination) doesn't abort
    /// the rest — `RebuildExecutor.execute(_:)` itself stops at the first
    /// thrown error, which is right for `fix()`'s much smaller, single-file
    /// renames but wrong here where the user wants "do everything you can,
    /// then tell me what didn't work."
    func rebuildToFolder(system: RomSystem, destination: URL, move: Bool) async {
        guard Self.modificationsEnabled else {
            logError("Rebuilding is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return
        }
        isBusy = true
        defer { isBusy = false }

        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let operations = RebuildPlanner.planRebuild(matchReport: matchReport, destination: destination, move: move)
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for operation in operations {
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("Could not \(Self.describeOperation(operation)): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value

        let verb = move ? "moved" : "copied"
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Rebuild finished: \(succeeded) file(s) \(verb) to \"\(destination.lastPathComponent)\", \(failed) failed (see the lines just above for which).")
        } else {
            logSuccess("Rebuild complete: \(succeeded) file(s) \(verb) to \"\(destination.lastPathComponent)\".")
        }
    }

    /// How many files "Remove Useless Files…" would actually delete, without
    /// touching disk — the same preview-before-confirm pattern as
    /// `planRebuildPreviewCount`. Returns `0` before any scan has run.
    func planRemoveUselessFilesPreviewCount() -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        return RebuildPlanner.planRemoveUselessFiles(matchReport: matchReport).count
    }

    /// Permanently deletes every file the DAT recognizes nothing about at
    /// all — Fase 2 Step 7, the single most destructive action in the whole
    /// app. `LibraryDetailView`'s own toolbar action always shows its own
    /// confirmation dialog before calling this; there is no "undo" once it
    /// runs. Each deletion is attempted independently (same reasoning as
    /// `rebuildToFolder` above) so one locked/already-gone file doesn't
    /// abort the rest.
    func removeUselessFiles(system: RomSystem) async {
        guard Self.modificationsEnabled else {
            logError("Removing files is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return
        }
        isBusy = true
        defer { isBusy = false }

        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let operations = RebuildPlanner.planRemoveUselessFiles(matchReport: matchReport)
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for operation in operations {
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("Could not \(Self.describeOperation(operation)): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value

        // jensyleo's own report (2026-09-11): logging this action's own
        // result BEFORE the verification rescan meant `scan()`'s own
        // `logLines.removeAll()` erased it right away — the Log ended up
        // showing only the rescan's narration, never what this action
        // itself actually did. Same fix as `fix()`/`renameRomsInArchive()`
        // above: scan first, log the result after.
        await scan(system: system)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Removed \(succeeded) useless file(s); \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Removed \(succeeded) useless file(s).")
        } else {
            logWarning("Nothing to remove — no unrecognized files in the current scan.")
        }
    }

    /// How many missing roms "Repair from Sibling Sets…" would actually fill
    /// in, without touching disk — same preview-before-confirm pattern as
    /// every other Fase 2 action. Returns `0` before any scan has run.
    func planRepairFromSiblingSetsPreviewCount() -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        return RebuildPlanner.planCrossSetRepair(matchReport: matchReport).count
    }

    /// Fills in a missing rom by copying it from a sibling parent/clone set
    /// that already has the exact same content — Fase 2 Step 3. Each
    /// planned operation is attempted independently (same reasoning as
    /// `removeUselessFiles`/`rebuildToFolder` above) so one failure doesn't
    /// abort the rest.
    func repairFromSiblingSets(system: RomSystem) async {
        guard Self.modificationsEnabled else {
            logError("Repairing is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return
        }
        isBusy = true
        defer { isBusy = false }

        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let operations = RebuildPlanner.planCrossSetRepair(matchReport: matchReport)
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for operation in operations {
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("Could not \(Self.describeOperation(operation)): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value

        // Scan first, log after — see `removeUselessFiles`'s own comment on
        // this exact reordering.
        await scan(system: system)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Repaired \(succeeded) rom(s) from sibling sets; \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Repaired \(succeeded) rom(s) from sibling sets.")
        } else {
            logWarning("Nothing to repair from sibling sets — no missing rom has a matching donor in this scan.")
        }
    }

    /// The plan `planRepairFromMaintenanceFolderPreviewCount` already
    /// built, so `repairFromMaintenanceFolder` can execute it without
    /// scanning the Maintenance folder a second time right after the
    /// user confirms — cheaper, and avoids the two steps silently
    /// disagreeing if a file appears/disappears there in between.
    private var pendingMaintenanceFolderOperations: [RebuildOperation] = []

    /// Scans the optional, read-only Maintenance folder configured in
    /// Settings → General (`MaintenanceFolderSettings`) and plans every
    /// rom it can donate to a `.missing` rom in the current scan — Fase
    /// 2's "Repair from Maintenance Folder…". Nothing here ever writes
    /// to, moves, or deletes anything in that folder; it's only ever
    /// read, exactly like `planRepairFromSiblingSetsPreviewCount`'s own
    /// sibling donors. Returns the operation count for the caller's
    /// preview-before-confirm dialog; the plan itself is cached in
    /// `pendingMaintenanceFolderOperations` for `repairFromMaintenanceFolder`.
    func planRepairFromMaintenanceFolderPreviewCount() async -> Int {
        pendingMaintenanceFolderOperations = []
        guard let matchReport = requireMatchReport() else { return 0 }
        guard let folderURL = MaintenanceFolderSettings.folderURL else {
            logWarning("No Maintenance folder configured — set one in Settings → General first.")
            return 0
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let operations = try await Task.detached(priority: .userInitiated) {
                let scannedFiles = try FolderScanner.scan(paths: [folderURL])
                let donorFiles = try await CollectionHasher.hash(scannedFiles: scannedFiles, algorithms: HashAlgorithmSettings.current)
                return RebuildPlanner.planRepairFromMaintenanceFolder(matchReport: matchReport, donorFiles: donorFiles)
            }.value
            pendingMaintenanceFolderOperations = operations
            return operations.count
        } catch {
            // jensyleo's own instruction (2026-09-10) to review the app's
            // whole logging for coherence: a bare `String(describing:
            // error)` reads as a raw dump ("folderNotFound(file:///...)")
            // with no sense of WHAT was being attempted when it happened —
            // every other error in this file names the action first.
            logError("Couldn't read the Maintenance folder (\(folderURL.path)): \(error.localizedDescription)")
            return 0
        }
    }

    /// Executes the plan `planRepairFromMaintenanceFolderPreviewCount`
    /// already built. Every operation only ever READS from the
    /// Maintenance folder (a `.copy`/`.extractZipEntry`/`.addEntryToZip`'s
    /// own donor source) — the actual write always lands in the scanned
    /// collection's own existing archive/folder, never back into the
    /// Maintenance folder itself. Each operation is attempted
    /// independently, same reasoning as `repairFromSiblingSets` above.
    func repairFromMaintenanceFolder(system: RomSystem) async {
        guard Self.modificationsEnabled else {
            logError("Repairing is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return
        }
        let operations = pendingMaintenanceFolderOperations
        pendingMaintenanceFolderOperations = []
        guard !operations.isEmpty else {
            logWarning("Nothing to repair from the Maintenance folder.")
            return
        }
        isBusy = true
        defer { isBusy = false }

        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for operation in operations {
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("Could not \(Self.describeOperation(operation)): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value

        // Scan first, log after — see `removeUselessFiles`'s own comment on
        // this exact reordering.
        await scan(system: system)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Repaired \(succeeded) rom(s) from the Maintenance folder; \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Repaired \(succeeded) rom(s) from the Maintenance folder.")
        }
    }

    /// How many roms "Make Self-Contained…" would actually copy in, without
    /// touching disk — same preview-before-confirm pattern as every other
    /// Fase 2 action. Returns `0` before any scan has run.
    func planMakeSelfContainedPreviewCount() -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        return RebuildPlanner.planConvertToNonMerged(matchReport: matchReport).count
    }

    /// Copies every rom the matcher found genuinely present elsewhere in
    /// the scan (`.foundElsewhere`) into each game's own archive — Fase 2
    /// Step 4, "non-merged" direction only (see `RebuildPlanner
    /// .planConvertToNonMerged`'s own doc comment for why "split"/"merged"
    /// aren't offered yet). Each planned operation is attempted
    /// independently (same reasoning as every other Fase 2 batch action
    /// above) so one failure doesn't abort the rest.
    func makeSelfContained(system: RomSystem) async {
        guard Self.modificationsEnabled else {
            logError("This is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return
        }
        isBusy = true
        defer { isBusy = false }

        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let operations = RebuildPlanner.planConvertToNonMerged(matchReport: matchReport)
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for operation in operations {
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("Could not \(Self.describeOperation(operation)): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value

        // Scan first, log after — see `removeUselessFiles`'s own comment on
        // this exact reordering.
        await scan(system: system)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Copied \(succeeded) inherited rom(s) into their own archives; \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Copied \(succeeded) inherited rom(s) into their own archives.")
        } else {
            logWarning("Nothing to copy — every game in this scan is already self-contained.")
        }
    }

    /// How many ROM entries "Fix Misnamed ROMs Inside Their Archives…"
    /// would actually fix, without touching disk. `RebuildPlanner.planRenameRomsInArchive`
    /// returns TWO operations per rename (add the new name, then remove the
    /// old one — see that function's own doc comment) — this counts pairs,
    /// not raw operations, so the number shown matches what the user
    /// actually asked for.
    func planRenameRomsInArchivePreviewCount(scopeFolders: [URL] = [], entryKeys: Set<String> = []) -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        let romsCasePolicy = FixPreferencesSettings.currentRomsCasePolicy()
        // jensyleo's own report (2026-09-10): "awbios.zip", Roms case =
        // Uppercase, "Fix Misnamed ROMs Inside This Archive…" (both the
        // toolbar's own and the new per-file context-menu action) logged
        // "no misnamed rom entries" even though the entries inside were
        // genuinely still lowercase. Root cause: `renameRomsInArchive()`
        // itself was unified (2026-09-10, ClrMamePro-parity request) to
        // run BOTH `planRenameRomsInArchive` (a wrong entry name) AND
        // `planApplyRomsCasePolicy` (an already-correct one re-styled) in
        // one pass — but THIS preview count, which gates whether that
        // action ever even runs, was never updated to match. It kept
        // counting only the mismatch half, so a scan with zero mismatches
        // but real case-only work to do still reported 0 and never let
        // the real action run at all.
        let mismatchOperations = RebuildPlanner.planRenameRomsInArchive(matchReport: matchReport, romsCasePolicy: romsCasePolicy)
        let caseOnlyOperations = RebuildPlanner.planApplyRomsCasePolicy(matchReport: matchReport, policy: romsCasePolicy)
        let operations = Self.restrictPairsToEntries(
            Self.restrictPairsToScope(mismatchOperations + caseOnlyOperations, scopeFolders: scopeFolders),
            entryKeys: entryKeys
        )
        return operations.count / 2
    }

    /// Renames a misnamed ROM entry inside an otherwise-correctly-named
    /// archive File — Fase 2 Step 6's ROM-level half (the File-level half is
    /// already what "Fix Mismatched Files" does). Each rename's own add+remove
    /// pair is executed together so one failure doesn't leave the archive
    /// with neither the old nor the new entry — see `RebuildPlanner
    /// .planRenameRomsInArchive`'s own doc comment for why add always comes
    /// before remove.
    /// - Parameter entryKeys: EMPTY means "every entry under `scopeFolders`
    ///   (or the whole system if that's also empty)" — the Games table's
    ///   own selection has no narrower concept than "these whole Files."
    ///   Non-empty (the Roms panel's own multi-selection, jensyleo's own
    ///   report 2026-09-10: "selecciono 2 roms y me renombra las 4" —
    ///   selecting SPECIFIC entries inside one archive used to still fix
    ///   every fixable entry in it, container-level scoping having no way
    ///   to tell "these two" from "all of them") restricts further, to
    ///   ONLY the entries named here — see `restrictPairsToEntries`'s own
    ///   doc comment for the exact key format.
    func renameRomsInArchive(system: RomSystem, scopeFolders: [URL] = [], entryKeys: Set<String> = []) async {
        guard Self.modificationsEnabled else {
            logError("Fixing is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        isBusy = true
        defer { isBusy = false }

        let romsCasePolicy = FixPreferencesSettings.currentRomsCasePolicy()

        let outcome = await Task.detached(priority: .userInitiated) {
            // Same unification as `fix()`'s own `mismatchOperations` +
            // `caseOnlyOperations` above, at the entry level: one "Fix"
            // pass should both repair a wrong entry name AND re-case an
            // already-correct one, matching ClrMamePro's single-pass
            // model. `planRenameRomsInArchive` only ever touches a
            // `.misnamed` entry; `planApplyRomsCasePolicy` only ever a
            // `.correct` one — mutually exclusive, so combining them
            // cannot double-rename the same entry.
            let mismatchOperations = RebuildPlanner.planRenameRomsInArchive(matchReport: matchReport, romsCasePolicy: romsCasePolicy)
            let caseOnlyOperations = RebuildPlanner.planApplyRomsCasePolicy(matchReport: matchReport, policy: romsCasePolicy)
            let allOperations = mismatchOperations + caseOnlyOperations
            let operations = Self.restrictPairsToEntries(
                Self.restrictPairsToScope(allOperations, scopeFolders: scopeFolders),
                entryKeys: entryKeys
            )
            var succeeded = 0
            var failed = 0
            // Same reasoning as `fix()`'s own `failureLines` above — a
            // swallowed error made "nothing happened" indistinguishable
            // from "every rewrite failed".
            var failureLines: [String] = []
            for pairStart in stride(from: 0, to: operations.count, by: 2) {
                let pair = Array(operations[pairStart..<Swift.min(pairStart + 2, operations.count)])
                do {
                    try RebuildExecutor.execute(pair)
                    succeeded += 1
                } catch {
                    failed += 1
                    if case .addEntryToZip(let archive, let entryName, _) = pair.first {
                        failureLines.append("Could not rename a rom to \"\(entryName)\" inside \"\(archive.lastPathComponent)\": \(error.localizedDescription)")
                    } else {
                        failureLines.append("Rom rename failed: \(error.localizedDescription)")
                    }
                }
            }
            return (
                succeeded: succeeded, failed: failed,
                plannedCount: allOperations.count / 2, inScopeCount: operations.count / 2,
                failureLines: failureLines
            )
        }.value
        let (succeeded, failed) = (outcome.succeeded, outcome.failed)

        // Same reasoning as `fix()`'s own comment just above: a scoped
        // rescan keeps this action's own verification consistent with what
        // it actually just did, instead of the Log switching back to an
        // unscoped "Scanning <system> (N folders)…" right after a scoped
        // action.
        // Same "did the scope itself get renamed away" concern as `fix()`
        // could in principle apply here too, but never actually does: this
        // action's own scope is always the CONTAINER's own path, and
        // `renameRomsInArchive` only ever rewrites ENTRIES inside it, never
        // the container itself — so `scopeFolders` always still exists by
        // the time this runs, no `effectiveScopeFolders` fallback needed.
        let scopeSuffix = Self.scopeSuffixForLog(scopeFolders)
        await scan(system: system, folders: scopeFolders.isEmpty ? nil : scopeFolders)
        log("Planned \(outcome.plannedCount) rom rename(s) from this scan (mismatches + \"Roms case\" re-styling); \(outcome.inScopeCount) of them\(scopeSuffix).")
        for line in outcome.failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Fixed \(succeeded) rom(s) inside their archives\(scopeSuffix); \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Fixed \(succeeded) rom(s) inside their archives\(scopeSuffix).")
        } else if outcome.plannedCount > 0, outcome.inScopeCount == 0 {
            let where_ = scopeFolders.count == 1 ? scopeFolders[0].lastPathComponent : "the selected folder/File(s)"
            logWarning("Every one of the \(outcome.plannedCount) misnamed rom(s) this scan found lives OUTSIDE \(where_) — select the folder/File they're actually in (or \"Database\" for the whole system) and run this again.")
        } else {
            logWarning("Nothing to fix\(scopeSuffix) — every rom entry already matches the DAT, styled exactly per \"Roms case\" (\(romsCasePolicy.rawValue)).")
        }
    }

    /// How many redundant roms "Strip Redundant ROMs (Split)…" would
    /// actually remove, without touching disk. Returns `0` before any scan
    /// has run.
    func planConvertToSplitPreviewCount() -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        return RebuildPlanner.planConvertToSplit(matchReport: matchReport).count
    }

    /// Strips a rom back out of a clone's own archive when the parent
    /// already has the exact same content correctly — Fase 2 Step 4, the
    /// "split" direction (the inverse of `makeSelfContained` above). Each
    /// planned operation is attempted independently (same reasoning as
    /// every other Fase 2 batch action) so one failure doesn't abort the
    /// rest.
    func convertToSplit(system: RomSystem) async {
        guard Self.modificationsEnabled else {
            logError("This is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return
        }
        isBusy = true
        defer { isBusy = false }

        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let operations = RebuildPlanner.planConvertToSplit(matchReport: matchReport)
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for operation in operations {
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("Could not \(Self.describeOperation(operation)): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value

        // Scan first, log after — see `removeUselessFiles`'s own comment on
        // this exact reordering.
        await scan(system: system)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Stripped \(succeeded) redundant rom(s) from clone archives; \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Stripped \(succeeded) redundant rom(s) from clone archives.")
        } else {
            logWarning("Nothing to strip — no clone in this scan has a rom already, exactly, in its parent's own archive.")
        }
    }

    /// Live `CorruptedFilesPolicy` + quarantine folder as currently
    /// configured in Settings → Fix — shared by the preview count and the
    /// real action below so they can never disagree about which policy
    /// they're each looking at.
    private func currentCorruptedFilesPolicy() -> (policy: CorruptedFilesPolicy, quarantineFolder: URL?) {
        let policy = CorruptedFilesPolicy(rawValue: UserDefaults.standard.string(forKey: FixPreferencesSettings.corruptedFilesPolicyKey) ?? "") ?? FixPreferencesSettings.corruptedFilesPolicyDefault
        let path = UserDefaults.standard.string(forKey: FixPreferencesSettings.corruptedFilesMoveToPathKey)
        let quarantineFolder = path.map { URL(fileURLWithPath: $0) }
        return (policy, quarantineFolder)
    }

    /// How many corrupted files "Handle Corrupted Files…" would actually
    /// act on, without touching disk — same preview-before-confirm pattern
    /// as every other Fase 2 action. Returns `0` before any scan has run,
    /// when the configured policy is "Don't Touch", or (for "Move to")
    /// when no quarantine folder is configured yet.
    func planCorruptedFilesPolicyPreviewCount() -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        let (policy, quarantineFolder) = currentCorruptedFilesPolicy()
        return RebuildPlanner.planCorruptedFilesPolicy(matchReport: matchReport, policy: policy, quarantineFolder: quarantineFolder).count
    }

    /// Applies whichever `CorruptedFilesPolicy` is configured in Settings →
    /// Fix to every rom `ZipIntegrityAuditor` confirms is internally
    /// corrupt — Fase 2 Step 8. Each corrupted file's own operation GROUP
    /// (one for `.delete`, two for `.moveTo` — see `RebuildPlanner
    /// .planCorruptedFilesPolicy`'s own doc comment) is executed together,
    /// so one failure doesn't leave a file half-quarantined.
    func applyCorruptedFilesPolicy(system: RomSystem) async {
        guard Self.modificationsEnabled else {
            logError("This is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return
        }
        isBusy = true
        defer { isBusy = false }

        let (policy, quarantineFolder) = currentCorruptedFilesPolicy()
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let groups = RebuildPlanner.planCorruptedFilesPolicy(matchReport: matchReport, policy: policy, quarantineFolder: quarantineFolder)
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for group in groups {
                do {
                    try RebuildExecutor.execute(group)
                    succeeded += 1
                } catch {
                    failed += 1
                    let description = group.map(Self.describeOperation).joined(separator: " + ")
                    failureLines.append("Could not \(description): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value

        // Scan first, log after — see `removeUselessFiles`'s own comment on
        // this exact reordering.
        await scan(system: system)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Handled \(succeeded) corrupted file(s); \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Handled \(succeeded) corrupted file(s).")
        } else {
            logWarning("Nothing to handle — no internally-corrupt rom found, or the configured policy has nothing to do.")
        }
    }

    /// How many clones "Merge Clones (Merged)…" would actually fold into
    /// their parent and delete, without touching disk. Returns `0` before
    /// any scan has run. See `RebuildPlanner.planConvertToMerged`'s own
    /// doc comment for exactly which clones qualify.
    func planConvertToMergedPreviewCount() -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        return RebuildPlanner.planConvertToMerged(matchReport: matchReport).count
    }

    /// Folds every clone's own unique roms into its parent's archive, then
    /// deletes the clone's whole archive — Fase 2 Step 4, the "Merged"
    /// direction. Each clone's own operation GROUP (every add, THEN that
    /// clone's own delete, listed last) is executed together — the delete
    /// only ever runs if every add before it in the SAME group already
    /// succeeded (see `RebuildPlanner.planConvertToMerged`'s own doc
    /// comment for why this ordering alone is the whole safety argument,
    /// no separate verification pass needed). A failed group means that
    /// ONE clone's archive survives, untouched; every other clone's own
    /// group is unaffected.
    func convertToMerged(system: RomSystem) async {
        guard Self.modificationsEnabled else {
            logError("This is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return
        }
        isBusy = true
        defer { isBusy = false }

        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let groups = RebuildPlanner.planConvertToMerged(matchReport: matchReport)
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for group in groups {
                do {
                    try RebuildExecutor.execute(group)
                    succeeded += 1
                } catch {
                    failed += 1
                    let description = group.map(Self.describeOperation).joined(separator: " + ")
                    failureLines.append("Could not \(description): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value

        // Scan first, log after — see `removeUselessFiles`'s own comment on
        // this exact reordering.
        await scan(system: system)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Merged \(succeeded) clone(s) into their parent; \(failed) failed partway through and were left untouched (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Merged \(succeeded) clone(s) into their parent.")
        } else {
            logWarning("Nothing to merge — no clone in this scan qualifies (see the toolbar action's own help text for what disqualifies one).")
        }
    }

    /// A short, human-readable description of what a single
    /// `RebuildOperation` actually does — jensyleo's own instruction
    /// (2026-09-10) to review the whole app's logging for coherence
    /// surfaced this as a real, SYSTEMIC gap: `fix()`/`renameRomsInArchive()`
    /// already had their own `failureLines` (per-operation error text,
    /// fixed 2026-09-10 after "la opción de fix sigue sin funcionar" turned
    /// out to be a swallowed-error bug, not a broken planner) — but every
    /// OTHER write action still had the exact same shape:
    /// `catch { failed += 1 }` swallows the real error entirely, while the
    /// summary line right below it promises "see above for which" with
    /// nothing ever actually logged above. This one helper lets every
    /// write action produce that missing line uniformly instead of
    /// duplicating a `switch` over `RebuildOperation` eight separate times.
    private nonisolated static func describeOperation(_ operation: RebuildOperation) -> String {
        switch operation {
        case .rename(let from, let to):
            return "rename \"\(from.lastPathComponent)\" to \"\(to.lastPathComponent)\""
        case .copy(let from, let to):
            return "copy \"\(from.lastPathComponent)\" to \"\(to.path)\""
        case .move(let from, let to):
            return "move \"\(from.lastPathComponent)\" to \"\(to.path)\""
        case .extractZipEntry(let archive, let entryName, let destination):
            return "extract \"\(entryName)\" from \"\(archive.lastPathComponent)\" to \"\(destination.path)\""
        case .createArchive(_, let destination):
            return "create \"\(destination.lastPathComponent)\""
        case .createTorrentZipArchive(_, let destination):
            return "create \"\(destination.lastPathComponent)\""
        case .delete(let target):
            return "delete \"\(target.lastPathComponent)\""
        case .addEntryToZip(let targetArchive, let entryName, _):
            return "add \"\(entryName)\" to \"\(targetArchive.lastPathComponent)\""
        case .removeEntryFromZip(let archive, let entryName):
            return "remove \"\(entryName)\" from \"\(archive.lastPathComponent)\""
        }
    }

    /// Whether `url` falls under ANY of `scopeFolders` — an EMPTY array (no
    /// specific folder/File selected) always means "in scope", same
    /// convention as `restrictToScope`/`restrictPairsToScope` below.
    /// Factored out of `operationTouchesFolder` so `fix()`'s own
    /// entry-level-mismatch count (computed straight from `matchReport`,
    /// never from a `RebuildOperation`) can respect the same scoping.
    ///
    /// jensyleo's own request (2026-09-10): "la app no permite selección
    /// múltiple" — every Fix action used to accept only ONE scope URL
    /// (a single selected ROM folder, or a single right-clicked File).
    /// Generalized from a single `URL?` to `[URL]` so a multi-selection in
    /// either table can scope a Fix action to every selected File/entry at
    /// once, not just the first — an empty array is the new "unscoped"
    /// (replacing the old `nil`), a single-element array behaves exactly
    /// as the old single-URL scope did, and multiple elements are simply
    /// "in scope if under ANY of these."
    private nonisolated static func urlIsInScope(_ url: URL, scopeFolders: [URL]) -> Bool {
        guard !scopeFolders.isEmpty else { return true }
        let itemPath = url.standardizedFileURL.path
        return scopeFolders.contains { scopeFolder in
            let folderPath = scopeFolder.standardizedFileURL.path
            return itemPath == folderPath || itemPath.hasPrefix(folderPath + "/")
        }
    }

    /// Restricts a planned batch to only the operations touching a file
    /// physically inside one of `scopeFolders` — jensyleo's own report
    /// (2026-09-10): standing on one specific "ROM folder" in the sidebar
    /// and running a Fix action used to act across the WHOLE system
    /// regardless (every configured folder at once), matching "Scan
    /// Folder" existing in name only — that one already scopes to the
    /// selected folder; every Fix action didn't. An EMPTY `scopeFolders`
    /// (no specific folder/File selected — "Database" or nothing) means
    /// "don't restrict at all", preserving the original whole-system
    /// behavior in that case.
    private nonisolated static func restrictToScope(_ operations: [RebuildOperation], scopeFolders: [URL]) -> [RebuildOperation] {
        guard !scopeFolders.isEmpty else { return operations }
        return operations.filter { operationTouchesFolder($0, scopeFolders) }
    }

    /// Same restriction as `restrictToScope` above, but for operations that
    /// must survive or drop TOGETHER as one unit (e.g. the add-then-remove
    /// pair `planRenameRomsInArchive` plans per ROM — both reference the
    /// same target archive, so scoping must check the PAIR's own archive
    /// once, not risk keeping an `.addEntryToZip` while dropping its own
    /// matching `.removeEntryFromZip`, which would leave the entry
    /// duplicated under both names instead of renamed).
    private nonisolated static func restrictPairsToScope(_ operations: [RebuildOperation], scopeFolders: [URL]) -> [RebuildOperation] {
        guard !scopeFolders.isEmpty else { return operations }
        var result: [RebuildOperation] = []
        for pairStart in stride(from: 0, to: operations.count, by: 2) {
            let pair = Array(operations[pairStart..<Swift.min(pairStart + 2, operations.count)])
            guard let first = pair.first, operationTouchesFolder(first, scopeFolders) else { continue }
            result.append(contentsOf: pair)
        }
        return result
    }

    /// One rom entry's own identity for `restrictPairsToEntries` below:
    /// the CONTAINER's own path plus the entry's CURRENT on-disk name
    /// (whatever it's actually named right now — the same real name
    /// `AuditEntry.actualEntryName` carries, not the DAT's declared
    /// `name`, since that's what an add-then-remove pair's own
    /// `sourceArchiveEntryName` reads FROM). Same "container::entry"
    /// convention `ScanCache.key(for:)` already uses, for a single unique
    /// string.
    nonisolated static func entryScopeKey(containerURL: URL, currentEntryName: String) -> String {
        "\(containerURL.path)::\(currentEntryName)"
    }

    /// Restricts a planned add-then-remove PAIR batch to only the ones
    /// whose OWN current entry (container + on-disk name, BEFORE this
    /// rename) is named in `entryKeys` — jensyleo's own report
    /// (2026-09-10): selecting exactly 2 of 5 misnamed roms in the Roms
    /// panel's own multi-selection and running "Fix Misnamed ROMs Inside
    /// This Archive…" renamed all 5, not just the 2 picked. Root cause:
    /// `restrictPairsToScope` above only ever scopes by CONTAINER (a
    /// whole File) — exactly right for the Games table's own selection
    /// (there's no narrower unit than "this File" there), but the Roms
    /// panel's selection is of INDIVIDUAL ENTRIES inside ONE already-
    /// selected game's own container, which container-level scoping
    /// cannot distinguish between at all (every entry shares the same
    /// container). An EMPTY `entryKeys` means "don't restrict any
    /// further" — the Games-table-driven call sites never populate it.
    private nonisolated static func restrictPairsToEntries(_ operations: [RebuildOperation], entryKeys: Set<String>) -> [RebuildOperation] {
        guard !entryKeys.isEmpty else { return operations }
        var result: [RebuildOperation] = []
        for pairStart in stride(from: 0, to: operations.count, by: 2) {
            let pair = Array(operations[pairStart..<Swift.min(pairStart + 2, operations.count)])
            guard case .addEntryToZip(let targetArchive, _, let source) = pair.first,
                  let currentEntryName = source.sourceArchiveEntryName,
                  entryKeys.contains(entryScopeKey(containerURL: targetArchive, currentEntryName: currentEntryName))
            else { continue }
            result.append(contentsOf: pair)
        }
        return result
    }

    /// The one filesystem path a `RebuildOperation` actually touches, for
    /// `restrictToScope`/`restrictPairsToScope` above to compare against
    /// the selected scope — the SOURCE being modified in place, not a
    /// brand-new destination outside any existing folder (`.rename`/
    /// `.copy`/`.move`'s own `from`, `.addEntryToZip`/`.removeEntryFromZip`'s
    /// own target/source archive, `.delete`'s own target). `nil` for a
    /// case with no single existing on-disk file being modified in place
    /// (e.g. `.createArchive`/`.createTorrentZipArchive`, which build
    /// something new at a destination the user picked directly) — treated
    /// as always in-scope, since there's nothing meaningful to restrict.
    private nonisolated static func operationTouchesFolder(_ operation: RebuildOperation, _ scopeFolders: [URL]) -> Bool {
        let path: URL?
        switch operation {
        case .rename(let from, _), .copy(let from, _), .move(let from, _):
            path = from
        case .extractZipEntry(let archive, _, _):
            path = archive
        case .delete(let target):
            path = target
        case .addEntryToZip(let targetArchive, _, _):
            path = targetArchive
        case .removeEntryFromZip(let archive, _):
            path = archive
        case .createArchive, .createTorrentZipArchive:
            path = nil
        }
        guard let path else { return true }
        return urlIsInScope(path, scopeFolders: scopeFolders)
    }
}

private extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
