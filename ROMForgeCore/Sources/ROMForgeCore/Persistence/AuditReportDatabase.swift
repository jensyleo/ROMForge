// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import SQLite3

public enum AuditReportDatabaseError: Error, Equatable, CustomStringConvertible {
    case cannotOpen(String)
    case sqlError(String)

    public var description: String {
        switch self {
        case .cannotOpen(let message): return "Could not open database: \(message)"
        case .sqlError(let message): return "SQLite error: \(message)"
        }
    }
}

/// Persists each configured system's last audit — every `AuditEntry` plus
/// which DAT produced it and when — so reopening ROMForge (or just
/// re-selecting a system) shows the last real scan's results immediately,
/// instead of an empty view until the user hits Scan again. A fresh Scan
/// always re-derives the truth from disk; this only caches its *result*.
///
/// One SQLite file for the whole app (`romforge.sqlite3`), not one per
/// system — `system_id` is just a column, the same shape MAME/RomVault-style
/// tools use for a Games/Roms/ScanHistory schema. Uses Darwin's built-in
/// `SQLite3` module directly (no Homebrew/vendored dependency, same
/// portability stance as `CZlib`). A fresh connection is opened per call
/// (matching SQLite's own recommended usage for infrequent, non-contended
/// access) rather than held open for the object's lifetime.
public final class AuditReportDatabase {
    private static let currentSchemaVersion: Int32 = 7

    private let path: String

    public init(path: String) throws {
        self.path = path
        let db = try Self.open(path)
        defer { sqlite3_close(db) }
        try Self.migrateIfNeeded(db)
    }

    // MARK: - Public API

    public func saveReport(_ report: AuditReport, systemID: String, datName: String?, datVersion: String?, scannedAt: Date) throws {
        let db = try Self.open(path)
        defer { sqlite3_close(db) }

        try Self.exec(db, "BEGIN TRANSACTION;")
        do {
            try Self.bindAndExec(db, "DELETE FROM audit_entries WHERE system_id = ?;", [.text(systemID)])
            try Self.bindAndExec(db, "DELETE FROM scans WHERE system_id = ?;", [.text(systemID)])
            try Self.bindAndExec(
                db,
                """
                INSERT INTO scans (system_id, dat_name, dat_version, scanned_at)
                VALUES (?, ?, ?, ?);
                """,
                [.text(systemID), .textOrNull(datName), .textOrNull(datVersion), .text(ISO8601DateFormatter().string(from: scannedAt))]
            )
            // One statement prepared and reused (bind → step → reset) for
            // every entry, instead of a fresh `sqlite3_prepare_v2` per row —
            // a real scan's `audit_entries` can run to tens of thousands of
            // rows, and re-parsing/re-compiling the same SQL that many
            // times inside one transaction was pure waste.
            let rowValues: [[BindValue]] = report.entries.map { entry in
                [
                    .text(systemID), .text(entry.status.rawValue), .textOrNull(entry.game), .textOrNull(entry.gameDescription), .textOrNull(entry.cloneOf),
                    .int(entry.isBios ? 1 : 0), .int(entry.hasCHD ? 1 : 0), .int(entry.hasSamples ? 1 : 0), .int(entry.isBadDump ? 1 : 0),
                    .textOrNull(entry.romDumpStatus?.rawValue), .textOrNull(entry.mergeName), .textOrNull(entry.chdNames),
                    .textOrNull(entry.gameYear), .textOrNull(entry.gameManufacturer), .textOrNull(entry.requiredBiosNames), .textOrNull(entry.deviceRefNames),
                    .int(entry.isDisk ? 1 : 0), .textOrNull(entry.foundElsewhereArchiveName), .textOrNull(entry.requiredByGameDescription),
                    .text(entry.name), .textOrNull(entry.path?.path),
                    .int64OrNull(entry.expectedSize), .int64OrNull(entry.actualSize),
                    .textOrNull(entry.expectedCRC), .textOrNull(entry.expectedMD5), .textOrNull(entry.expectedSHA1),
                    .textOrNull(entry.actualCRC), .textOrNull(entry.actualMD5), .textOrNull(entry.actualSHA1),
                ]
            }
            try Self.bindAndExecMany(
                db,
                """
                INSERT INTO audit_entries (
                    system_id, status, game, game_description, clone_of, is_bios, has_chd, has_samples, is_bad_dump,
                    rom_dump_status, merge_name, chd_names, game_year, game_manufacturer, required_bios_names, device_ref_names,
                    is_disk, found_elsewhere_archive_name, required_by_game_description,
                    name, path, expected_size, actual_size,
                    expected_crc, expected_md5, expected_sha1, actual_crc, actual_md5, actual_sha1
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                rowValues
            )
            try Self.exec(db, "COMMIT;")
        } catch {
            try? Self.exec(db, "ROLLBACK;")
            throw error
        }
    }

    /// The persisted report for a system, or `nil` if it's never been
    /// scanned (or was removed). Counts are recomputed from the loaded
    /// entries rather than also stored, so they can never drift apart.
    public func loadReport(systemID: String) throws -> AuditReport? {
        let db = try Self.open(path)
        defer { sqlite3_close(db) }

        guard try Self.rowExists(db, "SELECT 1 FROM scans WHERE system_id = ?;", [.text(systemID)]) else {
            return nil
        }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try Self.prepare(
            db, &statement,
            """
            SELECT status, game, game_description, clone_of, is_bios, has_chd, has_samples, is_bad_dump,
                   rom_dump_status, merge_name, chd_names, game_year, game_manufacturer, required_bios_names, device_ref_names,
                   is_disk, found_elsewhere_archive_name, required_by_game_description,
                   name, path, expected_size, actual_size,
                   expected_crc, expected_md5, expected_sha1, actual_crc, actual_md5, actual_sha1
            FROM audit_entries WHERE system_id = ?;
            """,
            [.text(systemID)]
        )

        var entries: [AuditEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            entries.append(
                AuditEntry(
                    status: AuditStatus(rawValue: Self.columnText(statement, 0) ?? "") ?? .surplus,
                    game: Self.columnText(statement, 1),
                    gameDescription: Self.columnText(statement, 2),
                    cloneOf: Self.columnText(statement, 3),
                    isBios: sqlite3_column_int(statement, 4) != 0,
                    hasCHD: sqlite3_column_int(statement, 5) != 0,
                    hasSamples: sqlite3_column_int(statement, 6) != 0,
                    isBadDump: sqlite3_column_int(statement, 7) != 0,
                    romDumpStatus: Self.columnText(statement, 8).flatMap(RomDumpStatus.init(rawValue:)),
                    mergeName: Self.columnText(statement, 9),
                    chdNames: Self.columnText(statement, 10),
                    gameYear: Self.columnText(statement, 11),
                    gameManufacturer: Self.columnText(statement, 12),
                    requiredBiosNames: Self.columnText(statement, 13),
                    deviceRefNames: Self.columnText(statement, 14),
                    isDisk: sqlite3_column_int(statement, 15) != 0,
                    foundElsewhereArchiveName: Self.columnText(statement, 16),
                    requiredByGameDescription: Self.columnText(statement, 17),
                    name: Self.columnText(statement, 18) ?? "",
                    path: Self.columnText(statement, 19).map(URL.init(fileURLWithPath:)),
                    expectedSize: Self.columnInt64(statement, 20),
                    actualSize: Self.columnInt64(statement, 21),
                    expectedCRC: Self.columnText(statement, 22),
                    expectedMD5: Self.columnText(statement, 23),
                    expectedSHA1: Self.columnText(statement, 24),
                    actualCRC: Self.columnText(statement, 25),
                    actualMD5: Self.columnText(statement, 26),
                    actualSHA1: Self.columnText(statement, 27)
                )
            )
        }

        let correct = entries.filter { $0.status == .correct }.count
        let incorrect = entries.filter { $0.status == .incorrect }.count
        let badDump = entries.filter { $0.status == .badDump }.count
        let missing = entries.filter { $0.status == .missing }.count
        let surplus = entries.filter { $0.status == .surplus }.count
        return AuditReport(entries: entries, correct: correct, incorrect: incorrect, badDump: badDump, missing: missing, surplus: surplus)
    }

    /// The DAT name/version last used to scan a system, and when — shown
    /// without needing to load every entry (e.g. a sidebar badge).
    public func loadScanMeta(systemID: String) throws -> (datName: String?, datVersion: String?, scannedAt: Date)? {
        let db = try Self.open(path)
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try Self.prepare(db, &statement, "SELECT dat_name, dat_version, scanned_at FROM scans WHERE system_id = ?;", [.text(systemID)])
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        let scannedAtString = Self.columnText(statement, 2) ?? ""
        let scannedAt = ISO8601DateFormatter().date(from: scannedAtString) ?? Date(timeIntervalSince1970: 0)
        return (Self.columnText(statement, 0), Self.columnText(statement, 1), scannedAt)
    }

    public func removeSystem(_ systemID: String) throws {
        let db = try Self.open(path)
        defer { sqlite3_close(db) }
        try Self.bindAndExec(db, "DELETE FROM audit_entries WHERE system_id = ?;", [.text(systemID)])
        try Self.bindAndExec(db, "DELETE FROM scans WHERE system_id = ?;", [.text(systemID)])
    }

    // MARK: - Low-level SQLite plumbing

    private enum BindValue {
        case text(String)
        case textOrNull(String?)
        case int(Int32)
        case int64OrNull(Int64?)
    }

    private static func open(_ path: String) throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw AuditReportDatabaseError.cannotOpen(message)
        }
        return db
    }

    private static func exec(_ db: OpaquePointer?, _ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw AuditReportDatabaseError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func bindValues(_ statement: OpaquePointer?, _ values: [BindValue]) {
        for (index, value) in values.enumerated() {
            let column = Int32(index + 1)
            switch value {
            case .text(let string):
                sqlite3_bind_text(statement, column, string, -1, SQLITE_TRANSIENT)
            case .textOrNull(let string):
                if let string {
                    sqlite3_bind_text(statement, column, string, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, column)
                }
            case .int(let value):
                sqlite3_bind_int(statement, column, value)
            case .int64OrNull(let value):
                if let value {
                    sqlite3_bind_int64(statement, column, value)
                } else {
                    sqlite3_bind_null(statement, column)
                }
            }
        }
    }

    private static func prepare(_ db: OpaquePointer?, _ statement: inout OpaquePointer?, _ sql: String, _ values: [BindValue]) throws {
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw AuditReportDatabaseError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        bindValues(statement, values)
    }

    private static func bindAndExec(_ db: OpaquePointer?, _ sql: String, _ values: [BindValue]) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare(db, &statement, sql, values)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AuditReportDatabaseError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Prepares `sql` once and re-executes it for every row in `rowValues`
    /// via bind → step → reset, instead of re-preparing (a real SQL parse/
    /// compile) from scratch per row — for a large collection (tens of
    /// thousands of `audit_entries` rows per scan), re-preparing per row
    /// was a genuine, avoidable hot-path cost inside the save transaction.
    private static func bindAndExecMany(_ db: OpaquePointer?, _ sql: String, _ rowValues: [[BindValue]]) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw AuditReportDatabaseError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        for values in rowValues {
            bindValues(statement, values)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AuditReportDatabaseError.sqlError(String(cString: sqlite3_errmsg(db)))
            }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }

    private static func rowExists(_ db: OpaquePointer?, _ sql: String, _ values: [BindValue]) throws -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare(db, &statement, sql, values)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private static func columnInt64(_ statement: OpaquePointer?, _ index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    private static func migrateIfNeeded(_ db: OpaquePointer?) throws {
        try exec(db, "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);")

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare(db, &statement, "SELECT version FROM schema_version ORDER BY version DESC LIMIT 1;", [])
        let currentVersion: Int32 = sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : 0

        guard currentVersion < currentSchemaVersion else { return }

        try exec(
            db,
            """
            CREATE TABLE IF NOT EXISTS scans (
                system_id TEXT PRIMARY KEY,
                dat_name TEXT,
                dat_version TEXT,
                scanned_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS audit_entries (
                system_id TEXT NOT NULL,
                status TEXT NOT NULL,
                game TEXT,
                game_description TEXT,
                clone_of TEXT,
                is_bios INTEGER NOT NULL,
                has_chd INTEGER NOT NULL,
                has_samples INTEGER NOT NULL,
                is_bad_dump INTEGER NOT NULL,
                rom_dump_status TEXT,
                merge_name TEXT,
                chd_names TEXT,
                game_year TEXT,
                game_manufacturer TEXT,
                required_bios_names TEXT,
                device_ref_names TEXT,
                is_disk INTEGER NOT NULL DEFAULT 0,
                found_elsewhere_archive_name TEXT,
                required_by_game_description TEXT,
                name TEXT NOT NULL,
                path TEXT,
                expected_size INTEGER,
                actual_size INTEGER,
                expected_crc TEXT,
                expected_md5 TEXT,
                expected_sha1 TEXT,
                actual_crc TEXT,
                actual_md5 TEXT,
                actual_sha1 TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_audit_entries_system ON audit_entries(system_id);
            """
        )
        // An existing (pre-version-N) database already has `audit_entries`
        // without these columns — the `CREATE TABLE IF NOT EXISTS` above is
        // a no-op for it, so each has to be added separately. Ignored if it
        // already exists (a fresh database just created the table with
        // every column already present above).
        try? exec(db, "ALTER TABLE audit_entries ADD COLUMN game_description TEXT;")
        try? exec(db, "ALTER TABLE audit_entries ADD COLUMN rom_dump_status TEXT;")
        try? exec(db, "ALTER TABLE audit_entries ADD COLUMN merge_name TEXT;")
        try? exec(db, "ALTER TABLE audit_entries ADD COLUMN chd_names TEXT;")
        try? exec(db, "ALTER TABLE audit_entries ADD COLUMN game_year TEXT;")
        try? exec(db, "ALTER TABLE audit_entries ADD COLUMN game_manufacturer TEXT;")
        try? exec(db, "ALTER TABLE audit_entries ADD COLUMN required_bios_names TEXT;")
        try? exec(db, "ALTER TABLE audit_entries ADD COLUMN device_ref_names TEXT;")
        // Schema v4 (2026-07-30): a `.chd` disk row and a rom row were
        // indistinguishable once persisted and reloaded — every disk entry
        // silently came back as `isDisk: false` (a rom) after a rescan or
        // app relaunch, undoing the "audit ROM and CHD independently, never
        // a combined pass/fail" fix (`AuditEntry.isDisk`, `romOnlyGameCategory`
        // in `LibraryDetailView.swift`, `AuditReport.worstStatus`) the very
        // next time the report was loaded from disk rather than freshly
        // scanned. `DEFAULT 0` above (fresh tables) and here (existing ones)
        // both default to "rom", the old always-true assumption — harmless
        // until the next real Scan re-populates every row with the correct
        // value from a live `DiskAuditor` pass.
        try? exec(db, "ALTER TABLE audit_entries ADD COLUMN is_disk INTEGER NOT NULL DEFAULT 0;")
        // Schema v5 (2026-08-04): exactly the same class of bug as v4 above,
        // for `AuditEntry.foundElsewhereArchiveName`. That field is what
        // `LibraryDetailView`'s folder-scoped views use to tell "a rom this
        // game genuinely owns, inside this folder" apart from "content merely
        // visible over in some other archive" — the latter must never count a
        // game as being present in a "Rom files" folder. Unpersisted, every
        // entry came back with `nil` after an app relaunch (or any time a
        // system's results were loaded from here instead of freshly scanned),
        // so that filter silently stopped filtering and games the user
        // doesn't own reappeared in folder views — jensyleo's own report
        // ("this you had already fixed before"): fixed live, then apparently
        // regressed, because a fresh scan behaved correctly and only the
        // reloaded-from-disk path didn't.
        try? exec(db, "ALTER TABLE audit_entries ADD COLUMN found_elsewhere_archive_name TEXT;")
        // Schema v6 (2026-08-04): same class of bug once more, for
        // `AuditEntry.requiredByGameDescription` — the field a surplus
        // entry uses to say "this leftover file's content is actually
        // required by <game>'s own archive" (e.g. a Split-mode clone's zip
        // still holding a rom the DAT declares only for its parent) instead
        // of a bare, indistinguishable "Unrecognized". Unpersisted, this
        // would go back to reading generically gray after any app relaunch
        // even though a fresh scan reports it correctly — exactly the
        // isDisk/foundElsewhereArchiveName pattern above; adding the ALTER
        // TABLE and the round-trip test up front this time, at the same
        // moment the field itself was introduced.
        try? exec(db, "ALTER TABLE audit_entries ADD COLUMN required_by_game_description TEXT;")
        // Schema v7 (2026-08-04, same day): no new column at all — this
        // bump exists purely to trigger the wipe below. jensyleo's own
        // correction, made right after v6 shipped: a "not needed here"
        // surplus file (`requiredByGameDescription != nil`) must read
        // `.incorrect`, not `.surplus` — "surplus" means genuinely
        // unrecognized, and this content is fully identified. Every row
        // `saveReport` wrote under v6 still has the old (wrong-by-current-
        // rules) `.surplus` status for such a file; only a fresh rescan
        // re-derives it correctly, so the stale rows have to go the same
        // way the v5 rows did below — the unconditional wipe there already
        // covers this bump too, nothing further to add here.
        // Also discard every stored verdict when arriving at v5 (not just add
        // the column): the same 2026-08-04 round of fixes changed what
        // `ROMMatcher` itself concludes — a clone the user doesn't own no
        // longer reports `.foundElsewhere`/`.incorrect` for the roms it
        // shares with its parent, it reports plain `.missing`. Rows written
        // before that are wrong by the current rules, not merely missing a
        // column, so keeping them would show the user the very bug that was
        // just fixed until they happened to rescan that particular system.
        // Only cached scan results are dropped — nothing the user configured
        // lives in this table, and a rescan rebuilds it fully.
        if currentVersion > 0 {
            try? exec(db, "DELETE FROM audit_entries;")
            try? exec(db, "DELETE FROM scans;")
        }
        try bindAndExec(db, "INSERT INTO schema_version (version) VALUES (?);", [.int(currentSchemaVersion)])
    }
}

/// `SQLITE_TRANSIENT` isn't imported as a usable constant by the Swift/Clang
/// bridge (it's the macro value `(sqlite3_destructor_type)-1`) — re-declared
/// here exactly as SQLite's own headers define it, telling SQLite to copy
/// each bound string immediately since Swift's `String` doesn't outlive the
/// call the way a static C string literal would.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
