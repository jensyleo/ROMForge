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
    var errorMessage: String?
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
    private(set) var logLines: [String] = []

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

    /// Backs the in-memory cache above with a disk-persisted one
    /// (`DATFileCache`) — the in-memory cache only lives for as long as this
    /// `LibraryViewModel` does, so it's already empty again on every fresh
    /// app launch, and `preloadDAT`/`scan` would otherwise silently re-parse
    /// the same DAT from scratch every single time the app opens even
    /// though nothing about it changed. Runs off the main actor (called
    /// from inside a `Task.detached`), so it only touches `FileManager`/
    /// `DATFileCache`, never `self`.
    private nonisolated static func loadDAT(
        datURL: URL,
        mergeMode: SetMergeMode,
        biosMergeMode: SetMergeMode,
        diskCacheURL: URL,
        onFileReadProgress: @escaping @Sendable (Int64, Int64) -> Void,
        onCountingStarted: @escaping @Sendable () -> Void,
        onCountingProgress: @escaping @Sendable (Int, Int) -> Void,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) throws -> DATFile {
        let attributes = try FileManager.default.attributesOfItem(atPath: datURL.path)
        let sourceSize = (attributes[.size] as? Int64) ?? Int64((attributes[.size] as? Int) ?? 0)
        let sourceModificationDate = (attributes[.modificationDate] as? Date) ?? Date.distantPast
        if let cached = try? DATFileCache.load(contentsOf: diskCacheURL),
           cached.isValid(sourceSize: sourceSize, sourceModificationDate: sourceModificationDate, mergeMode: mergeMode, biosMergeMode: biosMergeMode) {
            return cached.dat
        }
        let dat = try DATLoader.load(
            contentsOf: datURL, mergeMode: mergeMode, biosMergeMode: biosMergeMode,
            onFileReadProgress: onFileReadProgress, onCountingStarted: onCountingStarted, onCountingProgress: onCountingProgress, onProgress: onProgress
        )
        try? DATFileCache(sourceSize: sourceSize, sourceModificationDate: sourceModificationDate, mergeMode: mergeMode, biosMergeMode: biosMergeMode, dat: dat).save(to: diskCacheURL)
        return dat
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

    private func log(_ message: String) {
        let timestamp = DateFormatter.logTimestamp.string(from: Date())
        logLines.append("[\(timestamp)] \(message)")
    }

    /// Loads the last persisted audit for `system`, if any, so opening a
    /// previously-scanned system shows its last results immediately instead
    /// of an empty view until the user hits Scan again. A real Scan always
    /// re-derives the truth from disk and overwrites this.
    func loadPersistedReport(system: RomSystem) {
        guard auditReport == nil else { return }
        do {
            let db = try AuditDatabaseLocation.open()
            guard let report = try db.loadReport(systemID: system.id.uuidString) else { return }
            auditReport = report
            if let meta = try db.loadScanMeta(systemID: system.id.uuidString), let name = meta.datName {
                datHeader = DATHeader(name: name, description: "", version: meta.datVersion ?? "", author: "")
            }
        } catch {
            // A missing/corrupt database just means no cached results to
            // show yet — not worth surfacing as a user-facing error.
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
    func removeFolder(_ folderURL: URL, system: RomSystem) {
        ScanCacheLocation.remove(for: system)
        guard let previous = auditReport else { return }
        let folderPath = folderURL.path
        let prunedEntries = previous.entries.filter { entry in
            guard let path = entry.path else { return true }
            return !path.path.hasPrefix(folderPath)
        }
        guard prunedEntries.count != previous.entries.count else { return }
        var correct = 0, incorrect = 0, badDump = 0, missing = 0, surplus = 0
        for entry in prunedEntries {
            switch entry.status {
            case .correct: correct += 1
            case .incorrect: incorrect += 1
            case .badDump: badDump += 1
            case .missing: missing += 1
            case .surplus: surplus += 1
            }
        }
        let pruned = AuditReport(entries: prunedEntries, correct: correct, incorrect: incorrect, badDump: badDump, missing: missing, surplus: surplus)
        auditReport = pruned
        do {
            try AuditDatabaseLocation.open().saveReport(
                pruned, systemID: system.id.uuidString, datName: datHeader?.name, datVersion: datHeader?.version, scannedAt: Date()
            )
        } catch {
            log("Warning: couldn't persist the folder removal: \(error)")
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
        errorMessage = nil
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
        do {
            let datLoadStart = Date()
            let detached = Task.detached(priority: .userInitiated) {
                try Self.loadDAT(
                    datURL: datURL, mergeMode: mergeMode, biosMergeMode: biosMergeMode, diskCacheURL: diskCacheURL,
                    onFileReadProgress: fileReadProgressHandler, onCountingStarted: countingStartedHandler, onCountingProgress: countingProgressHandler, onProgress: datLoadProgressHandler
                )
            }
            cancelDetachedWork = { detached.cancel() }
            let dat = try await detached.value
            cachedDATKey = key
            cachedDATFile = dat
            datHeader = dat.header
            Self.sharedDATCache[system.id] = (key, dat)
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
            log("Failed to load DAT: \(String(describing: error))")
            errorMessage = String(describing: error)
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
        errorMessage = nil
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
        archiveListingProgress = nil
        logLines.removeAll()
        defer { isBusy = false }

        let scanStart = Date()
        let targetFolders = folders ?? system.romFolderURLs
        let isScopedScan = folders != nil && folders != system.romFolderURLs
        log(
            isScopedScan
                ? "Scanning \(targetFolders.map(\.lastPathComponent).joined(separator: ", "))…"
                : "Scanning \(system.name) (\(targetFolders.count) folder\(targetFolders.count == 1 ? "" : "s"))…"
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
            let archiveListedHandler: @Sendable (Int, Int) -> Void = { [weak self] read, total in
                Task { @MainActor in self?.archiveListingProgress = (read, total) }
            }
            let progressHandler: @Sendable (ScanProgress) -> Void = { [weak self] progress in
                Task { @MainActor in
                    // First hashing update means the folder walk and archive
                    // listing pass are both done — clear their live counts
                    // so the overlay/log switch phases.
                    self?.folderScanFilesFound = nil
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
                if let reusableDAT {
                    dat = reusableDAT
                    cachedDATLogHandler()
                } else {
                    let datLoadStart = Date()
                    dat = try Self.loadDAT(
                        datURL: datURL, mergeMode: mergeMode, biosMergeMode: biosMergeMode, diskCacheURL: datDiskCacheURL,
                        onFileReadProgress: fileReadProgressHandler, onCountingStarted: countingStartedHandler, onCountingProgress: countingProgressHandler, onProgress: datLoadProgressHandler
                    )
                    datLoadLogHandler(Date().timeIntervalSince(datLoadStart))
                }
                let walkStart = Date()
                // `paths` (not `folders`) since `targetFolders` may now
                // include an individual file (a single archive rescanned
                // directly, e.g. from a game's own right-click menu) mixed
                // in alongside whole folders — `FolderScanner.scan(paths:)`
                // handles either per-entry.
                let scannedFiles = try FolderScanner.scan(paths: targetFolders, onFileFound: folderProgressHandler)
                walkLogHandler(scannedFiles.count, Date().timeIntervalSince(walkStart))
                // A file whose size/mtime match a previous scan's cache
                // entry is served from there instead of rehashed — a real
                // collection can be tens of thousands of files, most of
                // which never change between scans.
                let cache = (try? ScanCache.load(contentsOf: cacheURL)) ?? ScanCache()
                // Loose files are hashed directly; .zip archives are expanded
                // and their entries hashed individually, since that's where
                // most ROM sets actually keep each game.
                let hashedFiles = try await CollectionHasher.hash(scannedFiles: scannedFiles, cache: cache, algorithms: hashAlgorithms, onProgress: progressHandler, onArchiveListed: archiveListedHandler)
                try? ScanCache.build(from: hashedFiles).save(to: cacheURL)
                matchingStartedHandler()
                let matchReport = ROMMatcher.match(dat: dat, hashedFiles: hashedFiles, onProgress: matchProgressHandler)
                var auditReport = AuditReporter.generate(from: matchReport)
                // CHDs never go through `ROMMatcher` at all (a disk isn't a
                // `DATRom`) — audited separately here, by each CHD's own
                // header SHA1 (`DiskAuditor`/`CHDMatcher`), then folded into
                // the same report so a scanned folder of MAME discs shows
                // up as real Correct/Incorrect/Missing rows instead of
                // silently vanishing from the audit entirely.
                let chdFiles = scannedFiles.filter { $0.url.pathExtension.lowercased() == "chd" }.map(\.url)
                // `DiskAuditor.audit` always evaluates every disk in the
                // *entire* DAT (it has no way to scope itself to just the
                // files actually scanned) — fine for a real full-folder
                // scan, but a real bug for a scoped rescan of one
                // unrelated rom file (`isScopedScan`, e.g. "Rescan This
                // File" on a single .zip): `chdFiles` comes back empty
                // (no .chd was in this scan's scope at all), so it would
                // freshly mark *every* disk in the whole DAT "missing",
                // relying on `Self.merge`'s prior-state reconciliation
                // below to quietly restore each one's real status —
                // wasted computation at best, and a real path to a
                // correct CHD's status flipping wrong if that
                // reconciliation ever mismatches (jensyleo's own report,
                // 2026-07-30: "rescan this file" on a rom left CHD
                // statuses inconsistent). Skipped entirely for a scoped
                // scan that touched no `.chd` at all — the previous
                // report's disk entries are simply left untouched by
                // `Self.merge` in that case, nothing to reconcile.
                let shouldAuditDisks = !chdFiles.isEmpty || (!isScopedScan && dat.games.contains(where: { !$0.disks.isEmpty }))
                if shouldAuditDisks {
                    let diskEntries = DiskAuditor.audit(dat: dat, chdFiles: chdFiles)
                    auditReport = AuditReporter.merging(diskEntries: diskEntries, into: auditReport)
                }
                return (dat.header, matchReport, auditReport, dat, shouldAuditDisks)
            }
            cancelDetachedWork = { detached.cancel() }
            let (header, report, audit, dat, disksWereAuditedFresh) = try await detached.value

            cachedDATKey = datCacheKey
            cachedDATFile = dat
            datHeader = header
            let mergedAudit: AuditReport
            if isScopedScan, let previous = auditReport {
                // Disk entries were skipped entirely above (nothing
                // relevant to this scan's own scope), so `audit.entries`
                // has none at all right now — carrying the previous
                // report's own disk rows over unchanged, rather than
                // letting `Self.merge`'s (rom-oriented) key-reconciliation
                // touch them, is what actually avoids the "rescan this
                // file leaves CHD statuses inconsistent" bug: there's
                // nothing to reconcile when nothing about them changed.
                let freshForMerge = disksWereAuditedFresh
                    ? audit
                    : AuditReport(
                        entries: audit.entries + previous.entries.filter(\.isDisk),
                        correct: audit.correct, incorrect: audit.incorrect, badDump: audit.badDump, missing: audit.missing, surplus: audit.surplus
                    )
                mergedAudit = Self.merge(previous: previous, fresh: freshForMerge, scopedFolders: targetFolders)
                // `matchReport` backs `fix()`, which is disabled
                // (`modificationsEnabled`) — not worth merging its far
                // richer per-game structure for a feature that can't run.
            } else {
                matchReport = report
                mergedAudit = audit
            }
            auditReport = mergedAudit
            scanProgress = nil
            folderScanFilesFound = nil
            archiveListingProgress = nil
            let totalDuration = Date().timeIntervalSince(scanStart)
            log(String(format: "Done in %.1fs: %d correct, %d incorrect, %d missing, %d surplus.", totalDuration, mergedAudit.correct, mergedAudit.incorrect, mergedAudit.missing, mergedAudit.surplus))
            do {
                try AuditDatabaseLocation.open().saveReport(
                    mergedAudit, systemID: system.id.uuidString, datName: header.name, datVersion: header.version, scannedAt: Date()
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
            archiveListingProgress = nil
            scanProgress = nil
            isMatching = false
            matchProgress = nil
            log("Failed: \(String(describing: error))")
            errorMessage = String(describing: error)
        }
    }

    /// Combines a freshly-scoped scan (only some of the system's folders)
    /// with the last full/partial report — a "missing" verdict from the
    /// scoped scan means only "not found in *this* folder", not "not found
    /// anywhere", so it falls back to whatever the previous report already
    /// knew for that exact (game, rom) pair rather than overwriting a real
    /// match with a false negative. Matched by (game, rom name) since
    /// that's stable across scans of the same DAT regardless of which
    /// folder a file happens to live in.
    private static func merge(previous: AuditReport, fresh: AuditReport, scopedFolders: [URL]) -> AuditReport {
        var merged: [AuditEntry] = []
        merged.reserveCapacity(fresh.entries.count + previous.entries.count)
        // Single pass over the merged result for all five counts, instead
        // of five separate full-array `.filter { }.count` passes — the
        // same redundant-rescan cost `computeScopedStatusCounts` was
        // already fixed for, here too.
        var correct = 0, incorrect = 0, badDump = 0, missing = 0, surplus = 0
        func append(_ entry: AuditEntry) {
            merged.append(entry)
            switch entry.status {
            case .correct: correct += 1
            case .incorrect: incorrect += 1
            case .badDump: badDump += 1
            case .missing: missing += 1
            case .surplus: surplus += 1
            }
        }

        let scopedPaths = scopedFolders.map(\.path)

        // Which games did this scan actually touch — i.e. have a REAL file
        // (not a `.foundElsewhere` borrowed path, see its own doc comment)
        // somewhere inside `scopedFolders`, per `fresh`'s own results.
        // Real bug found live by jensyleo (2026-08-04): the previous
        // version of this function only ever detected "touched" this way
        // for a *single-file* scope (`scopedFolders` naming exactly one
        // game by MAME's own "archive named after the machine"
        // convention) — any whole-*folder* scope (an ordinary "Scan
        // Folder" click, the overwhelmingly common case) fell back to a
        // much weaker per-rom `RomKey` reconciliation that only restored
        // `previous`'s status when fresh reported a rom plain `.missing`.
        // Once `ROMMatcher` started also reporting `.foundElsewhere`/
        // `.hashMismatch` (both map to `.incorrect`, not `.missing`) for a
        // rom it merely couldn't claim in *this* scan's own limited file
        // pool, that per-rom check no longer caught them: scanning one
        // folder (e.g. NEOGEO) could produce a stray `.incorrect` verdict
        // for some *completely different* system's game (e.g. a CPS1 rom
        // whose declared hash happens to collide, or one riding along via
        // `foundElsewhere`'s intentionally-generous cross-scan lookup) —
        // and since that verdict wasn't literally `.missing`, the old
        // per-rom check trusted it outright over the real, correct
        // `previous` status, flipping an untouched game's entire row
        // yellow. Fixed by generalizing the *entire* file-scope's
        // wholesale-carryover strategy to folder scopes too: a game this
        // scan didn't actually touch has its whole previous row carried
        // forward completely unreconciled, regardless of what fresh
        // (wrongly, out of its own limited scope) claims about it.
        var touchedGameNames: Set<String> = []
        for entry in fresh.entries {
            guard let game = entry.game, entry.foundElsewhereArchiveName == nil, let path = entry.path,
                  scopedPaths.contains(where: { path.path.hasPrefix($0) }) else { continue }
            touchedGameNames.insert(game.lowercased())
        }
        // Real bug found live by jensyleo (2026-08-04): a game whose entire
        // fresh footprint is surplus-derived (`entry.game == nil` — e.g.
        // `qsound_hle` under Split, where its only rom is merge-tagged and
        // stripped from its own expected list entirely, so nothing with
        // `game == "qsound_hle"` can ever exist in a Split-mode scan) never
        // satisfied the loop above at all, since that loop only ever looks
        // at entries that already have a real `game`. Untouched by this
        // definition, `qsound_hle`'s *stale* `previous` row (e.g. a
        // genuine `.correct` claim from an earlier scan under a merge mode
        // where its own rom wasn't stripped) got carried forward wholesale
        // instead of being superseded — alongside the fresh scan's own
        // surplus entry for the exact same physical file (always appended
        // unconditionally below), producing two contradictory rows for the
        // same rom slot: a stale green "Ok" next to a fresh yellow "Not
        // needed here". Any real, physically-scanned file inside scope —
        // rom-matched or not — did genuinely get looked at during this
        // scan, so whatever game its own archive's name implies must count
        // as touched too, regardless of whether the matcher ended up
        // attributing it to that name.
        for entry in fresh.entries {
            guard entry.game == nil, let path = entry.path, scopedPaths.contains(where: { path.path.hasPrefix($0) }) else { continue }
            touchedGameNames.insert(path.deletingPathExtension().lastPathComponent.lowercased())
        }
        // A single-FILE scope (e.g. "Rescan This File") also names its own
        // touched game directly by filename — needed for the edge case
        // where *every* one of that file's roms came back missing/
        // `.foundElsewhere` (no real in-scope path for the loop above to
        // have found at all), which would otherwise look "untouched".
        for url in scopedFolders {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                touchedGameNames.insert(url.deletingPathExtension().lastPathComponent.lowercased())
            }
        }

        // A rom's own archive is named after its *game* (MAME convention),
        // but a CHD disk's physical filename is the *disk's own* declared
        // name, which often doesn't match its game's name at all (e.g.
        // disk "cap-sf3-3" belongs to game "sfiii") — checked against
        // `entry.name` too, not just `entry.game`, so rescanning one
        // specific `.chd` file is correctly recognized as touching that
        // disk's entry.
        func isTouched(_ entry: AuditEntry, game: String) -> Bool {
            touchedGameNames.contains(game.lowercased()) || touchedGameNames.contains(entry.name.lowercased())
        }

        for entry in fresh.entries {
            guard let game = entry.game else {
                append(entry) // a surplus file found fresh, inside scope
                continue
            }
            if isTouched(entry, game: game) { append(entry) }
            // Untouched games are skipped here entirely — carried forward
            // from `previous` below instead, wholesale.
        }
        for entry in previous.entries {
            if let game = entry.game {
                if !isTouched(entry, game: game) { append(entry) }
            } else {
                let isInsideScope = entry.path.map { path in scopedPaths.contains { path.path.hasPrefix($0) } } ?? false
                if !isInsideScope { append(entry) }
            }
        }

        return AuditReport(entries: merged, correct: correct, incorrect: incorrect, badDump: badDump, missing: missing, surplus: surplus)
    }


    func fix(system: RomSystem) async {
        guard Self.modificationsEnabled else {
            errorMessage = "Repairing ROMs is disabled for now — ROMForge only scans and reports, it won't touch your files."
            return
        }
        guard let matchReport else {
            errorMessage = "Scan first."
            return
        }
        isBusy = true
        errorMessage = nil
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
                errorMessage = "Fixed what it could; \(skippedCount) misnamed ROM(s) inside .zip/.7z archives were left as-is (not supported yet)."
            }
        } catch {
            errorMessage = String(describing: error)
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

    func exportReport() {
        guard let auditReport else {
            errorMessage = "Scan first."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "ROMForge Report.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try Self.csv(for: auditReport).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Exports a "fixdat" — a normal DAT containing only the missing/
    /// incorrect entries from the last scan — handleable by any Logiqx-
    /// compatible tool to source exactly the gap. Uses the loaded DAT's own
    /// name so the fixdat is traceable back to its source.
    func exportFixdat(system: RomSystem) {
        guard let auditReport else {
            errorMessage = "Scan first."
            return
        }
        let datName = datHeader?.name ?? system.name
        let panel = NSSavePanel()
        // No content-type restriction: a ".dat" file's UTI doesn't conform
        // to public.xml even though its content is XML, so restricting to
        // .xml here would silently append ".xml" onto the ".dat" name
        // instead of respecting it — the exact same picker pitfall already
        // fixed once for the DAT-open panel in AddSystemSheet.
        panel.allowedContentTypes = []
        panel.nameFieldStringValue = "fixDat_\(datName).dat"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try FixDatExporter.generate(from: auditReport, datName: datName).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private static func csv(for report: AuditReport) -> String {
        var lines = ["status,game,name,path"]
        for entry in report.entries {
            let fields = [entry.status.rawValue, entry.game ?? "", entry.name, entry.path?.path ?? ""]
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
