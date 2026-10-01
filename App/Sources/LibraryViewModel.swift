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

/// TEMP PERF INSTRUMENTATION (2026-09-17, jensyleo's own report of a slow
/// launch) — writes straight to a fixed file path, bypassing the unified
/// system log entirely. `NSLog`/`os_log` output from an ad-hoc-signed app
/// gets redacted to `<private>` by macOS's log privacy filter, which made
/// every earlier attempt at this invisible to `log show` even with the
/// exact right predicate — the same reason this file-based approach was
/// already the proven fallback earlier in this session (the ⌘-drag
/// investigation).
///
/// jensyleo's own instruction (2026-09-26), after this same instrumentation
/// helped find and confirm two real fixes that same day (the sequential
/// zip-comment reads, `indexByID`'s own contention): "desactívalos, pero
/// déjalos listos para activar por si se vuelve a poner lento" — kept in
/// place at every call site rather than ripped out, gated behind this one
/// `isEnabled` switch so re-enabling later never needs re-instrumenting
/// each site by hand again.
enum PerfDebugLog {
    // A plain debug on/off switch, read/written from many different
    // isolation contexts (this whole file's background tasks) — never
    // load-bearing for correctness, only for whether a line gets appended
    // to a debug file, so `nonisolated(unsafe)` here is a deliberate,
    // low-stakes choice, not a shortcut around a real data race.
    nonisolated(unsafe) static var isEnabled = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        let line = "[\(Date())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let path = "/tmp/romforge_perf_debug.log"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

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
    /// When this system's own audit results were last actually produced by
    /// a real scan — `nil` before this system has ever been scanned.
    /// jensyleo's own request (2026-09-14), after twice mistaking a genuine
    /// row from an OLD, since-superseded scan (loaded instantly on open via
    /// `loadPersistedReport`, by design — see that function's own doc
    /// comment) for a live, current problem: surfacing this in the header
    /// lets a visibly-old timestamp warn "these results might not reflect
    /// what's on disk right now" before re-reading a stale "Bad" row as
    /// news. Set both when a persisted report loads on open AND after every
    /// real scan finishes, so it always reflects whichever is more recent.
    var lastScanDate: Date?
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
    /// A short label for whichever real, synchronous post-matching pass is
    /// currently running (disk auditing, duplicate-set detection, orphaned
    /// BIOS, filename/CRC checks, Maintenance donor detection) — jensyleo's
    /// own report (2026-09-19): once `ROMMatcher.match` finished (its own
    /// progress bar at 100%), the overlay kept showing "Comparing against
    /// the database… N of N games" frozen at that same text for however
    /// long these several real passes then took, with nothing telling the
    /// user any of them were even running. `nil` while `isMatching` is
    /// false, or while `ROMMatcher.match` itself is still the thing
    /// running (that phase already has its own real `matchProgress` text).
    var scanPostMatchPhase: String?
    /// True while a finished scan's (or "Verify ZIP Integrity"'s) report is
    /// being written to `AuditReportDatabase` — jensyleo's own report
    /// (2026-09-17): matching finishing (bar at 100%) didn't mean the
    /// operation was actually done. `saveReport` was called directly,
    /// synchronously, on this `@MainActor` class — for a real collection
    /// (323,626 rows) that write itself takes real time, and running it on
    /// the main actor blocked the whole app for that long, on top of
    /// `isMatching` having already reset to its idle state by then (see
    /// this session's own `isMatching`-reset fix), so the overlay fell all
    /// the way through to its generic "Scanning folders…" fallback for a
    /// phase that has nothing to do with folders at all. Moved onto its
    /// own background task (`saveReportInBackground`), with its own honest
    /// label here instead.
    var isSavingReport = false
    /// (completed, total) rows written so far while `isSavingReport` is
    /// true — jensyleo's own report (2026-09-19): "Saving results…" showed
    /// a bare, generic spinner with no numbers, unlike every other phase in
    /// this same overlay. `nil` while `isSavingReport` is false, or before
    /// `AuditReportDatabase.saveEntriesDiffed`'s own first throttled tick.
    var saveReportProgress: (completed: Int, total: Int)?
    /// A short label + (completed, total) progress for whichever Fix/File
    /// Action is currently running its own real file operations —
    /// jensyleo's own report (2026-09-19): "Remove Redundant Files…" only
    /// ever showed the ordinary scan pipeline's own generic overlay phases
    /// ("Scanning folders…", "Saving results…") — both real (the action's
    /// own automatic verification rescan), but nothing in the overlay ever
    /// named the actual file removal itself, or how far along it was.
    /// `nil` whenever no such action is actively running its own
    /// operations (including during its own follow-up rescan, which has
    /// its own separate, already-real progress fields).
    var fixActionProgress: (label: String, completed: Int, total: Int)?
    private(set) var logLines: [LogLine] = []

    /// One Fix/File Action's own success-or-failure summary, for the
    /// pop-up alert `FixResultPopupSettings` gates — jensyleo's own request
    /// (2026-09-11), additive to (never a replacement for) the Log panel's
    /// own lines for the same result. Same one-shot pattern as
    /// `cancelledPhase` above: set once an action's own outcome is known,
    /// cleared by the View once it's actually been shown, so re-showing
    /// the same result twice (e.g. from a spurious `body` re-evaluation)
    /// can never happen.
    struct FixResultAlert: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let isSuccess: Bool
        let message: String
    }
    var fixResultAlert: FixResultAlert?
    /// jensyleo's own follow-up (2026-09-16), after the "Scan Failed"
    /// pop-up landed: "verifica que solo muestre el mensaje al final...
    /// pero igual lo que encuentre sí lo escanee. Los recursos que no
    /// encontró debería marcarlos en rojo". A folder currently in this set
    /// is one the LAST scan that actually covered it couldn't reach —
    /// `ROM folder` rows read this to show a distinct marker. Cleared for
    /// every folder a scan's own scope covers right before that scan
    /// records its own result, so a folder that comes back online (NAS
    /// reconnected) stops being marked the very next time it's scanned —
    /// never left stuck red from a stale failure.
    var lastScanUnreachableFolders: Set<URL> = []

    /// Builds and posts `fixResultAlert` from the same succeeded/failed
    /// counts (and, for a failure, the same per-item reason strings) every
    /// write action already computes for its own Log lines — this never
    /// recomputes anything, just mirrors it into the more visible pop-up
    /// channel. No-ops entirely when `FixResultPopupSettings.isEnabled` is
    /// off, or when there's nothing to report at all (nothing planned,
    /// nothing succeeded, nothing failed — e.g. "Nothing to fix").
    private func postFixResultPopup(action: String, succeeded: Int, failed: Int, failureLines: [String] = []) {
        guard FixResultPopupSettings.isEnabled else { return }
        guard succeeded > 0 || failed > 0 else { return }
        var message: String
        if failed == 0 {
            message = "Succeeded — \(succeeded) item\(succeeded == 1 ? "" : "s")."
        } else if succeeded == 0 {
            message = "Failed — \(failed) item\(failed == 1 ? "" : "s")."
        } else {
            message = "\(succeeded) item\(succeeded == 1 ? "" : "s") succeeded, \(failed) item\(failed == 1 ? "" : "s") failed."
        }
        if !failureLines.isEmpty {
            let shown = failureLines.prefix(8)
            message += "\n\n" + shown.joined(separator: "\n")
            if failureLines.count > shown.count {
                message += "\n… and \(failureLines.count - shown.count) more (see the Log panel for the full list)."
            }
        }
        fixResultAlert = FixResultAlert(title: action, isSuccess: failed == 0, message: message)
    }

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

    private var matchReport: MatchReport? {
        didSet {
            matchedZipArchiveURLsCache = nil
            unscopedFixOperationsCache = nil
            unscopedRenameRomsOperationsCache = nil
        }
    }

    /// `SimilarNameSuggester`'s own live suggestion for the file at `url`,
    /// straight from this session's own last scan — jensyleo's own request
    /// (2026-09-29), right after the settings toggle for this alone didn't
    /// seem to visibly do anything: this surfaces the SAME preview
    /// "Fix Mismatched Files" would act on directly in the Detail panel's
    /// own "Info" row for a gray/surplus entry, so it's visible immediately
    /// after a scan rather than only discoverable by actually running the
    /// Fix action. Deliberately reads the live, in-memory `matchReport`
    /// only, not anything persisted (`AuditEntry`/SQLite) — a genuine
    /// resemblance guess (see `SurplusFile.similarNameSuggestion`'s own doc
    /// comment) isn't the kind of fact worth a schema migration to persist;
    /// re-scanning after a settings change is what refreshes it, same as
    /// every other `ROMMatcher.match` parameter.
    func similarNameSuggestion(forFileAt url: URL) -> SimilarNameSuggestion? {
        matchReport?.surplusFiles.first { $0.file.file.url == url }?.similarNameSuggestion
    }

    /// jensyleo's own request (2026-09-30): "Battle City (J).zip" scored
    /// only 57% against the genuinely correct "BattleCity (Japan) (En)"
    /// (the DAT itself spells the game with no space) — below the fixed
    /// 90% floor `RebuildPlanner.planRepair`'s own BATCH "Fix Mismatched
    /// Files" must never go below (see that floor's own doc comment for
    /// the real wrong-game cases it exists to block), so neither the
    /// context menu nor a folder-wide Fix ever offered it. jensyleo's own
    /// push-back once that floor was explained: "57 es mas de 50 que es
    /// el piso" — he'd already configured this system's own similarity
    /// threshold down to 50% specifically so a suggestion like this one
    /// would surface, and the fixed batch floor was blocking the one
    /// thing that setting was FOR. This is the per-file path: acts on
    /// exactly the suggestion already computed under the existing,
    /// correctly-layered global ("Ignore CRC/Hash Verification")/per-system
    /// (`RomSystem.similarNameFixThreshold`) gate — no separate floor of
    /// its own — for a single file the user already looked at and
    /// confirmed through an explicit dialog, never a silent batch.
    /// Returns before doing anything if `RebuildPlanner
    /// .planSingleSimilarNameRename` finds no actual rename to make (no
    /// suggestion, already correct, or a real collision) — the UI checks
    /// this first (see `LibraryDetailView.startRenameToSimilarNameSuggestion`)
    /// so a real collision is explained BEFORE asking the user to confirm,
    /// not discovered only after they already clicked "Rename".
    func renameToSimilarNameSuggestion(system: RomSystem, url: URL) async {
        guard Self.modificationsEnabled else {
            logError("File Actions are disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let matchReport else { return }
        let scopeFolders = Self.romFolders(containing: [url], in: system)
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        let result = RebuildPlanner.planSingleSimilarNameRename(
            matchReport: matchReport, fileURL: url, filesCasePolicy: FixPreferencesSettings.currentSetsCasePolicy()
        )
        guard case .rename(let operation) = result, case .rename(_, let destination) = operation else {
            logWarning("\(url.lastPathComponent): nothing to rename (the suggestion is no longer available — try rescanning).")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                try RebuildExecutor.execute([operation])
            }.value
            logSuccess("Renamed \"\(url.lastPathComponent)\" to \"\(destination.lastPathComponent)\".")
            await scan(system: system, folders: scopeFolders)
        } catch {
            logError("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Real perf bug found live by jensyleo (2026-09-22): right after
    /// "Remove Zip Comment…" was added to the Games table's own context
    /// menu, right-clicking ANY row (and, apparently, general scrolling —
    /// SwiftUI's `.contextMenu(forSelectionType:)` closure can be
    /// re-evaluated more eagerly than just "the menu is actually open")
    /// made the whole app beachball. Root cause:
    /// `RebuildPlanner.matchedZipArchiveURLs(matchReport:)` walks EVERY
    /// game's EVERY rom match in the WHOLE system — not just the
    /// right-clicked File's own scope — to find which archives are even
    /// candidates, before any scope filtering or comment-reading ever
    /// happens. For a real full MAME collection (hundreds of thousands of
    /// matched roms), that's a genuinely expensive synchronous walk, and
    /// it ran again on the main thread every single time this one
    /// preview count was computed — unlike its sibling previews
    /// (`removeUselessCount`/etc.), which only ever scan the much
    /// smaller `surplusFiles` list. The actual candidate set only changes
    /// when `matchReport` itself changes (a real scan completing), so
    /// it's computed once and reused here instead of on every click.
    private var matchedZipArchiveURLsCache: Set<URL>?

    private func matchedZipArchiveURLs(for matchReport: MatchReport) -> Set<URL> {
        if let cached = matchedZipArchiveURLsCache { return cached }
        let urls = RebuildPlanner.matchedZipArchiveURLs(matchReport: matchReport)
        matchedZipArchiveURLsCache = urls
        return urls
    }

    /// This session's own cached Maintenance-folder donor hashes, keyed by
    /// the exact folder path they came from — jensyleo's own report
    /// (2026-09-14): every single scan (even "Scan This Folder" scoped to
    /// one unrelated ROM folder) was re-reading and re-hashing the WHOLE
    /// Maintenance folder from disk, purely to recompute
    /// `MaintenanceDonorDetector`'s own flags — real, avoidable I/O on
    /// every scan click, not just when Maintenance's own contents could
    /// plausibly have changed. Reused across scans within this session
    /// (real donor files only change when the user actually edits that
    /// folder, which only "Scan Maintenance Folder" — seebe `LibraryDetailView
    /// .startScanMaintenanceFolder`'s own doc comment — or "Scan All
    /// Folders" are meant to notice) until explicitly invalidated by
    /// `invalidateMaintenanceDonorCache()`.
    private var cachedMaintenanceDonorFiles: (folderPath: String, files: [HashedFile])?

    /// Forces the next scan (regardless of scope) to re-read the
    /// Maintenance folder from disk instead of reusing
    /// `cachedMaintenanceDonorFiles` — called wherever donor content might
    /// have genuinely changed: "Scan Maintenance Folder" itself, and a full
    /// "Scan All Folders" (the one scan scope broad enough that refreshing
    /// everything, including this, is exactly what it promises).
    func invalidateMaintenanceDonorCache() {
        cachedMaintenanceDonorFiles = nil
    }

    /// Read access to `cachedMaintenanceDonorFiles` for
    /// `LibraryDetailView.loadMaintenanceFolderFiles()` — jensyleo's own
    /// report (2026-09-14): browsing the Maintenance folder re-read and
    /// re-hashed it from scratch every single time (selecting it in the
    /// sidebar, a DAT reload, the toolbar button…), taking ~10s against a
    /// real ~250MB Maintenance folder and reading as "stuck" when
    /// triggered back-to-back — the exact redundant-I/O problem this same
    /// cache was already built to avoid for the donor-detection pass, just
    /// never reused here. Returns `nil` on any mismatch/miss so the caller
    /// always falls back to a real read.
    func cachedMaintenanceDonorFiles(matchingFolderPath folderPath: String) -> [HashedFile]? {
        guard let cachedMaintenanceDonorFiles, cachedMaintenanceDonorFiles.folderPath == folderPath else { return nil }
        return cachedMaintenanceDonorFiles.files
    }

    /// Write access to `cachedMaintenanceDonorFiles` for
    /// `LibraryDetailView.loadMaintenanceFolderFiles()` — see
    /// `cachedMaintenanceDonorFiles(matchingFolderPath:)`'s own doc comment.
    /// A fresh hash computed by either caller populates the ONE shared
    /// cache, so whichever one runs first saves the other a redundant
    /// re-hash of the same folder.
    func cacheMaintenanceDonorFiles(folderPath: String, files: [HashedFile]) {
        cachedMaintenanceDonorFiles = (folderPath, files)
    }

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

    /// Folds a just-finished scan's own scope INTO whatever was already
    /// tracked, rather than replacing it outright — see the call site's
    /// own doc comment (`scan(system:folders:)`) for the real report this
    /// fixes. `nil` (a whole-system scan) always wins outright: it's the
    /// broadest possible coverage, and once reached nothing scoped after
    /// it can ever narrow it back down. Otherwise, any of `folders` not
    /// already covered by the existing scope gets appended — a scan can
    /// only ever ADD coverage, never remove it (nothing here ever
    /// invalidates a folder just because it wasn't part of THIS scan).
    private nonisolated static func mergedScanScope(_ existing: ScanScope?, withNewScan folders: [URL]?) -> ScanScope {
        guard let newFolders = folders else { return .wholeSystem }
        switch existing {
        case .none:
            return .paths(newFolders)
        case .wholeSystem:
            return .wholeSystem
        case .paths(let existingPaths):
            var merged = existingPaths
            for folder in newFolders where !urlIsInScope(folder, scopeFolders: existingPaths) {
                merged.append(folder)
            }
            return .paths(merged)
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

    /// Non-nil while the "Configuration Required" alert should be showing
    /// — same "message on click, not just a log line nobody was watching"
    /// reasoning as `rescanRequiredAlertMessage` right above. Real report,
    /// live (2026-09-24), jensyleo: "si activo la opción sin configurar la
    /// carpeta me sale el error en el log pero la app no muestra mensaje"
    /// — "Organize BIOS Files…"/"Organize Complementary Chips…" (and every
    /// other action gated on a Settings → Systems → MAME folder/toggle
    /// being configured first) used to only ever call `logError`/
    /// `logWarning` for this exact class of guard failure — invisible
    /// unless the Log panel happened to already be in view. Set alongside
    /// that same log line, never instead of it.
    var configurationRequiredAlertMessage: String?

    /// Sets both the Log line and the visible alert together, for the
    /// "you tried a Fix action but its own required Settings toggle/folder
    /// isn't configured" class of guard failure — see
    /// `configurationRequiredAlertMessage`'s own doc comment.
    /// Not `private` — `LibraryDetailView`'s own `startOrganizeBIOSFiles`/
    /// `startOrganizeComplementaryChips` also call this directly (the
    /// toolbar-click path that actually needs it — see their own doc
    /// comment for why the async actions' own guards below almost never
    /// fire in practice).
    func logConfigurationRequired(_ message: String) {
        logError(message)
        configurationRequiredAlertMessage = message
    }

    /// Non-nil while the "Nothing Found" alert should be showing — same
    /// "message on click, not just a log line nobody was watching"
    /// reasoning as `configurationRequiredAlertMessage`/
    /// `rescanRequiredAlertMessage` above. jensyleo's own request
    /// (2026-09-24): "como parte de los fixes de BIOS y Samples y demás,
    /// hay que colocar que si no encuentra nada avise desde la app, no
    /// solo desde el log" — scanning the BIOS/Complementary Chips/Samples
    /// folder specifically (the one place a genuinely empty result is
    /// common and easy to miss) now warns visibly, not just in the Log.
    var scanFoundNothingAlertMessage: String?

    /// Sets both the Log line and the visible alert together — see
    /// `scanFoundNothingAlertMessage`'s own doc comment.
    func logScanFoundNothing(_ message: String) {
        logWarning(message)
        scanFoundNothingAlertMessage = message
    }

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

    /// Same idea, same reason, as `sharedDATCache` just above — jensyleo's
    /// own report (2026-09-26), during a full-session slowness audit: every
    /// switch back to an already-visited system re-read that system's ENTIRE
    /// persisted report from SQLite (`loadPersistedReport` below) and re-ran
    /// `computeGameAggregateStatusByName`'s own full O(entries) pass over it
    /// — not just "the first time the app opens", but literally every
    /// single switch, all session, since `LibraryDetailView`'s `.id(system.id)`
    /// tears down and recreates the owning `LibraryViewModel` (and every
    /// one of its instance-level caches) on every switch. `sharedDATCache`
    /// already solved this exact problem for the DAT half back on
    /// 2026-08-03; this solves the other half — the actual scan RESULT.
    /// Kept updated at every real, authoritative write to `auditReport`
    /// (a fresh persisted-report load, a real scan finishing, a folder
    /// removal, `verifyZipIntegrity`) — see each call site's own comment.
    /// `ContentView`'s own app-launch preload additionally warms this for
    /// every OTHER configured system in the background, not just whichever
    /// one is initially shown, so a first visit to those feels instant too.
    private static var sharedAuditReportCache: [UUID: AuditReport] = [:]

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
        // No `system` param here (called from a notification meaning "the
        // WHOLE app's saved state was just purged", not just this one) —
        // clears every system's entry rather than trying to guess which
        // one this instance was for. Rare, explicit, user-triggered action
        // ("Purge Database View"), so the blunt full clear costs nothing
        // that matters.
        Self.sharedAuditReportCache.removeAll()
        lastScanDate = nil
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
    /// True while `loadPersistedReport` is in flight for the currently
    /// selected system — jensyleo's own report (2026-09-17): even after
    /// `loadReport`'s own SQLite read was parallelized down to ~1.6s (from
    /// 6.5s), the launch delay was still "notorio". Root cause found in the
    /// perf log: `handleCachedDATFileChange()` (`LibraryDetailView.swift`)
    /// unconditionally re-runs the whole expensive
    /// `refreshCachedGameDataAfterAuditReportChangeAsync()` pipeline
    /// (`OneGameOneROMSelector.compute` alone costs ~200ms over a
    /// 50k-game DAT) the moment the DAT finishes preloading — which, now
    /// that SQLite is fast, arrives just BEFORE the real report does, so
    /// this whole ~280ms pass runs against a still-empty report and gets
    /// thrown away moments later when the real one supersedes it. This
    /// flag lets that caller skip its own redundant pass specifically
    /// while it already knows the real, definitive one is imminent —
    /// still runs for a genuinely never-scanned system (this flag settles
    /// to `false` there too, once `loadReport` comes back `nil`), which is
    /// the actual case that call exists for in the first place.
    var isLoadingPersistedReport = false

    /// App-launch background warm-up for a system NOT currently being
    /// shown — `ContentView`'s own `.onAppear` calls this once per every
    /// OTHER configured system, at low priority, right after the initially
    /// selected one loads normally. A static, self-contained read (no
    /// `LibraryViewModel` instance needed, no `@Observable` property gets
    /// touched — nothing is on screen for this system yet) that fills
    /// `sharedAuditReportCache` directly, so the FIRST real visit to that
    /// system this session — whenever it happens — hits the same warm,
    /// instant path a re-visit already gets. A no-op if this system has no
    /// persisted report yet, or if something (a real visit already
    /// starting) beat this to populating the cache first.
    nonisolated static func preloadPersistedReportInBackground(system: RomSystem) async {
        let alreadyCached = await MainActor.run { sharedAuditReportCache[system.id] != nil }
        guard !alreadyCached else { return }
        let systemID = system.id.uuidString
        // The actual SQLite read happens here, OFF the main actor — this
        // whole function is `nonisolated` specifically so `db.loadReport`
        // (a real, possibly multi-second read for a large collection)
        // never touches the main thread, unlike an ordinary `@MainActor`
        // method on this class would force it to.
        guard let report = await Task.detached(priority: .background, operation: { () -> AuditReport? in
            guard let db = try? AuditDatabaseLocation.open() else { return nil }
            return try? db.loadReport(systemID: systemID)
        }).value else { return }
        await MainActor.run {
            guard sharedAuditReportCache[system.id] == nil else { return }
            sharedAuditReportCache[system.id] = report
        }
    }

    func loadPersistedReport(system: RomSystem) {
        guard auditReport == nil else { return }
        // See `sharedAuditReportCache`'s own doc comment — a re-visit to a
        // system already loaded THIS SESSION (by this same call, a real
        // scan, or the app-launch background preload in `ContentView`)
        // serves instantly from RAM, no SQLite read or `Task` hop needed at
        // all.
        if let cached = Self.sharedAuditReportCache[system.id] {
            auditReport = cached
            return
        }
        isLoadingPersistedReport = true
        let systemID = system.id.uuidString
        Task.detached(priority: .userInitiated) { [weak self] in
            // TEMP PERF INSTRUMENTATION (2026-09-17, jensyleo's own report
            // of a slow-to-appear ROM folder on launch) — remove once the
            // bottleneck is identified.
            let t0 = Date()
            do {
                let db = try AuditDatabaseLocation.open()
                let tOpen = Date()
                guard let report = try db.loadReport(systemID: systemID) else {
                    Task { @MainActor [weak self] in self?.isLoadingPersistedReport = false }
                    return
                }
                let tLoad = Date()
                let meta = try? db.loadScanMeta(systemID: systemID)
                let tMeta = Date()
                PerfDebugLog.write("loadPersistedReport: open=\(tOpen.timeIntervalSince(t0))s loadReport=\(tLoad.timeIntervalSince(tOpen))s (\(report.entries.count) entries) loadScanMeta=\(tMeta.timeIntervalSince(tLoad))s")
                Task { @MainActor [weak self] in
                    let tMainStart = Date()
                    guard let self else { return }
                    defer { self.isLoadingPersistedReport = false }
                    guard self.auditReport == nil else { return }
                    self.auditReport = report
                    Self.sharedAuditReportCache[system.id] = report
                    if let meta, let name = meta.datName {
                        self.datHeader = DATHeader(name: name, description: "", version: meta.datVersion ?? "", author: "")
                    }
                    self.lastScanDate = meta?.scannedAt
                    PerfDebugLog.write("loadPersistedReport: mainActorAssign=\(Date().timeIntervalSince(tMainStart))s totalSinceStart=\(Date().timeIntervalSince(t0))s")
                }
            } catch {
                // A missing/corrupt database just means no cached results to
                // show yet — not worth surfacing as a user-facing error.
                Task { @MainActor [weak self] in self?.isLoadingPersistedReport = false }
            }
        }
    }

    /// Writes a finished report to `AuditReportDatabase` off the main
    /// actor — jensyleo's own report (2026-09-17): both call sites used to
    /// run `saveReport` directly, synchronously, right there on this
    /// `@MainActor` class. For a real collection (323,626 rows) that write
    /// itself takes real time, and blocking the main actor for it froze
    /// the whole app (not just the overlay) for however long it took,
    /// right after the matching bar had already reached 100% — the same
    /// "stuck at the end" complaint `isMatching`'s own reset fix this
    /// session was chasing, just one step further down the pipeline.
    /// `nonisolated` (not a method on `self`) so callers can freely `await`
    /// it from within their own `@MainActor` bodies without this itself
    /// hopping back onto the main actor first.
    nonisolated static func saveReportInBackground(_ report: AuditReport, systemID: String, datName: String?, datVersion: String?, scannedAt: Date, onProgress: (@Sendable (Int, Int) -> Void)? = nil) async throws {
        try await Task.detached(priority: .userInitiated) {
            let t0 = Date()
            let db = try AuditDatabaseLocation.open()
            try db.saveReport(report, systemID: systemID, datName: datName, datVersion: datVersion, scannedAt: scannedAt, onProgress: onProgress)
            PerfDebugLog.write("saveReportInBackground: \(report.entries.count) entries in \(Date().timeIntervalSince(t0))s")
        }.value
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
        Self.sharedAuditReportCache[system.id] = auditReport

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
    /// always was. `onComplete` (optional, `nil` for every ordinary caller)
    /// runs right after the scan finishes, on the same `Task` — added
    /// (2026-09-24) specifically so "Scan BIOS/Complementary Chips/Samples
    /// Folder" can check whether anything was actually found there and
    /// warn visibly if not; see `LibraryDetailView
    /// .warnIfSpecialFolderEmpty(_:kind:)`'s own doc comment.
    func startScan(system: RomSystem, folders: [URL]? = nil, onComplete: (() -> Void)? = nil) {
        runningTask?.cancel()
        runningTask = Task {
            await scan(system: system, folders: folders)
            onComplete?()
        }
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
    /// Every folder a scan/match pass actually walks for `system` — its own
    /// configured `romFolderURLs`, plus the configured BIOS folder for a
    /// MAME system, automatically. jensyleo's own request (2026-09-24):
    /// "el sistema agrega la carpeta BIOS que se crea automáticamente,
    /// ¿para qué la declaro como un romfolder? Esto debería aparecer en la
    /// app como una carpeta con características similares a las de
    /// mantenimiento" — right after being told he'd need to add it
    /// manually. He's right that the Maintenance folder is the existing
    /// precedent for "a folder the app itself already knows to check,
    /// with no manual ROM-folder entry needed" — but Maintenance's own
    /// automatic check (`scan`'s own "Checking the Maintenance folder for
    /// donors…" phase) only ever flags a MISSING rom as "a donor is
    /// available", it never actually satisfies the match — the file still
    /// needs a real "Find ROMs…" copy to count as
    /// present. The BIOS folder is different in kind: "Organize BIOS
    /// Files…" physically MOVES a BIOS's own real container out of its
    /// ROM folder — the exact same real file, just at a new path — so
    /// treating it as "still not really there" the way Maintenance
    /// donors are would make every game needing that BIOS show
    /// "missing" the moment the very feature meant to tidy things up
    /// runs. Folding the BIOS folder directly into what gets scanned and
    /// matched (this is the ONE place `scan(system:folders:)` reads
    /// `system.romFolderURLs` from — `allFolders` — everything else in
    /// that function, `pathsToWalk`/`scannedScope`/`configuredFolders`,
    /// derives from it) is what makes a moved BIOS keep showing correct,
    /// with no extra manual step. Never appears in `system.romFolderURLs`
    /// itself, so it stays invisible in the ROM-folder sidebar/Settings
    /// folder list — exactly like the Maintenance folder.
    private nonisolated static func effectiveScanFolders(for system: RomSystem) -> [URL] {
        var folders = system.romFolderURLs
        guard system.isMAMEStyle else { return folders }
        if let biosFolder = BIOSFolderSettings.folderURL, !folders.contains(biosFolder) {
            folders.append(biosFolder)
        }
        // Same reasoning as the BIOS folder right above — jensyleo's own
        // request (2026-09-24): "lo mismo que BIOS pero para los demás
        // chips."
        if let chipsFolder = ComplementaryChipsFolderSettings.folderURL, !folders.contains(chipsFolder) {
            folders.append(chipsFolder)
        }
        // jensyleo's own request (2026-09-24): "impleméntalo" (Samples,
        // "lo mismo que BIOS") — walked here so it can be browsed/scanned
        // like any other folder, but its content is filtered OUT of the
        // actual match pipeline right below (see `SamplesFolderSettings
        // .isUnderSamplesFolder`'s own doc comment for why: samples have
        // no DAT hash to match against at all).
        if let samplesFolder = SamplesFolderSettings.folderURL, !folders.contains(samplesFolder) {
            folders.append(samplesFolder)
        }
        return folders
    }

    /// Exactly the `folders` this specific `scan(system:folders:)` call was
    /// given — `nil` for a whole-system scan — never the cumulative
    /// `lastScanScope` (which only ever widens and answers a different
    /// question, "is X covered by everything scanned so far this session").
    /// jensyleo's own report (2026-09-26): after "Remove Zip Comments…"
    /// scoped to one folder, the Info column took "more than a minute" to
    /// stop showing the stale "Has ZIP comment" for files whose comment
    /// had already been stripped — `LibraryDetailView`'s own
    /// `.onChange(of: auditReport)` called `zipCommentCache.invalidateAll()`
    /// unconditionally on ANY scan completing, forcing a fresh re-read of
    /// EVERY zip's comment across the WHOLE collection (up to tens of
    /// thousands of archives) just because 9 files in one folder actually
    /// changed. Read there to invalidate only what this scan could
    /// plausibly have touched.
    private(set) var lastScanFolders: [URL]?

    func scan(system: RomSystem, folders: [URL]? = nil) async {
        lastScanFolders = folders
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
        scanPostMatchPhase = nil
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
        let allFolders = Self.effectiveScanFolders(for: system)
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
            // jensyleo's own report (2026-09-19): once `ROMMatcher.match`
            // itself finished (its own `matchProgress` bar at 100%), the
            // overlay kept showing that same frozen text for however long
            // the several real, synchronous passes below (disk auditing,
            // duplicate-set detection, orphaned BIOS, filename/CRC checks,
            // Maintenance donor detection) then took — none of them are
            // internally progress-reportable (each is a single synchronous
            // pass over the report, not a per-item loop worth throttling
            // like `ScanProgressCounter` does), so this just names whichever
            // one is currently running instead of leaving the text stale.
            let postMatchPhaseHandler: @Sendable (String?) -> Void = { [weak self] phase in
                Task { @MainActor in self?.scanPostMatchPhase = phase }
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
            // Captured here, on the MainActor, before this scan's own
            // detached work starts — `cachedMaintenanceDonorFiles` is
            // MainActor-isolated state, so it can't be read directly from
            // inside `Task.detached` below. See that property's own doc
            // comment for why this cache exists at all.
            let cachedMaintenanceDonor = cachedMaintenanceDonorFiles
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
                // jensyleo's own philosophy statement (2026-09-13): the
                // Maintenance folder is purely a DONOR source for "Repair
                // from Maintenance Folder…"/"Replace Corrupted ROMs…" — it
                // must never be pulled into this system's own audit at all,
                // so nothing in it can ever be flagged surplus/duplicate/
                // redundant, or count toward Correct/Missing/etc. That's
                // already true by construction (`system.romFolderURLs` never
                // includes it), but only as long as the Maintenance root
                // happens to live OUTSIDE every configured ROM folder's own
                // directory tree — `FolderScanner.scan` has no concept of
                // "Maintenance" and would happily walk straight into it if a
                // user ever chose (or nested) it that way. Filtered out
                // here, defensively, right where files enter the audit
                // pipeline — a no-op (`isUnderMaintenanceFolder` is always
                // `false`) whenever no root is configured, or it simply
                // isn't nested under anything being scanned.
                // jensyleo's own report (2026-09-16): "¿Está parando ante
                // la primera carpeta que no encuentra? ¿Revisa las demás o
                // solo para en la primera?" — confirmed real: without this
                // callback, one unreachable folder (a NAS gone offline)
                // used to abort the walk for every OTHER configured folder
                // too, even healthy local ones. Collected here (safe to
                // mutate directly — every call happens sequentially in
                // `FolderScanner.scan`'s own top-level loop, never
                // concurrently) so the scan can still cover every reachable
                // folder, with the unreachable one(s) reported afterward
                // instead of silently skipped or fatal to the whole run.
                var failedFolders: [(url: URL, name: String, message: String)] = []
                let scannedFiles = try FolderScanner.scan(
                    paths: pathsToWalk, onFileFound: folderProgressHandler, onSkippedTooDeep: skippedTooDeepHandler,
                    onFolderStarted: folderStartedHandler,
                    onFolderFailed: { url, error in
                        failedFolders.append((url, url.lastPathComponent, error.localizedDescription))
                    }
                )
                .filter { !MaintenanceFolderSettings.isUnderMaintenanceFolder($0.url) && !SamplesFolderSettings.isUnderSamplesFolder($0.url) }
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
                // jensyleo's own explicit rule (2026-09-16): whichever
                // folder was just scanned should be the one that loses a
                // cross-folder duplicate claim, not whichever happens to
                // sort first alphabetically — see `ROMMatcher.match`'s own
                // `recentlyScannedPaths` doc comment. `forcedRescanPaths`
                // is already exactly "what this specific scan call was
                // actually asked to (re)read" (empty for a full "Scan All
                // Folders", where there's no meaningful "last folder" to
                // favor either way).
                // `!system.isMAMEStyle` — jensyleo's own scoping decision
                // (2026-09-28): this global toggle only ever applies to a
                // console/computer system's own scan, never an arcade/MAME
                // one, regardless of the setting's own value. See
                // `MatchingPreferencesSettings`'s own doc comment
                // (`GeneralSettingsView.swift`) and `ROMMatcher.match`'s own
                // `nameOnlyMatching` parameter doc comment for the full
                // reasoning.
                let matchReport = try ROMMatcher.match(
                    dat: dat, hashedFiles: hashedFiles, onProgress: matchProgressHandler, cancellationFlag: cancellationFlag,
                    recentlyScannedPaths: forcedRescanPaths,
                    nameOnlyMatching: !system.isMAMEStyle && MatchingPreferencesSettings.nameOnlyMatchingEnabled,
                    // Same MAME-never-eligible scoping as `nameOnlyMatching`
                    // just above, and for the same reason — see
                    // `RomSystem.similarNameFixEnabled`'s own doc comment.
                    // ALSO requires "Ignore CRC/Hash Verification" itself to be on —
                    // jensyleo's own explicit call (2026-09-29): a rename
                    // suggested purely by name resemblance only makes sense
                    // alongside the same toggle that already means "trust
                    // this collection's file names over strict hash
                    // verification" — never independently of it.
                    nameSimilarityThreshold: (
                        !system.isMAMEStyle && system.similarNameFixEnabled && MatchingPreferencesSettings.nameOnlyMatchingEnabled
                    ) ? system.similarNameFixThreshold : nil
                )
                postMatchPhaseHandler("Generating the report…")
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
                    postMatchPhaseHandler("Auditing CHDs…")
                    let diskEntries = try DiskAuditor.audit(dat: dat, chdFiles: chdFiles, duplicatePreference: FixPreferencesSettings.currentCHDDuplicatePreference())
                    auditReport = try AuditReporter.merging(diskEntries: diskEntries, into: auditReport)
                }
                // Several ROM folders per system is common (different
                // drives, region subfolders) — this flags a game whose set
                // is physically duplicated across more than one of them,
                // with its own dedicated row rather than only the scattered
                // per-rom "Not needed here" surplus reporting that already
                // exists. Run last, after every other pass has settled the
                // real per-rom statuses this reads.
                // `forcedRescanPaths` — same signal `ROMMatcher.match` above
                // just used — keeps the "Duplicate set" (blue) primary-folder
                // pick from contradicting the per-rom "Duplicated archive,
                // not needed here" (yellow) flag for the exact same game
                // (found live during today's own duplicate-handling audit).
                postMatchPhaseHandler("Detecting duplicate sets…")
                auditReport = try AuditReporter.addingDuplicateSets(to: auditReport, rootFolders: Self.effectiveScanFolders(for: system), recentlyScannedPaths: forcedRescanPaths)
                // Flags a BIOS archive nothing currently present actually
                // needs (e.g. `neogeo.zip` sitting unused once every
                // Neo-Geo game that used to depend on it was removed) — a
                // pure flag on rows this same report already computed, so
                // it can run after every other pass has settled them.
                postMatchPhaseHandler("Checking for orphaned BIOS files…")
                auditReport = AuditReporter.markingOrphanedBIOS(in: auditReport)
                // Flags a TOSEC/GoodTools embedded-filename-CRC vs
                // actual-content mismatch — cheap enough (filename parsing
                // plus a string compare against a hash already computed
                // above, no extra file reads) to run on every scan, unlike
                // the ZIP-internal-CRC check below.
                postMatchPhaseHandler("Checking filename/CRC consistency…")
                auditReport = AuditReporter.markingFilenameCRCMismatches(in: auditReport)
                // Flags a `.missing`/`.badDump`/`.foundElsewhere` rom whose
                // exact declared content is already sitting in this
                // system's own Maintenance folder — jensyleo's own request
                // (2026-09-14), after confirming live that "Find ROMs…"
                // already correctly plans this exact repair: the remaining
                // gap was purely visual, a donor already staged for a
                // missing rom looked identical to one with no fix in sight
                // at all. Cheap enough to run on every scan (the
                // Maintenance folder is typically a small staging area, not
                // a full collection).
                //
                // jensyleo's own follow-up report (2026-09-26), a real
                // screenshot: a game whose missing roms all showed
                // "Available in another game (sf2acc.zip)" etc. — i.e.
                // genuinely `.foundElsewhere`, already-hashed content sitting
                // in this SAME system's own ROM folder — still had no "Find
                // ROMs…" entry in its context menu. Root cause: this
                // detector's own `donorFiles` used to come ONLY from a
                // separate Maintenance-folder hash pass, even though "Find
                // ROMs…" itself (once its Settings → Fix scope picker was
                // removed the same day) always additionally searches every
                // one of the system's own configured ROM folders when
                // unscoped. Re-hashing every configured ROM folder again
                // here purely for this visual hint would reintroduce
                // exactly the kind of NAS-heavy, whole-collection cost this
                // session already fought hard to eliminate elsewhere — so
                // instead, `inScanHashedFiles` below reuses hashes THIS SAME
                // scan already computed for every OTHER game's own
                // `.correct`/`.misnamed` rom (zero extra disk I/O): that's
                // precisely the content a `.foundElsewhere` rom is already
                // known to be borrowing from. Maintenance donors (if any)
                // are still layered on top, so a rom repairable from EITHER
                // source gets flagged.
                // Real perf regression found live by jensyleo (2026-09-26),
                // reported as general app-wide slowness that "improved a
                // bit but persisted" after other fixes that same session:
                // this whole block (including the flatMap just below) used
                // to run unconditionally on EVERY scan, even a trivial
                // "Rescan This File" on a collection with nothing wrong at
                // all — a full pass over every game's every rom in the
                // ENTIRE system (`matchReport.games`, up to the whole real
                // collection), just to look for a donor NOTHING actually
                // needs. `.missing`/`.badDump`/an `.incorrect` entry with
                // `foundElsewhereArchiveName` set are the only three things
                // this detector could ever mark — `auditReport.incorrect == 0`
                // doesn't perfectly rule out that last case on its own, but
                // `foundElsewhereArchiveName` is only ever set on an
                // `.incorrect` entry, so `auditReport.incorrect == 0` still
                // proves none exist. Skips the entire pass (including the
                // Maintenance-folder hash read below) whenever all three
                // are zero — the common case for an already-healthy scan.
                if auditReport.missing > 0 || auditReport.badDump > 0 || auditReport.incorrect > 0 {
                let inScanHashedFiles: [HashedFile] = matchReport.games.flatMap { gameResult in
                    gameResult.matches.compactMap { romMatch -> HashedFile? in
                        switch romMatch.status {
                        case .correct(let file, _), .misnamed(let file, _): return file
                        default: return nil
                        }
                    }
                }
                var donorFiles = inScanHashedFiles
                if let maintenanceFolder = MaintenanceFolderSettings.subfolderURL(for: system) {
                    postMatchPhaseHandler("Checking the Maintenance folder for donors…")
                    let maintenanceDonorFiles: [HashedFile]
                    if let cachedMaintenanceDonor, cachedMaintenanceDonor.folderPath == maintenanceFolder.path {
                        // Reuse this session's cached hashes instead of
                        // re-reading/re-hashing the whole Maintenance folder —
                        // jensyleo's own report (2026-09-14): every scoped
                        // "Scan This Folder" click was redundantly re-scanning
                        // Maintenance too. Only a real Maintenance rescan
                        // ("Scan Maintenance Folder"/"Scan All Folders") calls
                        // `invalidateMaintenanceDonorCache()`, so this branch is
                        // safe to trust until one of those explicitly refreshes it.
                        maintenanceDonorFiles = cachedMaintenanceDonor.files
                    } else if let maintenanceFiles = try? FolderScanner.scan(paths: [maintenanceFolder]), !maintenanceFiles.isEmpty {
                        let freshDonorFiles = (try? await CollectionHasher.hash(scannedFiles: maintenanceFiles, algorithms: HashAlgorithmSettings.current)) ?? []
                        maintenanceDonorFiles = freshDonorFiles
                        // jensyleo's own audit request (2026-09-28): no
                        // `[weak self]` here — the enclosing scope already
                        // captures `self` strongly (this whole block runs
                        // inside `scan()`'s own outer detached task, which
                        // needs `self` alive regardless), so a weak
                        // capture here bought no real safety, just an
                        // inconsistent-capture-style warning.
                        let folderPath = maintenanceFolder.path
                        Task { @MainActor in
                            self.cachedMaintenanceDonorFiles = (folderPath, freshDonorFiles)
                        }
                    } else {
                        maintenanceDonorFiles = []
                    }
                    donorFiles += maintenanceDonorFiles
                }
                if !donorFiles.isEmpty {
                    auditReport = MaintenanceDonorDetector.markingDonorsAvailable(in: auditReport, matchReport: matchReport, donorFiles: donorFiles)
                }
                }
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
                return (dat.header, matchReport, auditReport, dat, freshlyParsed, freshlyParsedIdentity, freshlyObservedPaths, failedFolders)
            }
            cancelDetachedWork = { detached.cancel() }
            let (header, report, audit, dat, freshlyParsed, freshlyParsedIdentity, freshlyObservedPaths, failedFolders) = try await detached.value
            // jensyleo's own follow-up (2026-09-16): "verifica que solo
            // muestre el mensaje al final... pero igual lo que encuentre
            // sí lo escanee. Los recursos que no encontró debería
            // marcarlos en rojo" — updated here, once, after the WHOLE
            // scan (walk + hash + match) has finished, not mid-walk. Only
            // folders THIS scan's own scope actually covered (`pathsToWalk`,
            // captured below as part of the detached closure) are
            // cleared/re-marked — a folder outside this scan's scope keeps
            // whatever a PRIOR scan already determined about it.
            let scannedScope = forcedRescanPaths.isEmpty ? allFolders : forcedRescanPaths
            lastScanUnreachableFolders.subtract(scannedScope)
            lastScanUnreachableFolders.formUnion(failedFolders.map(\.url))
            // jensyleo's own report (2026-09-17): right after "Remove
            // Redundant File(s)…" correctly deleted a redundant archive
            // on purpose, its own automatic post-Fix verification rescan
            // (scoped to that exact, now-intentionally-gone path) reported
            // it through this SAME "Scan Failed"/"Couldn't reach" channel
            // — designed for a genuinely alarming case (a NAS gone
            // offline, a whole configured ROM folder disappearing) —
            // making an entirely expected, successful deletion read as a
            // scary failure. The two cases are told apart here: a whole
            // CONFIGURED folder (`system.romFolderURLs`) going unreachable
            // is always worth the alert, whatever the underlying error —
            // but a narrower path (typically the single file a scoped
            // Fix-verification rescan targets) that's simply gone
            // (`ScannerError.folderNotFound`, not some other read/permission
            // error) during a SCOPED rescan is treated as ordinary,
            // expected information instead: logged plainly, never
            // surfaced as "Scan Failed". A non-"not found" error (a real
            // read failure) on ANY path still alerts, scoped or not.
            let configuredFolders = Set(allFolders)
            func isExpectedGoneRatherThanAFailure(_ failure: (url: URL, name: String, message: String)) -> Bool {
                guard !forcedRescanPaths.isEmpty, !configuredFolders.contains(failure.url) else { return false }
                return failure.message == ScannerError.folderNotFound(failure.url).localizedDescription
            }
            let alarmingFailures = failedFolders.filter { !isExpectedGoneRatherThanAFailure($0) }
            let expectedGoneFailures = failedFolders.filter { isExpectedGoneRatherThanAFailure($0) }
            for failure in alarmingFailures {
                logError("Couldn't reach \(failure.url.path): \(failure.message)")
            }
            for failure in expectedGoneFailures {
                log("\(failure.name) is gone (likely just removed by a Fix action) — the rest of the scoped rescan still completed normally.")
            }
            if !alarmingFailures.isEmpty {
                fixResultAlert = FixResultAlert(
                    title: "Scan Failed",
                    isSuccess: false,
                    message: alarmingFailures.count == 1
                        ? "Couldn't reach \(alarmingFailures[0].name): \(alarmingFailures[0].message)\n\nEvery other reachable folder was still scanned normally."
                        : "\(alarmingFailures.count) folders couldn't be reached:\n\n" + alarmingFailures.map { "\($0.name): \($0.message)" }.joined(separator: "\n") + "\n\nEvery other reachable folder was still scanned normally."
                )
            }
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
            //
            // jensyleo's own report (2026-09-13): "rescaneo una carpeta,
            // hago fix de un archivo, luego trato de hacer fix en otro
            // archivo... me vuelve a pedir rescan" — this used to just
            // overwrite `lastScanScope` with THIS scan's own scope,
            // however narrow. A scoped Fix's own automatic verification
            // rescan (`fix()`'s own `scan(folders: effectiveScopeFolders)`
            // call, right above where it logs its result) is scoped to
            // only the File(s) it just touched — far narrower than the
            // whole folder a real "Scan Folder" had already covered a
            // moment earlier — so that single-file rescan was silently
            // discarding the broader coverage the user had already
            // established, and the very next Fix on a DIFFERENT file in
            // that same already-scanned folder failed the coverage check
            // for no real reason. `Self.mergedScanScope` accumulates
            // instead: a narrower scan's own scope is folded INTO
            // whatever was already tracked, never replacing broader
            // coverage that's still genuinely valid.
            lastScanScope = Self.mergedScanScope(lastScanScope, withNewScan: folders)
            auditReport = displayedAudit
            Self.sharedAuditReportCache[system.id] = auditReport
            scanProgress = nil
            folderScanFilesFound = nil
            currentlyScanningFolder = nil
            archiveListingProgress = nil
            // jensyleo's own report (2026-09-17): "Verify ZIP Integrity"
            // (and by the same mechanism, any other `isBusy` action run
            // after a successful scan) showed the scan's own frozen
            // "Comparing against the database… N of N games" text the
            // whole time it ran, completely unrelated to what it was
            // actually doing. Root cause: only the `catch` branches below
            // (cancellation, error) ever reset `isMatching`/`matchProgress`
            // back to their idle state — a scan that finishes normally,
            // the common case, left `isMatching` stuck `true` forever
            // after, since `scanProgressOverlay` checks that flag before
            // any of the other progress indicators this success path DOES
            // clear above.
            isMatching = false
            matchProgress = nil
            scanPostMatchPhase = nil
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
            let scanFinishedAt = Date()
            lastScanDate = scanFinishedAt
            isSavingReport = true
            saveReportProgress = nil
            // jensyleo's own report (2026-09-21): after a scoped scan's own
            // "Done in Xs…" line, the Log stayed silent for the whole
            // diffed-SQLite-save step (`saveReportInBackground`) — visible
            // only as the overlay's own progress bar, never as a Log line
            // — reading as the app having frozen ("se quedó escaneando
            // folders") even though it was genuinely still working. This
            // names the phase explicitly, with its own elapsed time, so a
            // slow save (a large persisted collection's diff can
            // legitimately take tens of seconds) reads as "still working"
            // rather than "stuck".
            log("Updating database…")
            let saveStartedAt = Date()
            let saveProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] completed, total in
                Task { @MainActor in self?.saveReportProgress = (completed, total) }
            }
            do {
                try await Self.saveReportInBackground(
                    audit, systemID: system.id.uuidString, datName: header.name, datVersion: header.version, scannedAt: scanFinishedAt,
                    onProgress: saveProgressHandler
                )
                log(String(format: "Database updated in %.1fs.", Date().timeIntervalSince(saveStartedAt)))
            } catch {
                logWarning("Couldn't persist this scan's results: \(error)")
            }
            isSavingReport = false
            saveReportProgress = nil
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
            scanPostMatchPhase = nil
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
            scanPostMatchPhase = nil
            logError("Failed: \(String(describing: error))")
            // jensyleo's own report (2026-09-16): scanning a ROM folder
            // that lives on a NAS, with the NAS currently unreachable,
            // only ever showed up as a Log panel line — easy to miss,
            // unlike a Fix action's own pop-up. Reuses the same
            // `fixResultAlert` channel (never gated behind
            // `FixResultPopupSettings.isEnabled`, unlike a routine Fix
            // completion — a scan that genuinely failed to even reach the
            // folder is a real problem the user needs to see, not a
            // "nice to know" notification they might reasonably turn off).
            fixResultAlert = FixResultAlert(
                title: "Scan Failed",
                isSuccess: false,
                message: error.localizedDescription
            )
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
        Self.sharedAuditReportCache[system.id] = auditReport
        let mismatchCount = verified.entries.filter(\.hasInternalZipCRCMismatch).count
        log(
            mismatchCount == 0
                ? "ZIP integrity check done: no internal CRC inconsistencies found."
                : "ZIP integrity check done: \(mismatchCount) entr\(mismatchCount == 1 ? "y" : "ies") with an internal CRC mismatch.",
            kind: mismatchCount == 0 ? .success : .warning
        )
        isSavingReport = true
        saveReportProgress = nil
        log("Updating database…")
        let saveStartedAt = Date()
        let saveProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in self?.saveReportProgress = (completed, total) }
        }
        do {
            if let meta = try AuditDatabaseLocation.open().loadScanMeta(systemID: system.id.uuidString) {
                try await Self.saveReportInBackground(
                    verified, systemID: system.id.uuidString, datName: meta.datName, datVersion: meta.datVersion, scannedAt: meta.scannedAt,
                    onProgress: saveProgressHandler
                )
                log(String(format: "Database updated in %.1fs.", Date().timeIntervalSince(saveStartedAt)))
            }
        } catch {
            logWarning("Couldn't persist the ZIP integrity check's results: \(error)")
        }
        isSavingReport = false
        saveReportProgress = nil
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
        // Real bug found live by jensyleo (2026-09-22): this used to show a
        // real, nonzero count from a STALE `matchReport` — e.g. left over
        // from an earlier whole-system scan, or from SQLite on launch —
        // even when the LAST actual scan only covered a narrower scope
        // (say, one folder's own "Rescan" button). The menu enabled, the
        // confirmation dialog promised "Fix N mismatched files", and only
        // AFTER the user confirmed did `fix()`'s own `scopeCoveredByLastScan`
        // guard refuse and demand a rescan — a real action that visibly
        // "did tasks" (built the preview, showed the dialog) yet fixed
        // nothing. Every preview count below gets the exact same guard its
        // own execute function already has, so a scope the last scan
        // didn't cover now shows 0 up front instead of a false promise.
        //
        // Silent (no `logRescanRequiredForFix` alert) — unlike the
        // whole-system-only actions below, this one is also called from
        // `GameTreeTableView`'s own context-menu construction closure
        // (evaluated on every right-click, sometimes more eagerly than
        // that — see that closure's own doc comment), so popping a modal
        // alert from in here would fire it spuriously just from Browse,
        // never mind an actual click. A 0 here just hides the menu item,
        // same as "no scan yet at all" already does.
        guard scopeCoveredByLastScan(scopeFolders) else { return 0 }
        return Self.restrictToScope(unscopedFixOperations(matchReport: matchReport), scopeFolders: scopeFolders).count
    }

    /// Real perf bug found live by jensyleo (2026-09-22) — same class as
    /// `matchedZipArchiveURLsCache`'s own doc comment: `planRepair`/
    /// `planApplySetsCasePolicy` each walk EVERY game's EVERY rom match in
    /// the whole system, unscoped, and this ran again on every single
    /// right-click (the Games table's own context menu computes this
    /// preview for whichever File was clicked). The result only changes
    /// when `matchReport` itself changes OR the case policy setting does
    /// (rare, user-driven) — cached against both, recomputed only when
    /// either actually differs from what's cached.
    private var unscopedFixOperationsCache: (policy: FileCasePolicy, operations: [RebuildOperation])?

    private func unscopedFixOperations(matchReport: MatchReport) -> [RebuildOperation] {
        let filesCasePolicy = FixPreferencesSettings.currentSetsCasePolicy()
        if let cached = unscopedFixOperationsCache, cached.policy == filesCasePolicy { return cached.operations }
        let mismatchOperations = RebuildPlanner.planRepair(matchReport: matchReport, filesCasePolicy: filesCasePolicy)
        let caseOnlyOperations = RebuildPlanner.planApplySetsCasePolicy(matchReport: matchReport, policy: filesCasePolicy)
        let operations = mismatchOperations + caseOnlyOperations
        unscopedFixOperationsCache = (filesCasePolicy, operations)
        return operations
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
        // corrected name is styled — read inside `unscopedFixOperations`
        // below, always applied.

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
        // `planRepair` itself now only ever plans a genuine File-level
        // rename (a loose file's own name, or a whole misnamed archive's
        // own container name) — an entry mismatch INSIDE an otherwise-
        // correctly-named archive is never touched by it at all (see
        // `planRepair`'s own doc comment), so every operation it returns
        // is eligible here, no separate filtering needed.
        //
        // jensyleo's own report (2026-09-10): 26 loose lowercase archives,
        // "Sets case" set to Uppercase, ran "Fix Mismatched Files" and got
        // "nothing to fix" — correctly, by this action's OLD, narrower
        // definition (nothing there disagreed with the DAT), but not by
        // his own, which matches ClrMamePro's actual model: one "Fix"
        // pass applies every configured policy at once, including
        // re-styling a name that's already otherwise correct. That was
        // split into a separate "Apply Case Policy…" action instead —
        // technically reachable, but two buttons sharing one Settings
        // toggle ("Sets case") reads as a collision rather than two
        // distinct features. Folding `planApplySetsCasePolicy` into THIS
        // same pass makes "Fix Mismatched Files" match ClrMamePro's model
        // for real: it repairs a wrong name AND re-cases an already-
        // correct one, in one click, exactly as its own doc comment on
        // `applyCasePolicy` already claimed the app does. The two plans
        // never target the same File: `planRepair` only ever touches a
        // `.misnamed` anchor, `planApplySetsCasePolicy` only ever a
        // `.correct` one whose OWN name already matches the DAT apart
        // from case (see that function's own doc comment) — mutually
        // exclusive by construction, so there's no double-rename risk in
        // combining them. Computed via the cached `unscopedFixOperations`
        // (main-actor-isolated) BEFORE entering `Task.detached` — see
        // `unscopedFixOperationsCache`'s own doc comment.
        let allOperations = unscopedFixOperations(matchReport: matchReport)
        // Real gap found live by jensyleo (2026-09-23), same class as
        // `removeUselessFiles`'s own doc comment: never set
        // `fixActionProgress`, so the overlay fell through to its generic
        // "Scanning folders…" fallback with no moving numbers.
        let fixProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in self?.fixActionProgress = ("Fixing mismatched files…", completed, total) }
        }
        let outcome = await Task.detached(priority: .userInitiated) {
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
            let total = scopedEligible.count
            for (index, operation) in scopedEligible.enumerated() {
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
                fixProgressHandler(index + 1, total)
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
        fixActionProgress = nil
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
            logWarning("Nothing to fix\(scopeSuffix) — every File name already matches the DAT, styled exactly per \"Sets case\" (\(FixPreferencesSettings.currentSetsCasePolicy().rawValue)).")
        }
        postFixResultPopup(action: "Fix Mismatched Files", succeeded: succeeded, failed: failed, failureLines: outcome.failureLines)
    }

    /// How many file operations a "Rebuild to Folder…" against `destination`
    /// would actually plan, without touching disk — used to show the user a
    /// real count ("Rebuild 214 files?") before they commit, same caution
    /// pattern as everything else Phase 2 writes. Returns `0` before any
    /// scan has run, same as every other write action's own "scan first"
    /// guard.
    func planRebuildPreviewCount(destination: URL, move: Bool) -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        // Same "rescan required" false-promise class as `planFixPreviewCount`'s
        // own doc comment — `rebuildToFolder` below is whole-system-only.
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return 0
        }
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
        postFixResultPopup(action: "Rebuild to Folder", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// How many files "Remove Useless Files…" would actually delete, without
    /// touching disk — the same preview-before-confirm pattern as
    /// `planRebuildPreviewCount`. Returns `0` before any scan has run.
    ///
    /// jensyleo's own correction (2026-09-13), after live-testing this
    /// action himself and finding it deleted surplus files across every
    /// configured ROM folder at once, not just the one he had selected:
    /// "Remove Useless Files… debe actuar solo en la carpeta
    /// SELECCIONADA." Scoped the same way `fix(system:scopeFolders:)`
    /// already scopes "Fix Mismatched Files" — via `restrictToScope`,
    /// which already knows how to read a path out of every
    /// `RebuildOperation` case this planner ever produces (`.delete`'s own
    /// target, `.removeEntryFromZip`'s own container archive).
    func planRemoveUselessFilesPreviewCount(scopeFolders: [URL]) -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        // Silent on scope mismatch — see `planFixPreviewCount`'s own doc
        // comment: also read from `GameTreeTableView`'s context-menu
        // construction closure, where a modal alert would fire spuriously.
        guard scopeCoveredByLastScan(scopeFolders) else { return 0 }
        return Self.restrictToScope(RebuildPlanner.planRemoveUselessFiles(matchReport: matchReport), scopeFolders: scopeFolders).count
    }

    /// Which of "File(s)"/"ROM(s)" the context menu's own "Remove Useless…"
    /// label should say for this exact scope — real report found live by
    /// jensyleo (2026-09-22): `RebuildPlanner.planRemoveUselessFiles`
    /// itself always handles BOTH a whole loose junk file (`.delete`) AND a
    /// single unrecognized entry inside an otherwise-known archive
    /// (`.removeEntryFromZip`) — unlike "Remove Redundant Files…"/"Remove
    /// Redundant ROMs…", which are genuinely two separate planner
    /// functions/menu items for that exact distinction. The menu item here
    /// always said "File(s)" regardless, even when scoped to a File whose
    /// only useless content is an ENTRY inside it (e.g. "Thunder Zone
    /// (World 4 Players)"'s own `thndzone4.zip` holding two unrecognized
    /// roms) — reading as a naming mismatch against the app's own
    /// established Files/ROMs vocabulary everywhere else.
    enum UselessRemovalKind { case files, roms, mixed }
    func planRemoveUselessFilesPreviewKind(scopeFolders: [URL]) -> UselessRemovalKind {
        guard let matchReport = requireMatchReport() else { return .files }
        let operations = Self.restrictToScope(RebuildPlanner.planRemoveUselessFiles(matchReport: matchReport), scopeFolders: scopeFolders)
        let hasLooseFile = operations.contains { if case .delete = $0 { return true }; return false }
        let hasRomEntry = operations.contains { if case .removeEntryFromZip = $0 { return true }; return false }
        if hasLooseFile && hasRomEntry { return .mixed }
        return hasRomEntry ? .roms : .files
    }

    /// Permanently deletes every file the DAT recognizes nothing about at
    /// all — Fase 2 Step 7, the single most destructive action in the whole
    /// app. `LibraryDetailView`'s own toolbar action always shows its own
    /// confirmation dialog before calling this; there is no "undo" once it
    /// runs. Each deletion is attempted independently (same reasoning as
    /// `rebuildToFolder` above) so one locked/already-gone file doesn't
    /// abort the rest.
    ///
    /// `scopeFolders` is never optional in practice — see
    /// `planRemoveUselessFilesPreviewCount`'s own doc comment for why this
    /// was narrowed to the selected folder only; `LibraryDetailView` never
    /// calls this without one selected. Kept as `[URL]` rather than a bare
    /// `URL`, matching every other scoped Fix action's own signature, so
    /// `restrictToScope`/`scopeCoveredByLastScan` need no special case for
    /// this one action.
    /// "Fix All" — jensyleo's own request (2026-09-29), the last Fase 2 item
    /// left pending: a single action that runs every FULLY AUTOMATIC Fix in
    /// one pass, ClrMamePro-style, instead of clicking through each one by
    /// hand. Deliberately excludes "Rebuild to Folder…" — the one Fix action
    /// that needs the user to pick a destination first, so it can never be
    /// automatic — everything else here needs no input beyond what's
    /// already configured in Settings.
    ///
    /// Order matters, and mirrors how a careful manual pass would go:
    /// 1. Names get fixed first (`fix`/`renameRomsInArchive`) so every later
    ///    step reads a correctly-named file/entry.
    /// 2. The system's own configured set layout (Split/Merged/Non-merged —
    ///    MAME only; a console DAT has no such concept, see
    ///    `RomSystem.isMAMEStyle`'s own doc comment) is normalized BEFORE
    ///    repairing missing content, so a repair lands in its final
    ///    location instead of one a layout change immediately moves again.
    /// 3. Missing/bad content gets repaired (sibling sets, then the
    ///    optional Maintenance folder donor area, then the configured
    ///    corrupted-files policy).
    /// 4. Genuinely destructive cleanup (`nodump` placeholders aside,
    ///    Remove Redundant ROMs/Files, then Remove Useless Files) runs only
    ///    once everything above has had its chance to turn a "surplus" or
    ///    "redundant" file into something actually needed instead.
    /// 5. Zip comments, Samples, BIOS, and Complementary Chips are pure
    ///    housekeeping — run last, and skipped outright (not just a no-op
    ///    log line) when their own folder isn't even configured, so this
    ///    never pops the "no folder configured" alert those raise when
    ///    invoked directly.
    ///
    /// Every sub-step already re-scans the whole system on its own before
    /// returning (see each one's own `scan(system:)` call and this file's
    /// own "scan first, log after" convention) — the NEXT step in this list
    /// always sees the freshly-updated result, so no separate rescan is
    /// needed here between them. That same per-step rescan also means the
    /// Log panel (which every scan clears — see `scan(system:folders:)`'s
    /// own `logLines.removeAll()`) only ever shows the MOST RECENT step's
    /// own lines while this runs; the final "Fix All: done" line below is
    /// the one line guaranteed to still be visible once it's over.
    /// A total count across every step `fixAll(system:enabledActionIDs:)`
    /// will actually run for this exact system/configuration, for the
    /// up-front confirmation dialog — same dry-run-before-write caution as
    /// every other Fase 2 action, just summed across all of them instead of
    /// one. Deliberately mirrors `fixAll`'s own step list and gating
    /// exactly (same `enabledActionIDs`/`isMAMEStyle`/folder-configured
    /// checks) so this number is never an over- or under-count of what
    /// confirming will actually do. Read-only: none of these
    /// `plan*PreviewCount` calls write anything.
    ///
    /// `enabledActionIDs` — `LibraryDetailView.fixActionsEnabledForTesting`,
    /// passed in rather than duplicated here: that set is this app's own
    /// staged-rollout knob (several Fase 2 actions stay deliberately hidden
    /// from the toolbar until jensyleo has live-tested them individually —
    /// see its own doc comment). "Fix All" must never run an action he
    /// hasn't already tested and enabled on its own, so it's gated by the
    /// exact same ids as the toolbar itself, not a separate list that could
    /// drift out of sync.
    func planFixAllPreviewCount(system: RomSystem, enabledActionIDs: Set<String>) async -> Int {
        var total = 0
        if enabledActionIDs.contains("fixMisnamed") { total += planFixPreviewCount() }
        if enabledActionIDs.contains("renameRomsInArchive") { total += planRenameRomsInArchivePreviewCount() }
        if system.isMAMEStyle {
            switch MAMEMergeModeSettings.current {
            case .split where enabledActionIDs.contains("convertToSplit"): total += planConvertToSplitPreviewCount()
            case .merged where enabledActionIDs.contains("convertToMerged"): total += planConvertToMergedPreviewCount()
            case .nonMerged where enabledActionIDs.contains("makeSelfContained"): total += planMakeSelfContainedPreviewCount()
            default: break
            }
        }
        if enabledActionIDs.contains("repairFromSiblingSets") { total += planRepairFromSiblingSetsPreviewCount() }
        if enabledActionIDs.contains("repairFromMaintenanceFolder"), MaintenanceFolderSettings.folderURL != nil {
            total += await planRepairFromMaintenanceFolderPreviewCount(system: system)
        }
        if enabledActionIDs.contains("handleCorruptedFiles") { total += planCorruptedFilesPolicyPreviewCount() }
        if enabledActionIDs.contains("createDummyRoms") { total += planCreateDummyRomsPreviewCount() }
        if enabledActionIDs.contains("removeRedundantRoms") { total += planRemoveRedundantRomsPreviewCount(scopeFolders: []) }
        if enabledActionIDs.contains("removeRedundantFiles") { total += planRemoveRedundantFilesPreviewCount(scopeFolders: []) }
        if enabledActionIDs.contains("removeUselessFiles") { total += planRemoveUselessFilesPreviewCount(scopeFolders: []) }
        if enabledActionIDs.contains("removeZipComments") { total += planRemoveZipCommentsPreviewCount() }
        if system.isMAMEStyle {
            if enabledActionIDs.contains("collectSamples"), SamplesFolderSettings.folderURL != nil {
                total += await planCollectSamplesPreviewCount(system: system)
            }
            if enabledActionIDs.contains("organizeBIOSFiles"), BIOSFolderSettings.folderURL != nil {
                total += planOrganizeBIOSFilesPreviewCount()
            }
            if enabledActionIDs.contains("organizeComplementaryChips"), ComplementaryChipsFolderSettings.folderURL != nil {
                total += planOrganizeComplementaryChipsPreviewCount()
            }
        }
        return total
    }

    func fixAll(system: RomSystem, enabledActionIDs: Set<String>) async {
        guard Self.modificationsEnabled else {
            logError("Fix All is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard requireMatchReport() != nil else { return }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return
        }

        if enabledActionIDs.contains("fixMisnamed") { await fix(system: system) }
        if enabledActionIDs.contains("renameRomsInArchive") { await renameRomsInArchive(system: system) }

        if system.isMAMEStyle {
            switch MAMEMergeModeSettings.current {
            case .split where enabledActionIDs.contains("convertToSplit"): await convertToSplit(system: system)
            case .merged where enabledActionIDs.contains("convertToMerged"): await convertToMerged(system: system)
            case .nonMerged where enabledActionIDs.contains("makeSelfContained"): await makeSelfContained(system: system)
            default: break
            }
        }

        if enabledActionIDs.contains("repairFromSiblingSets") { await repairFromSiblingSets(system: system) }

        if enabledActionIDs.contains("repairFromMaintenanceFolder"), MaintenanceFolderSettings.folderURL != nil {
            let maintenanceCount = await planRepairFromMaintenanceFolderPreviewCount(system: system, scopeFolders: [])
            if maintenanceCount > 0 {
                await repairFromMaintenanceFolder(system: system, scopeFolders: [])
            }
        }

        if enabledActionIDs.contains("handleCorruptedFiles") { await applyCorruptedFilesPolicy(system: system) }
        if enabledActionIDs.contains("createDummyRoms") { await createDummyRoms(system: system) }
        if enabledActionIDs.contains("removeRedundantRoms") { await removeRedundantRoms(system: system, scopeFolders: []) }
        if enabledActionIDs.contains("removeRedundantFiles") { await removeRedundantFiles(system: system, scopeFolders: []) }
        if enabledActionIDs.contains("removeUselessFiles") { await removeUselessFiles(system: system, scopeFolders: []) }
        if enabledActionIDs.contains("removeZipComments") { await removeZipComments(system: system, scopeFolders: []) }

        if system.isMAMEStyle {
            if enabledActionIDs.contains("collectSamples"), SamplesFolderSettings.folderURL != nil {
                await collectSamples(system: system)
            }
            if enabledActionIDs.contains("organizeBIOSFiles"), BIOSFolderSettings.folderURL != nil {
                await organizeBIOSFiles(system: system)
            }
            if enabledActionIDs.contains("organizeComplementaryChips"), ComplementaryChipsFolderSettings.folderURL != nil {
                await organizeComplementaryChips(system: system)
            }
        }

        logSuccess("Fix All: every automatic Fix action has run.")
    }

    func removeUselessFiles(system: RomSystem, scopeFolders: [URL]) async {
        guard Self.modificationsEnabled else {
            logError("Removing files is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        isBusy = true
        defer { isBusy = false }

        // Real gap found live by jensyleo (2026-09-23), same class as
        // `removeRedundantFiles`'s/`repairFromMaintenanceFolder`'s own doc
        // comments: this action never set `fixActionProgress` at all, so
        // the overlay fell through to its generic, indeterminate "Scanning
        // folders…" fallback with no moving numbers for however long the
        // actual deletes took.
        let fixProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in self?.fixActionProgress = ("Removing useless files…", completed, total) }
        }
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let operations = Self.restrictToScope(RebuildPlanner.planRemoveUselessFiles(matchReport: matchReport), scopeFolders: scopeFolders)
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            let total = operations.count
            for (index, operation) in operations.enumerated() {
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("Could not \(Self.describeOperation(operation)): \(error.localizedDescription)")
                }
                fixProgressHandler(index + 1, total)
            }
            return (succeeded, failed, failureLines)
        }.value
        fixActionProgress = nil

        // jensyleo's own report (2026-09-11): logging this action's own
        // result BEFORE the verification rescan meant `scan()`'s own
        // `logLines.removeAll()` erased it right away — the Log ended up
        // showing only the rescan's narration, never what this action
        // itself actually did. Same fix as `fix()`/`renameRomsInArchive()`
        // above: scan first, log the result after.
        //
        // jensyleo's own report (2026-09-16), testing "Repair from
        // Maintenance Folder…" scoped to one folder (SEGA) and seeing the
        // verification rescan's own progress narrate an entirely
        // UNRELATED one (CPS3): this rescan used to always cover the
        // WHOLE system regardless of how narrow `scopeFolders` was —
        // `fix()`/`renameRomsInArchive()` already scope their own
        // verification rescan this same way; this action (and its
        // siblings below) just never got that same treatment. An empty
        // `scopeFolders` (the toolbar-wide, whole-system version of this
        // action) still rescans everything, same as before.
        await scan(system: system, folders: scopeFolders.isEmpty ? nil : scopeFolders)
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
        postFixResultPopup(action: "Remove Useless Files", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// How many LOOSE files "Remove Redundant Files…" would actually delete
    /// — same preview-before-confirm pattern as
    /// `planRemoveUselessFilesPreviewCount`. Returns `0` before any scan has
    /// run.
    func planRemoveRedundantFilesPreviewCount(scopeFolders: [URL]) -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        // Silent on scope mismatch — see `planFixPreviewCount`'s own doc
        // comment: also read from the context-menu construction closure.
        guard scopeCoveredByLastScan(scopeFolders) else { return 0 }
        let fileOperations = RebuildPlanner.planRemoveRedundantFiles(matchReport: matchReport)
        let diskOperations = RebuildPlanner.planRemoveRedundantDisks(auditEntries: auditReport?.entries ?? [])
        let wholeArchiveOperations = RebuildPlanner.planRemoveRedundantWholeArchives(
            matchReport: matchReport, entryCounts: Self.redundantArchiveEntryCounts(matchReport: matchReport)
        )
        return Self.restrictToScope(fileOperations + diskOperations + wholeArchiveOperations, scopeFolders: scopeFolders).count
    }

    /// Lists (never decompresses — both `SevenZipArchiveScanner.scan` and
    /// `ZipArchiveScanner.scan` are cheap listings, same cost the initial
    /// scan itself already pays) every distinct archive container (`.7z`
    /// OR `.zip`, generalized 2026-09-17 — see
    /// `RebuildPlanner.planRemoveRedundantWholeArchives`'s own doc comment
    /// for why `.zip` needed this too) a redundant surplus rom lives in,
    /// so that function can tell "the redundant entry is this container's
    /// ONLY content" (safe to delete the whole archive) from "other,
    /// still-needed content shares this same archive" (must be left
    /// alone). Real disk I/O, deliberately kept in the App layer rather
    /// than `RebuildPlanner` itself (see that type's own "never touches
    /// disk" doc comment).
    private nonisolated static func redundantArchiveEntryCounts(matchReport: MatchReport) -> [URL: Int] {
        let containers = Set(
            matchReport.surplusFiles
                .filter { $0.requiredByGameDescription != nil }
                .map(\.file.file.url)
                .filter { $0.pathExtension.lowercased() == "7z" || $0.pathExtension.lowercased() == "zip" }
        )
        var counts: [URL: Int] = [:]
        for container in containers {
            if container.pathExtension.lowercased() == "7z" {
                counts[container] = (try? SevenZipArchiveScanner.scan(archive: container))?.count
            } else {
                counts[container] = (try? ZipArchiveScanner.scan(archive: container))?.count
            }
        }
        return counts
    }

    /// Permanently deletes every LOOSE file that's a redundant duplicate of
    /// content the DAT recognizes elsewhere — jensyleo's own request
    /// (2026-09-13), the exact complement of "Remove Useless Files" (which
    /// deliberately excludes this exact case — see
    /// `RebuildPlanner.planRemoveUselessFiles`'s own doc comment). Split
    /// from the archive-entry version (`removeRedundantRoms`, below)
    /// mirroring the existing Files/ROMs split every other Fix action here
    /// already uses.
    func removeRedundantFiles(system: RomSystem, scopeFolders: [URL]) async {
        guard Self.modificationsEnabled else {
            logError("Removing files is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        isBusy = true
        defer { isBusy = false }

        let diskEntries = auditReport?.entries ?? []
        let fixProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in self?.fixActionProgress = ("Removing redundant files…", completed, total) }
        }
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let fileOperations = RebuildPlanner.planRemoveRedundantFiles(matchReport: matchReport)
            let diskOperations = RebuildPlanner.planRemoveRedundantDisks(auditEntries: diskEntries)
            let wholeArchiveOperations = RebuildPlanner.planRemoveRedundantWholeArchives(
                matchReport: matchReport, entryCounts: Self.redundantArchiveEntryCounts(matchReport: matchReport)
            )
            let operations = Self.restrictToScope(fileOperations + diskOperations + wholeArchiveOperations, scopeFolders: scopeFolders)
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            let total = operations.count
            for (index, operation) in operations.enumerated() {
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("Could not \(Self.describeOperation(operation)): \(error.localizedDescription)")
                }
                fixProgressHandler(index + 1, total)
            }
            return (succeeded, failed, failureLines)
        }.value
        fixActionProgress = nil

        // jensyleo's own report (2026-09-16) — see `removeUselessFiles`'s
        // own doc comment on this exact scoping fix.
        await scan(system: system, folders: scopeFolders.isEmpty ? nil : scopeFolders)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Removed \(succeeded) redundant file(s); \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Removed \(succeeded) redundant file(s).")
        } else {
            logWarning("Nothing to remove — no redundant files in the current scan.")
        }
        postFixResultPopup(action: "Remove Redundant Files", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// How many operations "Organize BIOS Files…" would actually perform —
    /// same preview-before-confirm pattern as
    /// `planRemoveUselessFilesPreviewCount`/`planRemoveRedundantFilesPreviewCount`.
    /// Whole-system only (BIOSes can live under any of a system's ROM
    /// folders) — `0` before any scan, or when no BIOS folder is configured
    /// in Settings → Systems → MAME.
    func planOrganizeBIOSFilesPreviewCount() -> Int {
        guard let biosFolder = BIOSFolderSettings.folderURL else { return 0 }
        guard let matchReport = requireMatchReport() else { return 0 }
        guard scopeCoveredByLastScan([]) else { return 0 }
        return RebuildPlanner.planOrganizeBIOSFiles(matchReport: matchReport, biosFolder: biosFolder).count
    }

    /// One human-readable line per BIOS machine "Organize BIOS Files…"
    /// would touch — jensyleo's own request (2026-09-23), so its own
    /// confirmation dialog can list exactly which BIOSes were found,
    /// instead of just a bare count. See `RebuildPlanner
    /// .describeOrganizeBIOSFiles`'s own doc comment.
    func planOrganizeBIOSFilesPreviewLines() -> [String] {
        guard let biosFolder = BIOSFolderSettings.folderURL else { return [] }
        guard let matchReport = requireMatchReport() else { return [] }
        guard scopeCoveredByLastScan([]) else { return [] }
        return RebuildPlanner.describeOrganizeBIOSFiles(matchReport: matchReport, biosFolder: biosFolder)
    }

    /// jensyleo's own request (2026-09-23): "Debe buscar en todos los ROM
    /// folders y moverlos a la carpeta BIOS. Si hay repetidos, los
    /// elimina." — a toolbar-only action (never in a per-row context menu,
    /// per point 3 of that same request), always whole-system since a BIOS
    /// can be referenced by games under any of a system's configured ROM
    /// folders. Moves each BIOS's own loose file into the configured BIOS
    /// folder (see `BIOSFolderSettings`), and removes any further loose or
    /// zip-entry copy of that same BIOS this scan found still sitting
    /// somewhere a game only needed because another copy is now confirmed
    /// safe elsewhere (`RebuildPlanner.planOrganizeBIOSFiles`'s own
    /// `requiredByGameOwnerSatisfiedElsewhere` check — the exact same
    /// safety guard `removeRedundantFiles` above already relies on, never
    /// a plain "delete every duplicate" pass).
    func organizeBIOSFiles(system: RomSystem) async {
        guard Self.modificationsEnabled else {
            logConfigurationRequired("Organizing BIOS files is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let biosFolder = BIOSFolderSettings.folderURL else {
            logConfigurationRequired("No BIOS folder configured — set one in Settings → Systems → MAME first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return
        }
        isBusy = true
        defer { isBusy = false }

        // Captured from the PRE-move `matchReport`, before `scan(system:
        // folders: nil)` below replaces it — jensyleo's own request
        // (2026-09-24): "debe... indicar que BIOS cargó después de
        // terminar", right after asking for the same list in the
        // confirmation dialog (`planOrganizeBIOSFilesPreviewLines`). Same
        // underlying describe function, just logged as the RESULT instead
        // of a preview.
        let summaryLines = RebuildPlanner.describeOrganizeBIOSFiles(matchReport: matchReport, biosFolder: biosFolder)

        let fixProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in self?.fixActionProgress = ("Organizing BIOS files…", completed, total) }
        }
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let operations = RebuildPlanner.planOrganizeBIOSFiles(matchReport: matchReport, biosFolder: biosFolder)
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            let total = operations.count
            for (index, operation) in operations.enumerated() {
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("Could not \(Self.describeOperation(operation)): \(error.localizedDescription)")
                }
                fixProgressHandler(index + 1, total)
            }
            return (succeeded, failed, failureLines)
        }.value
        fixActionProgress = nil

        await scan(system: system, folders: nil)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Organized \(succeeded) BIOS file(s); \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Organized \(succeeded) BIOS file(s) into \"\(biosFolder.lastPathComponent)\":")
            for line in summaryLines {
                logSuccess("  \(line)")
            }
        } else {
            logWarning("Nothing to organize — no BIOS files found outside \"\(biosFolder.lastPathComponent)\" in the current scan.")
        }
        postFixResultPopup(action: "Organize BIOS Files", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// How many operations "Organize Complementary Chips…" would actually
    /// perform — same preview-before-confirm pattern as
    /// `planOrganizeBIOSFilesPreviewCount`.
    func planOrganizeComplementaryChipsPreviewCount() -> Int {
        guard let chipsFolder = ComplementaryChipsFolderSettings.folderURL else { return 0 }
        guard let matchReport = requireMatchReport() else { return 0 }
        guard scopeCoveredByLastScan([]) else { return 0 }
        return RebuildPlanner.planOrganizeComplementaryChips(matchReport: matchReport, chipsFolder: chipsFolder).count
    }

    /// One human-readable line per chip "Organize Complementary Chips…"
    /// would touch — same reasoning as `planOrganizeBIOSFilesPreviewLines`.
    func planOrganizeComplementaryChipsPreviewLines() -> [String] {
        guard let chipsFolder = ComplementaryChipsFolderSettings.folderURL else { return [] }
        guard let matchReport = requireMatchReport() else { return [] }
        guard scopeCoveredByLastScan([]) else { return [] }
        return RebuildPlanner.describeOrganizeComplementaryChips(matchReport: matchReport, chipsFolder: chipsFolder)
    }

    /// jensyleo's own request (2026-09-24): "lo mismo que BIOS pero para
    /// los demás chips" — see `RebuildPlanner
    /// .planOrganizeComplementaryChips`'s own doc comment for the exact
    /// distinction (`DATGame.isDevice`, confirmed against MAME's own
    /// official "Device set" documentation) and `organizeBIOSFiles`'s own
    /// doc comment above for why every other line here mirrors that
    /// function exactly.
    func organizeComplementaryChips(system: RomSystem) async {
        guard Self.modificationsEnabled else {
            logConfigurationRequired("Organizing complementary chips is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let chipsFolder = ComplementaryChipsFolderSettings.folderURL else {
            logConfigurationRequired("No Complementary Chips folder configured — set one in Settings → Systems → MAME first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return
        }
        isBusy = true
        defer { isBusy = false }

        let summaryLines = RebuildPlanner.describeOrganizeComplementaryChips(matchReport: matchReport, chipsFolder: chipsFolder)

        let fixProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in self?.fixActionProgress = ("Organizing complementary chips…", completed, total) }
        }
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let operations = RebuildPlanner.planOrganizeComplementaryChips(matchReport: matchReport, chipsFolder: chipsFolder)
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            let total = operations.count
            for (index, operation) in operations.enumerated() {
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("Could not \(Self.describeOperation(operation)): \(error.localizedDescription)")
                }
                fixProgressHandler(index + 1, total)
            }
            return (succeeded, failed, failureLines)
        }.value
        fixActionProgress = nil

        await scan(system: system, folders: nil)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Organized \(succeeded) complementary chip file(s); \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Organized \(succeeded) complementary chip file(s) into \"\(chipsFolder.lastPathComponent)\":")
            for line in summaryLines {
                logSuccess("  \(line)")
            }
        } else {
            logWarning("Nothing to organize — no complementary chip files found outside \"\(chipsFolder.lastPathComponent)\" in the current scan.")
        }
        postFixResultPopup(action: "Organize Complementary Chips", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// How many archive ENTRIES "Remove Redundant ROMs…" would actually
    /// remove — same preview-before-confirm pattern as
    /// `planRemoveRedundantFilesPreviewCount` just above.
    func planRemoveRedundantRomsPreviewCount(scopeFolders: [URL]) -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        // Silent on scope mismatch — see `planFixPreviewCount`'s own doc
        // comment: also read from the context-menu construction closure.
        guard scopeCoveredByLastScan(scopeFolders) else { return 0 }
        let fullyRedundant = RebuildPlanner.fullyRedundantArchiveContainers(
            matchReport: matchReport, entryCounts: Self.redundantArchiveEntryCounts(matchReport: matchReport)
        )
        return Self.restrictToScope(
            RebuildPlanner.planRemoveRedundantRoms(matchReport: matchReport, fullyRedundantContainers: fullyRedundant), scopeFolders: scopeFolders
        ).count
    }

    /// Removes every archive ENTRY that's a redundant duplicate of content
    /// the DAT recognizes elsewhere — the archive-entry counterpart to
    /// `removeRedundantFiles` above; see its own doc comment for the shared
    /// "recognized, but not needed HERE" definition both act on. Never
    /// removes a whole archive — same reasoning "Remove Useless Files"
    /// already documents.
    func removeRedundantRoms(system: RomSystem, scopeFolders: [URL]) async {
        guard Self.modificationsEnabled else {
            logError("Removing ROMs is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        isBusy = true
        defer { isBusy = false }

        let fixProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in self?.fixActionProgress = ("Removing redundant ROMs…", completed, total) }
        }
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let fullyRedundant = RebuildPlanner.fullyRedundantArchiveContainers(
                matchReport: matchReport, entryCounts: Self.redundantArchiveEntryCounts(matchReport: matchReport)
            )
            let operations = Self.restrictToScope(
                RebuildPlanner.planRemoveRedundantRoms(matchReport: matchReport, fullyRedundantContainers: fullyRedundant), scopeFolders: scopeFolders
            )
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            let total = operations.count
            for (index, operation) in operations.enumerated() {
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("Could not \(Self.describeOperation(operation)): \(error.localizedDescription)")
                }
                fixProgressHandler(index + 1, total)
            }
            return (succeeded, failed, failureLines)
        }.value
        fixActionProgress = nil

        // jensyleo's own report (2026-09-16) — see `removeUselessFiles`'s
        // own doc comment on this exact scoping fix.
        await scan(system: system, folders: scopeFolders.isEmpty ? nil : scopeFolders)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Removed \(succeeded) redundant rom(s); \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Removed \(succeeded) redundant rom(s).")
        } else {
            logWarning("Nothing to remove — no redundant roms in the current scan.")
        }
        postFixResultPopup(action: "Remove Redundant ROMs", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    // MARK: - Rom Entry Actions (jensyleo's own request, 2026-09-13)

    /// One row's own target for the actions just below — a plain file
    /// (`isArchived == false`, `url` is the file itself) or a `.zip` entry
    /// (`isArchived == true`, `url` is the CONTAINING archive, `entryName`
    /// the entry's own name inside it).
    struct RomEntryTarget: Sendable {
        let url: URL
        let entryName: String
        let isArchived: Bool
    }

    /// jensyleo's own report (2026-09-13): the Roms panel's own context
    /// menu only ever offered "Fix This Misnamed ROM…", and only when a
    /// rename was actually available — regardless of a rom's own DAT
    /// status (Correct/Bad/Unknown/Missing), he wants the SAME kind of
    /// File Actions the Games table already has (Trash/Delete/Extract),
    /// just adapted for the fact a rom entry often lives INSIDE a `.zip`
    /// rather than as its own loose file: "obviamente ahí hay que tener en
    /// cuenta que el archivo está comprimido, por ende también debe tener
    /// acciones de descompresión como Extract file". These three functions
    /// are that: entry-aware equivalents of the existing loose-file-only
    /// `moveFilesToTrash`/`deleteFilesPermanently`/`copyFiles`, dispatching
    /// per target between a real Trash/delete of a loose file and a
    /// `.removeEntryFromZip`/`.extractZipEntry` for an archived one — never
    /// touching the archive as a whole. Deliberately independent of
    /// `MatchReport`/`RebuildPlanner`, exactly like the existing generic
    /// File Actions below: a rom's own DAT status is irrelevant to "get
    /// this file out" or "get rid of this file".

    /// Copies each target's own content out to `destination` as a plain
    /// loose file, keeping its own name — never touches the source (the
    /// containing archive, for an archived entry, is only ever READ from),
    /// so no rescan is needed.
    func extractRomEntries(system: RomSystem, _ entries: [RomEntryTarget], to destination: URL) async {
        guard Self.modificationsEnabled else {
            logError("File Actions are disabled — enable file modifications in Settings → General first.")
            return
        }
        guard !entries.isEmpty else { return }
        let scopeFolders = Self.romFolders(containing: entries.map(\.url), in: system)
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        isBusy = true
        defer { isBusy = false }
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for entry in entries {
                let target = destination.appendingPathComponent(entry.entryName)
                let operation: RebuildOperation = entry.isArchived
                    ? .extractZipEntry(archive: entry.url, entryName: entry.entryName, to: target)
                    : .copy(from: entry.url, to: target)
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("\(entry.entryName): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value
        for line in failureLines { logWarning(line) }
        if failed > 0 {
            logWarning("Extracted \(succeeded) rom(s) to \(destination.path); \(failed) failed (see the lines just above for which).")
        } else {
            logSuccess("Extracted \(succeeded) rom(s) to \(destination.path).")
        }
        postFixResultPopup(action: "Extract to Folder", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// Moves each target to the Trash (a loose file) or removes just its
    /// own entry from its containing archive (leaving every other rom in
    /// that same archive untouched) — recoverable only for the loose-file
    /// case, same as `moveFilesToTrash`. Rescans afterward.
    func moveRomEntriesToTrash(system: RomSystem, _ entries: [RomEntryTarget]) async {
        guard Self.modificationsEnabled else {
            logError("File Actions are disabled — enable file modifications in Settings → General first.")
            return
        }
        guard !entries.isEmpty else { return }
        let scopeFolders = Self.romFolders(containing: entries.map(\.url), in: system)
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        isBusy = true
        defer { isBusy = false }
        let looseURLs = entries.filter { !$0.isArchived }.map(\.url)
        let archivedEntries = entries.filter(\.isArchived)
        var succeeded = 0
        var failed = 0
        var failureLines: [String] = []
        if !looseURLs.isEmpty {
            do {
                succeeded += try await NSWorkspace.shared.recycle(looseURLs).count
            } catch {
                failed += looseURLs.count
                failureLines.append(error.localizedDescription)
            }
        }
        let (archivedSucceeded, archivedFailed, archivedFailureLines) = await Task.detached(priority: .userInitiated) {
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for entry in archivedEntries {
                do {
                    try RebuildExecutor.execute([.removeEntryFromZip(archive: entry.url, entryName: entry.entryName)])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("\(entry.entryName): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value
        succeeded += archivedSucceeded
        failed += archivedFailed
        failureLines += archivedFailureLines

        await scan(system: system, folders: scopeFolders.isEmpty ? nil : scopeFolders)
        for line in failureLines { logWarning(line) }
        if failed > 0 {
            logWarning("Removed \(succeeded) rom(s); \(failed) failed (see the lines just above for which).")
        } else {
            logSuccess("Removed \(succeeded) rom(s) — loose file(s) went to the Trash, archive entries were removed from their own zip.")
        }
        postFixResultPopup(action: "Move to Trash", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// Permanently deletes each target — a real file delete for a loose rom,
    /// or a `.removeEntryFromZip` for an archived one (same primitive
    /// "Remove Useless Files…"/"Remove Redundant ROMs…" already use).
    /// Irreversible. Rescans afterward.
    func deleteRomEntriesPermanently(system: RomSystem, _ entries: [RomEntryTarget]) async {
        guard Self.modificationsEnabled else {
            logError("File Actions are disabled — enable file modifications in Settings → General first.")
            return
        }
        guard !entries.isEmpty else { return }
        let scopeFolders = Self.romFolders(containing: entries.map(\.url), in: system)
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        isBusy = true
        defer { isBusy = false }
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for entry in entries {
                let operation: RebuildOperation = entry.isArchived
                    ? .removeEntryFromZip(archive: entry.url, entryName: entry.entryName)
                    : .delete(entry.url)
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("\(entry.entryName): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value
        await scan(system: system, folders: scopeFolders.isEmpty ? nil : scopeFolders)
        for line in failureLines { logWarning(line) }
        if failed > 0 {
            logWarning("Permanently deleted \(succeeded) rom(s); \(failed) failed (see the lines just above for which).")
        } else {
            logSuccess("Permanently deleted \(succeeded) rom(s).")
        }
        postFixResultPopup(action: "Delete Permanently", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    // MARK: - File Actions (generic, OS-level — jensyleo's own request, 2026-09-11)

    /// Plain Finder-style operations (Move to Trash, Delete Permanently,
    /// Copy/Move to Folder…) on whatever Files are currently selected —
    /// unlike every other action in this file, these don't care whether a
    /// file matches its expected DAT rom/name at all, so they never consult
    /// `MatchReport`/`RebuildPlanner`. Still gated by `modificationsEnabled`
    /// (they're real disk writes) and still refuse anything inside the
    /// Maintenance folder (`LibraryDetailView.rejectIfUnderMaintenanceFolder`
    /// checks that BEFORE any of these are ever called, so a rejection never
    /// even reaches here) — that area is documented, deliberately read-only
    /// donor storage.

    /// Moves `urls` to the Trash (`NSWorkspace.recycle`, real Finder Trash —
    /// recoverable, unlike `deleteFilesPermanently`). Rescans afterward
    /// since this removes files from the scanned collection.
    func moveFilesToTrash(system: RomSystem, urls: [URL]) async {
        guard Self.modificationsEnabled else {
            logError("File Actions are disabled — enable file modifications in Settings → General first.")
            return
        }
        guard !urls.isEmpty else { return }
        let scopeFolders = Self.romFolders(containing: urls, in: system)
        // Real gap found live by jensyleo (2026-09-23): "File Actions" let
        // you delete/move/duplicate/compress a File without ever having
        // scanned it this session at all — every OTHER write action in
        // this file refuses on exactly this same check
        // (`scopeCoveredByLastScan`). These were originally exempted on
        // purpose (see this section's own doc comment: they don't consult
        // `MatchReport` at all, so nothing here technically NEEDS a scan
        // to know what to do) — jensyleo's own explicit follow-up:
        // "Todos los File Actions debe pedir escaneo previo" overrides
        // that with the same standing "never act on possibly-stale data"
        // rule every other write action already follows.
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let trashedURLs = try await NSWorkspace.shared.recycle(urls)
            await scan(system: system, folders: scopeFolders.isEmpty ? nil : scopeFolders)
            logSuccess("Moved \(trashedURLs.count) file(s) to the Trash.")
            postFixResultPopup(action: "Move to Trash", succeeded: trashedURLs.count, failed: 0)
        } catch {
            await scan(system: system, folders: scopeFolders.isEmpty ? nil : scopeFolders)
            logError("Move to Trash failed: \(error.localizedDescription)")
            postFixResultPopup(action: "Move to Trash", succeeded: 0, failed: urls.count, failureLines: [error.localizedDescription])
        }
    }

    /// Permanently deletes `urls` (`RebuildOperation.delete`, same primitive
    /// "Remove Useless Files…" uses) — irreversible, unlike
    /// `moveFilesToTrash`. Each file is attempted independently so one
    /// failure doesn't abort the rest, same reasoning as
    /// `removeUselessFiles` above. Rescans afterward.
    func deleteFilesPermanently(system: RomSystem, urls: [URL]) async {
        guard Self.modificationsEnabled else {
            logError("File Actions are disabled — enable file modifications in Settings → General first.")
            return
        }
        guard !urls.isEmpty else { return }
        let scopeFolders = Self.romFolders(containing: urls, in: system)
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        isBusy = true
        defer { isBusy = false }
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for url in urls {
                do {
                    try RebuildExecutor.execute([.delete(url)])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value
        await scan(system: system, folders: scopeFolders.isEmpty ? nil : scopeFolders)
        for line in failureLines { logWarning(line) }
        if failed > 0 {
            logWarning("Permanently deleted \(succeeded) file(s); \(failed) failed (see the lines just above for which).")
        } else {
            logSuccess("Permanently deleted \(succeeded) file(s).")
        }
        postFixResultPopup(action: "Delete Permanently", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// Every one of `urls`' own filename that already exists directly under
    /// `destination` — jensyleo's own report (2026-09-30): "Copy File(s)
    /// to…" silently refused (`RebuildExecutor` never overwrites — see its
    /// own doc comment, a deliberate invariant kept everywhere else in this
    /// codebase too) with no way for the user to say "yes, replace it
    /// anyway", the exact confusion behind a real collision copying a
    /// genuinely correct "Bump 'n' Jump (USA).zip" over a bad dump already
    /// sitting under that same name in the destination. Queried by the UI
    /// BEFORE committing the action, so it can ask "N file(s) already
    /// exist — replace them?" instead of silently failing partway through
    /// a batch. jensyleo's own explicit call: never Finder's "Keep Both"
    /// auto-suffix (" 2") — an appended-number filename would never again
    /// match anything in the DAT, permanently creating a NEW unrecognized
    /// file instead of fixing the one that was already there.
    nonisolated static func existingDestinationFilenames(for urls: [URL], in destination: URL, fileManager: FileManager = .default) -> [String] {
        urls.map(\.lastPathComponent).filter { fileManager.fileExists(atPath: destination.appendingPathComponent($0).path) }
    }

    /// Copies `urls` into `destination`, keeping each file's own name —
    /// never touches the source, so no rescan needed. Each file attempted
    /// independently, same reasoning as every other batch action here.
    /// `replacingFilenames` — exactly the subset of `urls`' own filenames
    /// the user explicitly confirmed replacing (via
    /// `existingDestinationFilenames` above, surfaced through a real
    /// confirmation dialog) — is removed from `destination` FIRST, one file
    /// at a time, immediately before that specific copy, so
    /// `RebuildExecutor`'s own "never overwrites" guard still sees a clean,
    /// empty destination and its invariant is never silently bypassed; the
    /// actual, irreversible act of removing the old file only ever happens
    /// here, for a filename the user was shown and explicitly agreed to.
    func copyFiles(system: RomSystem, _ urls: [URL], to destination: URL, replacingFilenames: Set<String> = []) async {
        guard Self.modificationsEnabled else {
            logError("File Actions are disabled — enable file modifications in Settings → General first.")
            return
        }
        guard !urls.isEmpty else { return }
        let scopeFolders = Self.romFolders(containing: urls, in: system)
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        isBusy = true
        defer { isBusy = false }
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for url in urls {
                let target = destination.appendingPathComponent(url.lastPathComponent)
                do {
                    if replacingFilenames.contains(url.lastPathComponent) {
                        try? FileManager.default.removeItem(at: target)
                    }
                    try RebuildExecutor.execute([.copy(from: url, to: target)])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value
        for line in failureLines { logWarning(line) }
        if failed > 0 {
            logWarning("Copied \(succeeded) file(s) to \(destination.path); \(failed) failed (see the lines just above for which).")
        } else {
            logSuccess("Copied \(succeeded) file(s) to \(destination.path).")
        }
        postFixResultPopup(action: "Copy to Folder", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// Moves `urls` into `destination`, keeping each file's own name —
    /// removes each from its source, so rescans afterward, same as
    /// `moveFilesToTrash`/`deleteFilesPermanently`. `replacingFilenames` —
    /// see `copyFiles`'s own doc comment on `existingDestinationFilenames`/
    /// `replacingFilenames`, identical reasoning here.
    func moveFiles(system: RomSystem, urls: [URL], to destination: URL, replacingFilenames: Set<String> = []) async {
        guard Self.modificationsEnabled else {
            logError("File Actions are disabled — enable file modifications in Settings → General first.")
            return
        }
        guard !urls.isEmpty else { return }
        guard scopeCoveredByLastScan(Self.romFolders(containing: urls, in: system)) else {
            logRescanRequiredForFix(scopeFolders: Self.romFolders(containing: urls, in: system))
            return
        }
        isBusy = true
        defer { isBusy = false }
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for url in urls {
                let target = destination.appendingPathComponent(url.lastPathComponent)
                do {
                    if replacingFilenames.contains(url.lastPathComponent) {
                        try? FileManager.default.removeItem(at: target)
                    }
                    try RebuildExecutor.execute([.move(from: url, to: target)])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value
        await scan(system: system)
        for line in failureLines { logWarning(line) }
        if failed > 0 {
            logWarning("Moved \(succeeded) file(s) to \(destination.path); \(failed) failed (see the lines just above for which).")
        } else {
            logSuccess("Moved \(succeeded) file(s) to \(destination.path).")
        }
        postFixResultPopup(action: "Move to Folder", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// Finder-style "name copy.ext", "name copy 2.ext", … — the first
    /// available name in the SAME folder as `url` that doesn't already
    /// exist, same convention Finder's own "Duplicate" uses.
    private nonisolated static func uniqueDuplicateURL(for url: URL, fileManager: FileManager = .default) -> URL {
        let directory = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        func candidate(_ suffix: String) -> URL {
            directory.appendingPathComponent(ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)")
        }
        var result = candidate("copy")
        var n = 2
        while fileManager.fileExists(atPath: result.path) {
            result = candidate("copy \(n)")
            n += 1
        }
        return result
    }

    /// Duplicates `urls` in place — Finder's own "Duplicate", via the same
    /// `RebuildOperation.copy` primitive "Copy to Folder…" uses, just
    /// targeting a generated name in the SAME folder instead of a
    /// user-chosen one. Never touches the source, so no rescan needed for
    /// safety, but a duplicate IS a new File the collection didn't have
    /// before, so this still rescans to reflect it.
    func duplicateFiles(system: RomSystem, urls: [URL]) async {
        guard Self.modificationsEnabled else {
            logError("File Actions are disabled — enable file modifications in Settings → General first.")
            return
        }
        guard !urls.isEmpty else { return }
        guard scopeCoveredByLastScan(Self.romFolders(containing: urls, in: system)) else {
            logRescanRequiredForFix(scopeFolders: Self.romFolders(containing: urls, in: system))
            return
        }
        isBusy = true
        defer { isBusy = false }
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for url in urls {
                let target = Self.uniqueDuplicateURL(for: url)
                do {
                    try RebuildExecutor.execute([.copy(from: url, to: target)])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return (succeeded, failed, failureLines)
        }.value
        await scan(system: system)
        for line in failureLines { logWarning(line) }
        if failed > 0 {
            logWarning("Duplicated \(succeeded) file(s); \(failed) failed (see the lines just above for which).")
        } else {
            logSuccess("Duplicated \(succeeded) file(s).")
        }
        postFixResultPopup(action: "Duplicate File", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// Finder-style "Compress" output name: the source's own name with a
    /// ".zip" extension for a single file ("game.zip" from "game" or, if
    /// `url` is already a `.zip`, still just its own base name), or
    /// "Archive.zip" for multiple — same convention Finder's own "Compress"
    /// uses, with the same "append a number if taken" collision handling as
    /// `uniqueDuplicateURL` above. Lands next to the FIRST selected file.
    private nonisolated static func uniqueCompressedArchiveURL(for urls: [URL], fileManager: FileManager = .default) -> URL {
        // `urls` is never actually empty here — `compressFiles` already
        // guards `!urls.isEmpty` before this is ever called — but this
        // fallback still uses `FileManager.default.temporaryDirectory` with
        // a random `UUID` component rather than a fixed name (a code-audit
        // finding, 2026-09-11: a hardcoded "Archive.zip" under
        // `NSTemporaryDirectory()` would be a predictable path a symlink
        // planted there ahead of time could hijack) — defensive, not a
        // live vulnerability, since this branch is unreachable today.
        guard let first = urls.first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        }
        let directory = first.deletingLastPathComponent()
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        var candidate = directory.appendingPathComponent("\(base).zip")
        var n = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(n).zip")
            n += 1
        }
        return candidate
    }

    /// Packs `urls` into one new `.zip` alongside them — Finder's own
    /// "Compress", via the same `RebuildOperation.createArchive` primitive
    /// the Fase 2 rebuild engine already uses for building game sets, just
    /// packing whatever Files are selected verbatim (each as its own
    /// top-level entry, named after itself) rather than DAT-matched roms.
    /// Never touches the sources, but a compressed archive IS a new File
    /// the collection didn't have before, so this still rescans afterward.
    func compressFiles(system: RomSystem, urls: [URL]) async {
        guard Self.modificationsEnabled else {
            logError("File Actions are disabled — enable file modifications in Settings → General first.")
            return
        }
        guard !urls.isEmpty else { return }
        guard scopeCoveredByLastScan(Self.romFolders(containing: urls, in: system)) else {
            logRescanRequiredForFix(scopeFolders: Self.romFolders(containing: urls, in: system))
            return
        }
        isBusy = true
        defer { isBusy = false }
        let destination = Self.uniqueCompressedArchiveURL(for: urls)
        let entries = urls.map { ArchiveEntrySource(source: $0, entryName: $0.lastPathComponent) }
        do {
            try await Task.detached(priority: .userInitiated) {
                try RebuildExecutor.execute([.createArchive(entries: entries, to: destination)])
            }.value
            await scan(system: system)
            logSuccess("Created \"\(destination.lastPathComponent)\" containing \(urls.count) file(s).")
            postFixResultPopup(action: "Compress", succeeded: urls.count, failed: 0)
        } catch {
            await scan(system: system)
            logError("Compress failed: \(error.localizedDescription)")
            postFixResultPopup(action: "Compress", succeeded: 0, failed: urls.count, failureLines: [error.localizedDescription])
        }
    }

    /// How many missing roms "Repair from Sibling Sets…" would actually fill
    /// in, without touching disk — same preview-before-confirm pattern as
    /// every other Fase 2 action. Returns `0` before any scan has run.
    func planRepairFromSiblingSetsPreviewCount() -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        // Real bug found live by jensyleo (2026-09-22): this is whole-
        // system-only (its own `repairFromSiblingSets` below has no scope
        // parameter at all), but showed a count from a STALE matchReport
        // even when the last actual scan was only scoped to one folder —
        // same false-promise class documented on `planFixPreviewCount`.
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return 0
        }
        return RebuildPlanner.planCrossSetRepair(matchReport: matchReport).count
    }

    /// How many dummy placeholder roms "Create Dummy ROMs" would actually
    /// create, without touching disk. Returns `0` before any scan has run.
    func planCreateDummyRomsPreviewCount() -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return 0
        }
        return RebuildPlanner.planCreateDummyRoms(matchReport: matchReport).count
    }

    /// How many distinct archives "Remove Zip Comments" would actually
    /// touch, without touching disk. Returns `0` before any scan has run.
    /// `scopeFolders` — real gap found live by jensyleo (2026-09-22):
    /// right-clicking a single File whose Info read "Ok — Has ZIP comment"
    /// (e.g. `dlair.zip`) had no way to remove just that one archive's
    /// comment — only the toolbar's own unscoped, whole-system version of
    /// this action existed, unlike every other Fix action here. Empty
    /// (the default) preserves the original whole-system behavior for the
    /// toolbar's own caller.
    func planRemoveZipCommentsPreviewCount(scopeFolders: [URL] = []) -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        // Silent on scope mismatch — see `planFixPreviewCount`'s own doc
        // comment: also read from the context-menu construction closure.
        guard scopeCoveredByLastScan(scopeFolders) else { return 0 }
        let candidates = matchedZipArchiveURLs(for: matchReport)
        return Self.planRemoveZipCommentsOperations(candidates: candidates, scopeFolders: scopeFolders).count
    }

    /// Shared by the preview count above and the real execution below —
    /// see `RebuildPlanner.matchedZipArchiveURLs`'s own doc comment for
    /// why the real disk read (which archive of the CANDIDATES actually
    /// has a comment) happens here rather than inside `RebuildPlanner`
    /// itself. Real bug found live by jensyleo (2026-09-22): before this
    /// split, every matched zip was offered/removed unconditionally,
    /// comment or not.
    /// `candidates` — the caller already resolves these via the cached
    /// `matchedZipArchiveURLs(for:)` above (main-actor-isolated, since it
    /// touches `matchedZipArchiveURLsCache`) BEFORE calling this
    /// `nonisolated` function, so the one genuinely expensive part (the
    /// whole-system walk) never repeats needlessly, whether this runs on
    /// the main actor (the preview count, cheap either way) or off it
    /// (the real execution's own `Task.detached`).
    private nonisolated static func planRemoveZipCommentsOperations(candidates: Set<URL>, scopeFolders: [URL]) -> [RebuildOperation] {
        let scoped = scopeFolders.isEmpty ? candidates : candidates.filter { urlIsInScope($0, scopeFolders: scopeFolders) }
        let archivesWithComments = Set(scoped.filter { url in
            guard let comment = ZipCommentReader.comment(ofZipAt: url) else { return false }
            return !comment.isEmpty
        })
        return RebuildPlanner.planRemoveZipComments(archivesWithComments: archivesWithComments)
    }

    /// How many sample-set zips "Fix Samples" would actually collect,
    /// without touching disk. `0` when samples support is disabled, no
    /// Samples folder is configured, or the loaded DAT declares no
    /// samples at all. Does the same read-only folder search
    /// `collectSamples(system:)` itself does — see that method's own doc
    /// comment for why this needs a real (bounded) disk read even at
    /// preview time, unlike every other Fase 2 preview count here.
    func planCollectSamplesPreviewCount(system: RomSystem) async -> Int {
        guard let samplesFolder = SamplesFolderSettings.folderURL else { return 0 }
        let neededSetNames = Set(preloadedGames.filter(\.hasSamples).map { $0.sampleOf ?? $0.name })
        guard !neededSetNames.isEmpty else { return 0 }
        let searchFolders = system.romFolderURLs
        return await Task.detached(priority: .userInitiated) {
            let foundSampleZips = Self.findSampleZips(named: neededSetNames, in: searchFolders)
            return RebuildPlanner.planCollectSamples(neededSetNames: neededSetNames, foundSampleZips: foundSampleZips, samplesFolder: samplesFolder).count
        }.value
    }

    /// Searches `folders` (never anywhere else — always this system's own
    /// already-configured ROM folders, never an arbitrary "scavenging"
    /// location, per jensyleo's own standing rule against those) for a
    /// loose `.zip` whose base filename exactly matches one of
    /// `neededNames` — a MAME sample set has no hash to verify by (see
    /// `RebuildPlanner.planCollectSamples`'s own doc comment), so filename
    /// is the only signal there is. `FolderScanner` never looks INSIDE a
    /// zip on its own (unlike `CollectionHasher`), so each matching zip
    /// surfaces as exactly one `ScannedFile` here — nothing is hashed,
    /// nothing is opened.
    private nonisolated static func findSampleZips(named neededNames: Set<String>, in folders: [URL]) -> [String: URL] {
        guard let scannedFiles = try? FolderScanner.scan(paths: folders) else { return [:] }
        var found: [String: URL] = [:]
        for file in scannedFiles {
            guard file.url.pathExtension.lowercased() == "zip" else { continue }
            let baseName = (file.url.lastPathComponent as NSString).deletingPathExtension
            guard neededNames.contains(baseName), found[baseName] == nil else { continue }
            found[baseName] = file.url
        }
        return found
    }

    /// Populates the MAME Samples folder (Settings → Systems → MAME) with
    /// whichever sample-set zips it can find in this system's own
    /// configured ROM folders — "Fix Samples". Never touches, renames, or
    /// deletes anything in either location; only ever adds a new zip that
    /// wasn't there before (`RebuildExecutor`'s own `.copy` refuses to
    /// overwrite an existing destination, same as every other Fase 2
    /// action). Unlike every other Fix action, this doesn't need — and
    /// doesn't check — a prior scan/`matchReport` at all: sample sets
    /// aren't part of the ROM audit pipeline in any way, just a plain
    /// name lookup against the loaded DAT's own games.
    func collectSamples(system: RomSystem) async {
        guard Self.modificationsEnabled else {
            logError("Collecting samples is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let samplesFolder = SamplesFolderSettings.folderURL else {
            logWarning("Samples support is off, or no Samples folder is configured — set both in Settings → Systems → MAME first.")
            return
        }
        let neededSetNames = Set(preloadedGames.filter(\.hasSamples).map { $0.sampleOf ?? $0.name })
        guard !neededSetNames.isEmpty else {
            logWarning("Nothing to collect — the loaded DAT declares no samples.")
            return
        }
        isBusy = true
        defer { isBusy = false }

        let searchFolders = system.romFolderURLs
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let foundSampleZips = Self.findSampleZips(named: neededSetNames, in: searchFolders)
            let operations = RebuildPlanner.planCollectSamples(neededSetNames: neededSetNames, foundSampleZips: foundSampleZips, samplesFolder: samplesFolder)
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

        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Collected \(succeeded) sample zip(s); \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Collected \(succeeded) sample zip(s) into the Samples folder.")
        } else {
            logWarning("Nothing to collect — no matching sample zip found in this system's own ROM folders.")
        }
        postFixResultPopup(action: "Fix Samples", succeeded: succeeded, failed: failed, failureLines: failureLines)
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
        postFixResultPopup(action: "Repair from Sibling Sets", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// Creates a zero-byte placeholder for every `.missing`/`nodump` rom —
    /// "Create dummy roms for nodump entries" (`RebuildPlanner
    /// .planCreateDummyRoms`'s own doc comment covers exactly which roms
    /// qualify). Same shape as `repairFromSiblingSets` above: no folder
    /// picker needed, since every placeholder lands wherever that game's
    /// OTHER roms already live.
    func createDummyRoms(system: RomSystem) async {
        guard Self.modificationsEnabled else {
            logError("Creating dummy roms is disabled — enable file modifications in Settings → General first.")
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
            let operations = RebuildPlanner.planCreateDummyRoms(matchReport: matchReport)
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

        await scan(system: system)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Created \(succeeded) dummy rom(s); \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Created \(succeeded) dummy rom(s) for nodump entries.")
        } else {
            logWarning("Nothing to create — no missing nodump rom found in this scan.")
        }
        postFixResultPopup(action: "Create Dummy ROMs", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// Strips the trailing comment from every matched `.zip` — "Remove zip
    /// comments" (`RebuildPlanner.planRemoveZipComments`). `scopeFolders`
    /// — see `planRemoveZipCommentsPreviewCount`'s own doc comment; empty
    /// (the toolbar's own default) keeps the original whole-system
    /// behavior and its own whole-system verification rescan.
    func removeZipComments(system: RomSystem, scopeFolders: [URL] = []) async {
        guard Self.modificationsEnabled else {
            logError("Removing zip comments is disabled — enable file modifications in Settings → General first.")
            return
        }
        guard let matchReport = requireMatchReport() else { return }
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        isBusy = true
        defer { isBusy = false }

        let candidates = matchedZipArchiveURLs(for: matchReport)
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            let operations = Self.planRemoveZipCommentsOperations(candidates: candidates, scopeFolders: scopeFolders)
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

        await scan(system: system, folders: scopeFolders.isEmpty ? nil : scopeFolders)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Removed comments from \(succeeded) archive(s); \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Removed comments from \(succeeded) archive(s).")
        } else {
            logWarning("Nothing to remove — no matched archive in this scan has a comment.")
        }
        postFixResultPopup(action: "Remove Zip Comments", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// The plan `planRepairFromMaintenanceFolderPreviewCount` already
    /// built, so `repairFromMaintenanceFolder` can execute it without
    /// scanning the Maintenance folder a second time right after the
    /// user confirms — cheaper, and avoids the two steps silently
    /// disagreeing if a file appears/disappears there in between.
    private var pendingMaintenanceFolderOperations: [RebuildOperation] = []

    /// jensyleo's own request (2026-09-14): "fusionalo con repair from
    /// maintenance folder. A la larga es lo mismo" — replacing a
    /// `.badDump` rom's bad content with a verified-correct donor copy is,
    /// from the user's own point of view, the same "fix it from
    /// Maintenance" action as filling a `.missing` one, just needing a
    /// remove-then-add PAIR instead of a plain add (see
    /// `RebuildPlanner.planReplaceCorruptedRoms`'s own doc comment for
    /// why). Kept in its own array, alongside `pendingMaintenanceFolderOperations`
    /// rather than merged into one list, purely because the two need
    /// different execution shapes (singles vs. pairs-executed-together) —
    /// there is no longer a separate "Replace Corrupted ROMs…" action;
    /// this is planned and executed by the exact same "Repair from
    /// Maintenance Folder…" entry point as the `.missing` case.
    private var pendingMaintenanceFolderReplaceOperations: [RebuildOperation] = []

    /// Scans the optional, read-only Maintenance folder configured in
    /// Settings → General (`MaintenanceFolderSettings`) and plans every
    /// rom it can donate to a `.missing` OR `.badDump` rom in the current
    /// scan — "Find ROMs…". Nothing here ever writes
    /// to, moves, or deletes anything in that folder; it's only ever
    /// read, exactly like `planRepairFromSiblingSetsPreviewCount`'s own
    /// sibling donors. Returns the TOTAL rom count (fills + replacements)
    /// for the caller's preview-before-confirm dialog; the plans
    /// themselves are cached in `pendingMaintenanceFolderOperations`/
    /// `pendingMaintenanceFolderReplaceOperations` for
    /// `repairFromMaintenanceFolder` to execute.
    func planRepairFromMaintenanceFolderPreviewCount(system: RomSystem, scopeFolders: [URL] = []) async -> Int {
        pendingMaintenanceFolderOperations = []
        pendingMaintenanceFolderReplaceOperations = []
        guard let matchReport = requireMatchReport() else { return 0 }
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return 0
        }
        // jensyleo's own request (2026-09-11): scoped to THIS system's own
        // subfolder only ("Maintenance/\(system.name)"), never the whole
        // root — a donor dropped for one system can never accidentally
        // satisfy a different system's missing rom just because they
        // happen to share a hash. Lazily created here (idempotent) rather
        // than requiring a prior visit to Settings — the same "just works"
        // guarantee `LibraryDetailView`'s own `.onAppear` already gives
        // this system's `ScanCache`/`DATCacheLocation` files.
        guard let folderURL = MaintenanceFolderSettings.ensureSubfolderExists(for: system) else {
            logWarning("No Maintenance folder configured — set one in Settings → Systems → MAME first.")
            return 0
        }
        // Always looks across every one of the system's own
        // currently-configured ROM folders, not just Maintenance — a rom
        // that's merely misplaced in a sibling folder (a different drive,
        // a region subfolder, an old backup location) can donate too, not
        // only one deliberately staged in Maintenance. Still strictly
        // read-only — nothing here ever writes to a ROM folder, only reads
        // from it as a donor source.
        //
        // jensyleo's own follow-up (2026-09-26): this used to be gated by
        // a Settings → Fix toggle ("Maintenance Folder Only" vs "+ All ROM
        // Folders") for the unscoped case below — removed outright once
        // he pointed out it never actually changed anything observable,
        // since a SCOPED call (right-clicking one folder/file) already
        // always searched that folder too regardless of the toggle's own
        // value (see the 2026-09-16 note this replaces).
        //
        // jensyleo's own real, live-reproduced report (2026-09-26), same
        // day: right-clicking one specific FILE (sf2cet.zip) whose own
        // missing roms were genuinely available in SIBLING files in the
        // SAME folder (sf2acc.zip/sf2bhh.zip/etc — not Maintenance at all)
        // still failed with "Nothing to repair from the Maintenance
        // folder" — because a scoped call's own `searchFolders` used to be
        // ONLY `[folderURL] + scopeFolders` (Maintenance plus the exact
        // clicked FILE's own path, never its sibling files). "Coloca que
        // busque en todo lugar donde pueda ver" — the donor search is now
        // ALWAYS Maintenance plus every one of the system's own configured
        // ROM folders, scoped or not; `scopeFolders` only ever narrows
        // WHICH games get repaired/verified afterward (see this function's
        // own `restrictToScope`/verification-rescan below), never where a
        // donor can be found.
        let searchFolders: [URL] = [folderURL] + system.romFolderURLs
        isBusy = true
        defer { isBusy = false }
        // Real gap found live by jensyleo (2026-09-22): this donor scan
        // never reported ANY progress (no folder-started/file-found/
        // hashing callbacks at all, unlike `scan(system:)`'s own full set
        // of handlers) — the overlay's generic "Scanning folders…"
        // fallback stayed on screen with no moving numbers for however
        // long a large Maintenance folder took to read and hash, reading
        // as stuck even though it was genuinely working. Wired to the
        // exact same overlay state `scan(system:)` already drives.
        folderScanFilesFound = nil
        currentlyScanningFolder = nil
        scanProgress = nil
        archiveListingProgress = nil
        let folderStartedHandler: @Sendable (URL) -> Void = { [weak self] url in
            Task { @MainActor in self?.currentlyScanningFolder = url }
        }
        let folderProgressHandler: @Sendable (Int) -> Void = { [weak self] count in
            Task { @MainActor in self?.folderScanFilesFound = count }
        }
        let archiveListedHandler: @Sendable (Int, Int) -> Void = { [weak self] read, total in
            Task { @MainActor in self?.archiveListingProgress = (read, total) }
        }
        let hashProgressHandler: @Sendable (ScanProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                self?.folderScanFilesFound = nil
                self?.currentlyScanningFolder = nil
                self?.archiveListingProgress = nil
                self?.scanProgress = progress
            }
        }
        defer {
            folderScanFilesFound = nil
            currentlyScanningFolder = nil
            scanProgress = nil
            archiveListingProgress = nil
        }
        do {
            let (fillOperations, replaceOperations) = try await Task.detached(priority: .userInitiated) {
                let scannedFiles = try FolderScanner.scan(
                    paths: searchFolders, onFileFound: folderProgressHandler, onFolderStarted: folderStartedHandler
                )
                let donorFiles = try await CollectionHasher.hash(
                    scannedFiles: scannedFiles, algorithms: HashAlgorithmSettings.current,
                    onProgress: hashProgressHandler, onArchiveListed: archiveListedHandler
                )
                return (
                    RebuildPlanner.planRepairFromMaintenanceFolder(matchReport: matchReport, donorFiles: donorFiles),
                    RebuildPlanner.planReplaceCorruptedRoms(matchReport: matchReport, donorFiles: donorFiles)
                )
            }.value
            // jensyleo's own request (2026-09-14): "agrega [Repair from
            // Maintenance Folder] al menú contextual" — right-clicking one
            // specific File should only ever repair/replace THAT file, not
            // silently act on every other repairable/replaceable rom in the
            // whole system too. Same `restrictToScope`/`restrictPairsToScope`
            // every other context-menu Fix action already uses — pairs
            // (replace) restricted as PAIRS, never split apart.
            let scopedFillOperations = Self.restrictToScope(fillOperations, scopeFolders: scopeFolders)
            let scopedReplaceOperations = Self.restrictPairsToScope(replaceOperations, scopeFolders: scopeFolders)
            pendingMaintenanceFolderOperations = scopedFillOperations
            pendingMaintenanceFolderReplaceOperations = scopedReplaceOperations
            return scopedFillOperations.count + scopedReplaceOperations.count / 2
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
    ///
    /// Two DIFFERENT "scopes" are in play here, deliberately never
    /// conflated:
    /// 1. **Where a donor is searched for** — always the current system's
    ///    own Maintenance subfolder AND every one of its configured ROM
    ///    folders (see `planRepairFromMaintenanceFolderPreviewCount`'s own
    ///    doc comment — removed the old Settings toggle for this
    ///    2026-09-26, jensyleo: it never changed anything observable) —
    ///    never affected by `scopeFolders`.
    /// 2. **Which folder(s) get VERIFIED afterward** — `scopeFolders`,
    ///    exactly like `fix()`'s own verification rescan. Real bug found
    ///    live by jensyleo: scoping a repair to one folder ("SEGA") still
    ///    triggered a full-system verification rescan, visibly narrating
    ///    an unrelated folder's progress ("CPS3") — confusing, and
    ///    needlessly slow on a NAS-backed folder. Fixed below to match
    ///    `fix()`'s own scoped rescan.
    func repairFromMaintenanceFolder(system: RomSystem, scopeFolders: [URL] = []) async {
        guard Self.modificationsEnabled else {
            logError("Repairing is disabled — enable file modifications in Settings → General first.")
            return
        }
        // Real bug found live by jensyleo (2026-09-14): this used to always
        // check `scopeCoveredByLastScan([])` — "is the WHOLE system
        // covered" — regardless of what scope the preview this executes
        // was actually planned against. A context-menu repair scoped to
        // one specific File (whose scan already covers it, e.g. a scoped
        // "Scan This Folder") was wrongly told to rescan, because `[]`
        // (empty scope) only ever succeeds against a `.wholeSystem` last
        // scan — see `scopeCoveredByLastScan`'s own guard. Must match the
        // exact scope `planRepairFromMaintenanceFolderPreviewCount` was
        // just called with.
        guard scopeCoveredByLastScan(scopeFolders) else {
            logRescanRequiredForFix(scopeFolders: scopeFolders)
            return
        }
        let fillOperations = pendingMaintenanceFolderOperations
        let replaceOperations = pendingMaintenanceFolderReplaceOperations
        pendingMaintenanceFolderOperations = []
        pendingMaintenanceFolderReplaceOperations = []
        guard !fillOperations.isEmpty || !replaceOperations.isEmpty else {
            logWarning("Nothing to repair from the Maintenance folder.")
            return
        }
        isBusy = true
        defer { isBusy = false }

        // Real gap found live by jensyleo (2026-09-22): this action never
        // set `fixActionProgress` at all — unlike `removeRedundantFiles`/
        // `removeRedundantRoms`, which already do (see their own doc
        // comments) — so the overlay fell through every specific phase
        // check and landed on the generic, indeterminate "Scanning
        // folders…" fallback for however long the actual repair writes
        // took, with a label that didn't even describe what was
        // happening.
        let total = fillOperations.count + (replaceOperations.count + 1) / 2
        let fixProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in self?.fixActionProgress = ("Repairing from the Maintenance folder…", completed, total) }
        }
        let (succeeded, failed, failureLines) = await Task.detached(priority: .userInitiated) {
            var succeeded = 0
            var failed = 0
            var failureLines: [String] = []
            for (index, operation) in fillOperations.enumerated() {
                do {
                    try RebuildExecutor.execute([operation])
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("Could not \(Self.describeOperation(operation)): \(error.localizedDescription)")
                }
                fixProgressHandler(index + 1, total)
            }
            // Each `.badDump` replacement plans as a PAIR (remove-then-add,
            // or delete-then-copy/extract — see `RebuildPlanner
            // .planReplaceCorruptedRoms`'s own doc comment) that must be
            // executed TOGETHER, same `stride(by: 2)` shape
            // `renameRomsInArchive`'s own pairs use: a donor read failure
            // between the two halves then leaves that one rom `.missing`
            // rather than silently duplicated or left half-written.
            for pairStart in stride(from: 0, to: replaceOperations.count, by: 2) {
                let pair = Array(replaceOperations[pairStart..<Swift.min(pairStart + 2, replaceOperations.count)])
                do {
                    try RebuildExecutor.execute(pair)
                    succeeded += 1
                } catch {
                    failed += 1
                    failureLines.append("Could not replace \(Self.describeOperation(pair[0])): \(error.localizedDescription)")
                }
                fixProgressHandler(fillOperations.count + pairStart / 2 + 1, total)
            }
            return (succeeded, failed, failureLines)
        }.value
        fixActionProgress = nil

        // Scan first, log after — see `removeUselessFiles`'s own comment on
        // this exact reordering. Scoped to `scopeFolders` (2026-09-16) —
        // see that same function's own doc comment: jensyleo's own report,
        // scoping this exact action to "SEGA" and seeing the verification
        // rescan narrate an unrelated "CPS3" folder's progress instead.
        await scan(system: system, folders: scopeFolders.isEmpty ? nil : scopeFolders)
        for line in failureLines {
            logWarning(line)
        }
        if failed > 0 {
            logWarning("Repaired \(succeeded) rom(s) from the Maintenance folder; \(failed) failed (see the lines just above for which).")
        } else if succeeded > 0 {
            logSuccess("Repaired \(succeeded) rom(s) from the Maintenance folder.")
        }
        postFixResultPopup(action: "Find ROMs", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// How many roms "Make Self-Contained…" would actually copy in, without
    /// touching disk — same preview-before-confirm pattern as every other
    /// Fase 2 action. Returns `0` before any scan has run.
    func planMakeSelfContainedPreviewCount() -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return 0
        }
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
        postFixResultPopup(action: "Make Self-Contained", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// How many ROM entries "Fix Misnamed ROMs Inside Their Archives…"
    /// would actually fix, without touching disk. `RebuildPlanner.planRenameRomsInArchive`
    /// returns TWO operations per rename (add the new name, then remove the
    /// old one — see that function's own doc comment) — this counts pairs,
    /// not raw operations, so the number shown matches what the user
    /// actually asked for.
    func planRenameRomsInArchivePreviewCount(scopeFolders: [URL] = [], entryKeys: Set<String> = []) -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        // Silent on scope mismatch — see `planFixPreviewCount`'s own doc
        // comment: also read from the context-menu construction closure.
        guard scopeCoveredByLastScan(scopeFolders) else { return 0 }
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
        let operations = Self.restrictPairsToEntries(
            Self.restrictPairsToScope(unscopedRenameRomsOperations(matchReport: matchReport), scopeFolders: scopeFolders),
            entryKeys: entryKeys
        )
        return operations.count / 2
    }

    /// Same perf fix, same reasoning, as `unscopedFixOperationsCache`'s
    /// own doc comment — `planRenameRomsInArchive`/`planApplyRomsCasePolicy`
    /// each walk every game's every rom match unscoped, and this ran again
    /// on every right-click.
    private var unscopedRenameRomsOperationsCache: (policy: FileCasePolicy, operations: [RebuildOperation])?

    private func unscopedRenameRomsOperations(matchReport: MatchReport) -> [RebuildOperation] {
        let romsCasePolicy = FixPreferencesSettings.currentRomsCasePolicy()
        if let cached = unscopedRenameRomsOperationsCache, cached.policy == romsCasePolicy { return cached.operations }
        let mismatchOperations = RebuildPlanner.planRenameRomsInArchive(matchReport: matchReport, romsCasePolicy: romsCasePolicy)
        let caseOnlyOperations = RebuildPlanner.planApplyRomsCasePolicy(matchReport: matchReport, policy: romsCasePolicy)
        let operations = mismatchOperations + caseOnlyOperations
        unscopedRenameRomsOperationsCache = (romsCasePolicy, operations)
        return operations
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

        // Same unification as `fix()`'s own `mismatchOperations` +
        // `caseOnlyOperations`, at the entry level: one "Fix" pass should
        // both repair a wrong entry name AND re-case an already-correct
        // one, matching ClrMamePro's single-pass model. `planRenameRomsInArchive`
        // only ever touches a `.misnamed` entry; `planApplyRomsCasePolicy`
        // only ever a `.correct` one — mutually exclusive, so combining
        // them cannot double-rename the same entry. Computed via the
        // cached `unscopedRenameRomsOperations` (main-actor-isolated)
        // BEFORE entering `Task.detached` — see that cache's own doc
        // comment.
        let allOperations = unscopedRenameRomsOperations(matchReport: matchReport)
        // Real gap found live by jensyleo (2026-09-23), same class as
        // `removeUselessFiles`'s own doc comment: never set
        // `fixActionProgress`, so the overlay fell through to its generic
        // "Scanning folders…" fallback with no moving numbers.
        let fixProgressHandler: @Sendable (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in self?.fixActionProgress = ("Renaming roms inside their archives…", completed, total) }
        }
        let outcome = await Task.detached(priority: .userInitiated) {
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
            let totalPairs = operations.count / 2
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
                fixProgressHandler(pairStart / 2 + 1, totalPairs)
            }
            return (
                succeeded: succeeded, failed: failed,
                plannedCount: allOperations.count / 2, inScopeCount: operations.count / 2,
                failureLines: failureLines
            )
        }.value
        fixActionProgress = nil
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
            logWarning("Nothing to fix\(scopeSuffix) — every rom entry already matches the DAT, styled exactly per \"Roms case\" (\(FixPreferencesSettings.currentRomsCasePolicy().rawValue)).")
        }
        postFixResultPopup(action: "Fix Misnamed ROMs Inside Archives", succeeded: succeeded, failed: failed, failureLines: outcome.failureLines)
    }

    /// How many redundant roms "Strip Redundant ROMs (Split)…" would
    /// actually remove, without touching disk. Returns `0` before any scan
    /// has run.
    func planConvertToSplitPreviewCount() -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return 0
        }
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
        postFixResultPopup(action: "Strip Redundant ROMs (Split)", succeeded: succeeded, failed: failed, failureLines: failureLines)
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
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return 0
        }
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
        postFixResultPopup(action: "Handle Corrupted Files", succeeded: succeeded, failed: failed, failureLines: failureLines)
    }

    /// How many clones "Merge Clones (Merged)…" would actually fold into
    /// their parent and delete, without touching disk. Returns `0` before
    /// any scan has run. See `RebuildPlanner.planConvertToMerged`'s own
    /// doc comment for exactly which clones qualify.
    func planConvertToMergedPreviewCount() -> Int {
        guard let matchReport = requireMatchReport() else { return 0 }
        guard scopeCoveredByLastScan([]) else {
            logRescanRequiredForFix(scopeFolders: [])
            return 0
        }
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
        postFixResultPopup(action: "Merge Clones (Merged)", succeeded: succeeded, failed: failed, failureLines: failureLines)
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
        case .createDummyFile(let url, _):
            return "create dummy rom \"\(url.lastPathComponent)\""
        case .createDummyZipEntry(let targetArchive, let entryName, _):
            return "create dummy rom \"\(entryName)\" in \"\(targetArchive.lastPathComponent)\""
        case .clearZipComment(let archive):
            return "remove comment from \"\(archive.lastPathComponent)\""
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
    /// Which of `system`'s own configured ROM folders each of `urls`
    /// actually lives under — feeds `scan(system:folders:)`'s own scoping
    /// for the generic File Actions below (`moveFilesToTrash`/
    /// `deleteFilesPermanently`/`moveRomEntriesToTrash`/
    /// `deleteRomEntriesPermanently`), which take raw URLs/entries rather
    /// than an already-known `scopeFolders` list the way
    /// `removeUselessFiles`/`removeRedundantFiles`/`removeRedundantRoms`
    /// do.
    ///
    /// Real report (2026-09-21, jensyleo): deleting even a single file from
    /// one ROM folder "vuelve y escanea todo" — these four functions always
    /// called the plain, unscoped `scan(system: system)`, which (per
    /// `scan(system:folders:)`'s own doc comment) walks and force-rehashes
    /// EVERY configured folder, not just the one the deleted file came
    /// from. Every other destructive action in this file already scopes
    /// its own verification rescan (see `removeUselessFiles`'s own doc
    /// comment on this exact history) — these four just never got that
    /// same treatment, since they were added later, generically, without a
    /// `scopeFolders` parameter of their own to reuse.
    private nonisolated static func romFolders(containing urls: [URL], in system: RomSystem) -> [URL] {
        var result: [URL] = []
        for url in urls {
            guard let folder = system.romFolderURLs.first(where: { url.path.hasPrefix($0.path) }), !result.contains(folder) else { continue }
            result.append(folder)
        }
        return result
    }

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
        case .createDummyFile(let at, _):
            path = at
        case .createDummyZipEntry(let targetArchive, _, _):
            path = targetArchive
        case .clearZipComment(let archive):
            path = archive
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
