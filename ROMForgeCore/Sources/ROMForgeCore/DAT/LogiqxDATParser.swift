// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Parses Logiqx/ClrMamePro-style XML DATs (the schema shared by No-Intro, Redump,
/// TOSEC and FBNeo) into a `DATFile`. MAME's richer `-listxml` format (with
/// `biosset`/`device_ref`/`disk`) is handled by a dedicated parser added later.
public enum LogiqxDATParser {
    public static func parse(data: Data) throws -> DATFile {
        let delegate = DATXMLParserDelegate()
        let parser = XMLParser(data: data)
        XMLParserHardening.harden(parser)
        parser.delegate = delegate

        guard parser.parse() else {
            // A wrong-format document (e.g. a MAME `-listxml` dump, whose
            // root is `<mame>` not `<datafile>`) is deliberately aborted at
            // its very first element (see `rootElementRejected` below)
            // rather than falling through the generic XML-error path —
            // reported as a clean "wrong root", not whatever message
            // `abortParsing()`'s own parser error happens to produce.
            if delegate.rootElementRejected {
                throw DATParsingError.missingRootElement
            }
            throw delegate.thrownError ?? .malformedXML(
                underlying: parser.parserError?.localizedDescription ?? "unknown error"
            )
        }
        if let error = delegate.thrownError {
            throw error
        }
        guard delegate.sawRoot else {
            throw DATParsingError.missingRootElement
        }
        guard let header = delegate.header else {
            throw DATParsingError.missingHeader
        }
        // No-Intro's own DAT-o-MATIC schema (confirmed 2026-09-29 against a
        // real, freshly-generated NES DAT — `xsi:schemaLocation
        // =".../schema_nointro_datfile_v4.xsd"`) declares parent/clone via a
        // numeric `cloneofid="<id>"` referencing another `<game>`'s own
        // numeric `id="<id>"`, not the classic Logiqx/MAME `cloneof="<name>"`
        // by name. Both attributes can't be resolved from a single element
        // in isolation — a clone can (and does, in the real file) appear
        // before its own parent — so this is a second pass over the fully
        // parsed `games`, run only for entries the by-name attribute left
        // unresolved. Every other DAT flavor (classic Logiqx, MAME
        // `-listxml`) has no `cloneofid`/numeric `id` at all, so this is a
        // no-op for them.
        var games = delegate.games
        for (index, cloneOfId) in delegate.pendingCloneOfIdResolutions {
            guard let parentName = delegate.idToName[cloneOfId], parentName != games[index].name else { continue }
            let game = games[index]
            games[index] = DATGame(
                name: game.name,
                description: game.description,
                cloneOf: parentName,
                romOf: game.romOf,
                roms: game.roms,
                hasSamples: game.hasSamples,
                category: game.category
            )
        }
        return DATFile(header: header, games: games, hasClones: games.contains { $0.cloneOf != nil })
    }

    public static func parse(contentsOf url: URL) throws -> DATFile {
        try parse(data: try Data(contentsOf: url))
    }
}

private final class DATXMLParserDelegate: NSObject, XMLParserDelegate {
    fileprivate var sawRoot = false
    fileprivate var header: DATHeader?
    fileprivate var games: [DATGame] = []
    fileprivate var thrownError: DATParsingError?
    /// Set (and the parse aborted) the moment the document's very first
    /// element turns out not to be `<datafile>` — a MAME `-listxml` dump
    /// (root `<mame>`) would otherwise be processed start to finish by this
    /// parser (its `<machine>` elements masquerading as valid Logiqx
    /// `<game>`/`<machine>` entries, since this parser deliberately accepts
    /// either tag name) before failing only at the very end on `sawRoot`
    /// — for a real ~320MB MAME DAT, that's the entire file parsed and
    /// thrown away, silently, before `DATLoader` even tries the parser
    /// that actually handles it. Aborting on the first element instead
    /// makes a wrong-format DAT fail near-instantly.
    fileprivate var rootElementRejected = false
    private var isFirstElement = true

    private var currentText = ""
    private var inHeader = false
    private var headerName = ""
    private var headerDescription = ""
    private var headerVersion = ""
    private var headerAuthor = ""

    private var inGame = false
    private var currentGameName = ""
    private var currentGameDescription = ""
    private var currentGameCloneOf: String?
    private var currentGameRomOf: String?
    private var currentGameId: String?
    private var currentGameCloneOfId: String?
    private var currentGameRoms: [DATRom] = []
    private var currentGameDisks: [DATDisk] = []
    private var currentGameHasSamples = false
    private var currentGameCategory: String?

    /// `id="<n>"` → that game's own `name`, built up as each `<game>`
    /// closes — used to resolve a No-Intro-style `cloneofid` after the whole
    /// document has been read (see the numeric-id doc comment on `parse(data:)`).
    fileprivate var idToName: [String: String] = [:]
    /// `(index into `games`, cloneofid)` for every game whose `cloneof`
    /// (by-name) attribute was absent but a numeric `cloneofid` was present —
    /// resolved against `idToName` once the full document is read.
    fileprivate var pendingCloneOfIdResolutions: [(index: Int, cloneOfId: String)] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""
        if isFirstElement {
            isFirstElement = false
            guard elementName == "datafile" else {
                rootElementRejected = true
                parser.abortParsing()
                return
            }
        }
        switch elementName {
        case "datafile":
            sawRoot = true
        case "header":
            inHeader = true
        case "game", "machine":
            inGame = true
            currentGameName = attributeDict["name"] ?? ""
            currentGameDescription = ""
            currentGameCloneOf = attributeDict["cloneof"]
            currentGameRomOf = attributeDict["romof"]
            currentGameId = attributeDict["id"]
            currentGameCloneOfId = attributeDict["cloneofid"]
            currentGameRoms = []
            currentGameDisks = []
            currentGameHasSamples = false
            currentGameCategory = nil
        case "rom":
            guard inGame, thrownError == nil else { break }
            guard let name = attributeDict["name"] else {
                thrownError = .missingRomAttribute(game: currentGameName, attribute: "name")
                break
            }
            guard let sizeString = attributeDict["size"], let size = Int64(sizeString) else {
                thrownError = .missingRomAttribute(game: currentGameName, attribute: "size")
                break
            }
            currentGameRoms.append(
                DATRom(
                    name: name,
                    size: size,
                    crc: attributeDict["crc"],
                    md5: attributeDict["md5"],
                    sha1: attributeDict["sha1"],
                    status: RomDumpStatus(rawValue: attributeDict["status"] ?? "good") ?? .good,
                    serial: attributeDict["serial"],
                    sha256: attributeDict["sha256"],
                    header: attributeDict["header"]
                )
            )
        case "disk":
            guard inGame, let diskName = attributeDict["name"] else { break }
            currentGameDisks.append(DATDisk(name: diskName, sha1: attributeDict["sha1"]))
        case "sample":
            guard inGame else { break }
            currentGameHasSamples = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentText = ""
        switch elementName {
        case "name" where inHeader:
            headerName = text
        case "description" where inHeader:
            headerDescription = text
        case "version" where inHeader:
            headerVersion = text
        case "author" where inHeader:
            headerAuthor = text
        case "header":
            inHeader = false
            header = DATHeader(
                name: headerName,
                description: headerDescription,
                version: headerVersion,
                author: headerAuthor
            )
        case "description" where inGame:
            currentGameDescription = text
        case "category" where inGame:
            currentGameCategory = text.isEmpty ? nil : text
        case "game", "machine":
            inGame = false
            games.append(
                DATGame(
                    name: currentGameName,
                    description: currentGameDescription,
                    cloneOf: currentGameCloneOf,
                    romOf: currentGameRomOf,
                    roms: currentGameRoms,
                    disks: currentGameDisks,
                    hasSamples: currentGameHasSamples,
                    category: currentGameCategory
                )
            )
            if let id = currentGameId {
                idToName[id] = currentGameName
            }
            if currentGameCloneOf == nil, let cloneOfId = currentGameCloneOfId {
                pendingCloneOfIdResolutions.append((index: games.count - 1, cloneOfId: cloneOfId))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if thrownError == nil {
            thrownError = .malformedXML(underlying: parseError.localizedDescription)
        }
    }
}
