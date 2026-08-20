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
/// One line of the Log panel — `isError` picks red instead of the default
/// text color, jensyleo's own request (2026-08-17) after a MAME
/// launch-failure message (previously its own separate `errorMessage`
/// sheet) moved into this same log instead: "esto debería salir en la
/// ventana de log... mantén el color rojo del error."
struct LogLine: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let isError: Bool
}

@Observable
@MainActor
final class LibraryViewModel {
    /// Single switch gating every file-modifying operation. `fix()` checks
    /// this before doing anything, so there's no path to a rename/move even
    /// if the disabled Fix button were somehow triggered anyway.
    static let modificationsEnabled = false

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

    func log(_ message: String, isError: Bool = false) {
        let timestamp = DateFormatter.logTimestamp.string(from: Date())
        logLines.append(LogLine(text: "[\(timestamp)] \(message)", isError: isError))
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
        log(message, isError: true)
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
                    self?.log("Warning: couldn't persist the folder removal: \(error)")
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
            log("DAT loading cancelled.")
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
    /// every configured folder (`folders: nil`). Passing a subset (e.g. one
    /// folder selected under "Rom files") only re-derives *that* subset
    /// from disk instead of the whole collection — useful for a system
    /// split across several folders, where re-hashing everything just to
    /// pick up a change in one of them would be wasteful. A scoped scan's
    /// result is merged into the existing report (`Self.merge`) rather than
    /// replacing it outright, so the other folders' last-known results
    /// aren't lost or wrongly reported "missing" just because this run
    /// didn't look at them.
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
        // Every scan always walks and matches EVERY one of the system's ROM
        // folders, never just the selected scope — jensyleo's own
        // architectural call (2026-08-06), and the fix for a whole class of
        // bugs rather than one instance of it.
        //
        // Scoped scans used to hand `ROMMatcher` only the selected folder's
        // files, then reconcile the partial result against the previous
        // report afterward. That reconciliation was inherently guesswork: a
        // matcher that can't see the other folders cannot know that
        // `ghouls.zip` also sits in one of them, so it claimed whichever
        // copy it was shown and the merge step had to decide, blind, what to
        // keep — producing the game-vanishes-from-the-other-folder flip-flop
        // (TESTING.md §9.2 scenario #4) and three earlier live-found bugs
        // before it. jensyleo's own reasoning for removing it outright: if
        // the app can't compare across folders, it can never correctly
        // decide which duplicate to keep and which to repair, so ROM fixing
        // could never be built on top of it.
        //
        // Affordable because the two costs are wildly asymmetric — measured
        // 2026-08-06 on jensyleo's own real collection (5 folders, 161
        // archives, ~1.8 GB, MAME 0.288 → 50,097 games):
        //
        //   DAT load       10.5s   (reused within a session, `cachedDATFile`)
        //   hash, cold    408.7s   ← the only genuinely expensive phase
        //   hash, warm      0.34s  ← `ScanCache`, unchanged files
        //   match ALL      11.3s   ← what this change makes unconditional
        //   audit report    0.39s
        //
        // So re-reading bytes is ~1200x more expensive than a cache hit, and
        // matching everything costs about as much as loading the DAT once.
        // The selected scope therefore now controls only what gets re-read
        // from disk (`ScanCache.removingEntries(under:)`), never what gets
        // matched: the expensive phase still scales with what actually
        // changed, while the result is always a complete, correct report
        // needing no reconciliation at all.
        let allFolders = system.romFolderURLs
        // Paths the user explicitly asked to re-read ("Scan Folder" on one
        // folder, "Rescan This File" on one archive) — their cached hashes
        // are dropped so they're genuinely rehashed even if size+mtime are
        // unchanged, which is the whole point of asking.
        let forcedRescanPaths = (folders != nil && folders != allFolders) ? (folders ?? []) : []
        log(
            forcedRescanPaths.isEmpty
                ? "Scanning \(system.name) (\(allFolders.count) folder\(allFolders.count == 1 ? "" : "s"))…"
                : "Rescanning \(forcedRescanPaths.map(\.lastPathComponent).joined(separator: ", ")) (matching against all \(allFolders.count) folders)…"
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
                    self?.log("Scanning \(url.lastPathComponent)…")
                }
            }
            // jensyleo's own request (2026-08-05): a subfolder nested past
            // `FolderScanner.maxSubfolderDepth` is skipped, not fatal to the
            // whole scan — logged so it's still visible (rather than
            // silently never-mentioned) that ROMForge never looked inside
            // it at all.
            let skippedTooDeepHandler: @Sendable (URL) -> Void = { [weak self] url in
                Task { @MainActor in self?.log("Skipped (nested too deep, not scanned): \(url.path)") }
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
                // Always every folder — see this function's own doc comment
                // above for why the selected scope no longer limits this.
                // `paths` (not `folders`) since `FolderScanner.scan(paths:)`
                // handles a whole folder or an individual file per entry.
                let scannedFiles = try FolderScanner.scan(paths: allFolders, onFileFound: folderProgressHandler, onSkippedTooDeep: skippedTooDeepHandler, onFolderStarted: folderStartedHandler)
                walkLogHandler(scannedFiles.count, Date().timeIntervalSince(walkStart))
                // A file whose size/mtime match a previous scan's cache
                // entry is served from there instead of rehashed — a real
                // collection can be tens of thousands of files, most of
                // which never change between scans. This is what makes
                // always-walk-everything affordable (see above): only what
                // genuinely changed, plus whatever the user explicitly asked
                // to re-read, actually costs anything.
                let cache = ((try? ScanCache.load(contentsOf: cacheURL)) ?? ScanCache())
                    .removingEntries(under: forcedRescanPaths)
                // Loose files are hashed directly; .zip archives are expanded
                // and their entries hashed individually, since that's where
                // most ROM sets actually keep each game.
                let hashedFiles = try await CollectionHasher.hash(scannedFiles: scannedFiles, cache: cache, algorithms: hashAlgorithms, onProgress: progressHandler, onArchiveListed: archiveListedHandler)
                try? ScanCache.build(from: hashedFiles).save(to: cacheURL)
                matchingStartedHandler()
                let matchReport = try ROMMatcher.match(dat: dat, hashedFiles: hashedFiles, onProgress: matchProgressHandler, cancellationFlag: cancellationFlag)
                var auditReport = try AuditReporter.generate(from: matchReport)
                // CHDs never go through `ROMMatcher` at all (a disk isn't a
                // `DATRom`) — audited separately here, by each CHD's own
                // header SHA1 (`DiskAuditor`/`CHDMatcher`), then folded into
                // the same report so a scanned folder of MAME discs shows
                // up as real Correct/Incorrect/Missing rows instead of
                // silently vanishing from the audit entirely.
                let chdFiles = scannedFiles.filter { $0.url.pathExtension.lowercased() == "chd" }.map(\.url)
                // `DiskAuditor.audit` always evaluates every disk in the
                // entire DAT, which is now exactly right: `chdFiles` covers
                // every folder on every scan, so its verdicts are always
                // complete rather than scoped guesses needing repair
                // afterward. This used to need a carve-out precisely because
                // a scoped scan could hand it an empty `chdFiles` and have it
                // wrongly mark every disk in the DAT missing (jensyleo's own
                // report, 2026-07-30: "rescan this file" on a rom left CHD
                // statuses inconsistent) — the always-scan-everything change
                // above removes the situation entirely.
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
                return (dat.header, matchReport, auditReport, dat, freshlyParsed, freshlyParsedIdentity)
            }
            cancelDetachedWork = { detached.cancel() }
            let (header, report, audit, dat, freshlyParsed, freshlyParsedIdentity) = try await detached.value
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
            let displayedAudit = AuditReporter.replacingRescannedEntries(in: auditReport, with: audit, rescannedPaths: forcedRescanPaths)
            matchReport = report
            auditReport = displayedAudit
            scanProgress = nil
            folderScanFilesFound = nil
            currentlyScanningFolder = nil
            archiveListingProgress = nil
            let totalDuration = Date().timeIntervalSince(scanStart)
            log(String(format: "Done in %.1fs: %d correct, %d incorrect, %d missing, %d surplus.", totalDuration, audit.correct, audit.incorrect, audit.missing, audit.surplus))
            do {
                try AuditDatabaseLocation.open().saveReport(
                    audit, systemID: system.id.uuidString, datName: header.name, datVersion: header.version, scannedAt: Date()
                )
            } catch {
                log("Warning: couldn't persist this scan's results: \(error)")
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
            log("Scan cancelled.")
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

    func fix(system: RomSystem) async {
        guard Self.modificationsEnabled else {
            logError("Repairing ROMs is disabled for now — ROMForge only scans and reports, it won't touch your files.")
            return
        }
        guard let matchReport else {
            logError("Scan first.")
            return
        }
        isBusy = true
        defer { isBusy = false }

        do {
            let skippedCount = try await Task.detached(priority: .userInitiated) {
                let allOperations = RebuildPlanner.planRepair(matchReport: matchReport)
                // A rename planned from inside a .zip/.7z would target the
                // archive itself (there's no standalone file for one entry)
                // — repairing an archived ROM's name isn't supported yet, so
                // those are skipped rather than corrupting the archive.
                let (eligible, skipped) = Self.partitionArchivedRenames(allOperations)
                try RebuildExecutor.execute(eligible)
                return skipped.count
            }.value

            await scan(system: system)
            if skippedCount > 0 {
                logError("Fixed what it could; \(skippedCount) misnamed ROM(s) inside .zip/.7z archives were left as-is (not supported yet).")
            }
        } catch {
            logError(String(describing: error))
        }
    }

    private nonisolated static let archivedRenameExtensions: Set<String> = ["zip", "7z"]

    private nonisolated static func partitionArchivedRenames(_ operations: [RebuildOperation]) -> (eligible: [RebuildOperation], skipped: [RebuildOperation]) {
        var eligible: [RebuildOperation] = []
        var skipped: [RebuildOperation] = []
        for operation in operations {
            if case .rename(let from, _) = operation, archivedRenameExtensions.contains(from.pathExtension.lowercased()) {
                skipped.append(operation)
            } else {
                eligible.append(operation)
            }
        }
        return (eligible, skipped)
    }

}

private extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
