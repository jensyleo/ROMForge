// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Parses MAME software-list XML (`hash/*.xml` in MAME's own source, or the
/// output of `mame -listsoftware`) — a third DAT dialect alongside Logiqx
/// and `-listxml`, used for cartridge/disk/cassette software on the
/// computer/console/handheld systems MAME emulates, as opposed to arcade
/// `<machine>` entries. Structurally distinct from both: a `<software>` can
/// have multiple `<part>` elements (one per physically separate piece of
/// media), each containing `<dataarea>`/`<diskarea>` around its own
/// `<rom>`/`<disk>` entries, rather than a flat bag of roms.
///
/// Deliberately lenient about `<rom>` entries: unlike `LogiqxDATParser`/
/// `MAMEListXMLParser` (which throw on a rom missing `size`), software
/// lists commonly include `loadflag="continue"/"reload"/"fill"` entries
/// that describe how to reassemble a dump rather than declaring content of
/// their own, often without a `size` or even a `name`. Those are silently
/// skipped rather than treated as malformed, since throwing would make
/// nearly every real software list unparseable.
public enum SoftwareListParser {
    public static func parse(data: Data) throws -> SoftwareListDataset {
        let delegate = SoftwareListXMLParserDelegate()
        let parser = XMLParser(data: data)
        XMLParserHardening.harden(parser)
        parser.delegate = delegate

        guard parser.parse() else {
            throw delegate.thrownError ?? .malformedXML(
                underlying: parser.parserError?.localizedDescription ?? "unknown error"
            )
        }
        if let error = delegate.thrownError {
            throw error
        }
        guard delegate.sawRoot else {
            throw SoftwareListParsingError.missingRootElement
        }
        return SoftwareListDataset(name: delegate.listName, description: delegate.listDescription, software: delegate.software)
    }

    public static func parse(contentsOf url: URL) throws -> SoftwareListDataset {
        try parse(data: try Data(contentsOf: url))
    }
}

private final class SoftwareListXMLParserDelegate: NSObject, XMLParserDelegate {
    fileprivate var sawRoot = false
    fileprivate var listName = ""
    fileprivate var listDescription = ""
    fileprivate var software: [SoftwareListSoftware] = []
    fileprivate var thrownError: SoftwareListParsingError?

    private var currentText = ""

    private var inSoftware = false
    private var softwareName = ""
    private var softwareDescription = ""
    private var softwareCloneOf: String?
    private var parts: [SoftwareListPart] = []

    private var inPart = false
    private var partName = ""
    private var partInterface = ""
    private var partRoms: [DATRom] = []
    private var partDisks: [SoftwareListDisk] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""
        switch elementName {
        case "softwarelist":
            sawRoot = true
            listName = attributeDict["name"] ?? ""
            listDescription = attributeDict["description"] ?? ""
        case "software":
            inSoftware = true
            softwareName = attributeDict["name"] ?? ""
            softwareDescription = ""
            softwareCloneOf = attributeDict["cloneof"]
            parts = []
        case "part":
            guard inSoftware else { break }
            inPart = true
            partName = attributeDict["name"] ?? ""
            partInterface = attributeDict["interface"] ?? ""
            partRoms = []
            partDisks = []
        case "rom":
            guard inPart else { break }
            guard let romName = attributeDict["name"], let sizeString = attributeDict["size"], let size = Int64(sizeString) else {
                break
            }
            partRoms.append(
                DATRom(
                    name: romName, size: size, crc: attributeDict["crc"], md5: attributeDict["md5"], sha1: attributeDict["sha1"],
                    status: RomDumpStatus(rawValue: attributeDict["status"] ?? "good") ?? .good
                )
            )
        case "disk":
            guard inPart, let diskName = attributeDict["name"] else { break }
            partDisks.append(
                SoftwareListDisk(
                    name: diskName, sha1: attributeDict["sha1"],
                    status: RomDumpStatus(rawValue: attributeDict["status"] ?? "good") ?? .good
                )
            )
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
        case "description" where inSoftware && !inPart:
            softwareDescription = text
        case "part":
            inPart = false
            parts.append(SoftwareListPart(name: partName, interface: partInterface, roms: partRoms, disks: partDisks))
        case "software":
            inSoftware = false
            software.append(
                SoftwareListSoftware(name: softwareName, description: softwareDescription, cloneOf: softwareCloneOf, parts: parts)
            )
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
