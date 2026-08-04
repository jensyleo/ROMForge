// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Parses the output of `mame -listxml`: a `<mame>` root of `<machine>`
/// elements, richer than the generic Logiqx schema (BIOS sets, device
/// references, CHD disks, and `romof`/`cloneof` parent-clone relationships).
public enum MAMEListXMLParser {
    /// - Parameter onProgress: reports (machinesParsed, totalMachines) —
    ///   a real `-listxml` dump for the full MAME driver set is hundreds of
    ///   MB of XML and can itself take longer to parse than scanning or
    ///   hashing a modest ROM collection, with `XMLParser`'s SAX callbacks
    ///   otherwise giving no visibility into how far along it is. The total
    ///   is a cheap single-pass byte count of `<machine ` occurrences done
    ///   up front, before the real (much slower, allocation-heavy) parse.
    /// - Parameter onCountingStarted: fired right before the up-front byte
    ///   count begins — for a real full-driver-set dump (hundreds of MB),
    ///   that single-pass scan is cheap relative to the real parse but
    ///   still isn't instant, and without a distinct signal for "counting"
    ///   vs. "parsing with a known total", a caller's UI had no way to
    ///   label this brief phase as anything but a generic, unexplained wait.
    /// - Parameter onCountingProgress: reports (bytesScanned, totalBytes)
    ///   during the up-front counting pass itself — see
    ///   `countMachineElements`'s doc comment for why that pass needed its
    ///   own progress signal rather than staying a bare spinner.
    public static func parse(data: Data, onCountingStarted: (@Sendable () -> Void)? = nil, onCountingProgress: (@Sendable (Int, Int) -> Void)? = nil, onProgress: (@Sendable (Int, Int) -> Void)? = nil) throws -> MAMEDataset {
        let delegate = MAMEXMLParserDelegate()
        if let onProgress {
            onCountingStarted?()
            let total = countMachineElements(in: data, onByteProgress: onCountingProgress)
            // Reported immediately (0 of total) rather than waiting for the
            // first throttled callback — otherwise the caller has no known
            // total (and so no determinate bar) for however long it takes
            // to reach the first 100 machines, which for a big DAT was a
            // visible "starts as a bare spinner, then a bar pops in" glitch.
            onProgress(0, total)
            delegate.onProgress = { count in onProgress(count, total) }
        }
        let parser = XMLParser(data: data)
        // XXE hardening: never fetch/resolve an external DTD or entity a
        // malicious/corrupt DAT might declare.
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate

        guard parser.parse() else {
            // A user-initiated cancel aborts the parser the same way a real
            // parse error would (`XMLParser` has no other way to stop
            // early) — checked first so it's reported as an actual
            // cancellation, not folded into a generic/malformed-XML error
            // `DATLoader` would otherwise treat as "try the next format".
            if delegate.wasCancelled {
                throw CancellationError()
            }
            throw delegate.thrownError ?? .malformedXML(
                underlying: parser.parserError?.localizedDescription ?? "unknown error"
            )
        }
        if let error = delegate.thrownError {
            throw error
        }
        guard delegate.sawRoot else {
            throw MAMEParsingError.missingRootElement
        }
        onProgress?(delegate.machines.count, delegate.machines.count)
        return MAMEDataset(machines: delegate.machines)
    }

    public static func parse(contentsOf url: URL, onCountingStarted: (@Sendable () -> Void)? = nil, onCountingProgress: (@Sendable (Int, Int) -> Void)? = nil, onProgress: (@Sendable (Int, Int) -> Void)? = nil) throws -> MAMEDataset {
        try parse(data: try Data(contentsOf: url), onCountingStarted: onCountingStarted, onCountingProgress: onCountingProgress, onProgress: onProgress)
    }

    /// A plain byte-level scan for the literal `<machine ` marker — far
    /// cheaper than a real XML parse (no allocation, no element/attribute
    /// bookkeeping), so doing this once up front to learn a total is worth
    /// it even for a very large file.
    ///
    /// - Parameter onByteProgress: reports (bytesScanned, totalBytes) every
    ///   ~8MB — for a real full-driver-set dump (hundreds of MB) this pass
    ///   alone can take a few real seconds, and until this was added the
    ///   caller had no total to show a determinate bar for it (only a bare
    ///   spinner labeled "Counting machines…", indistinguishable from a
    ///   stall for however long the scan actually took).
    private static func countMachineElements(in data: Data, onByteProgress: (@Sendable (Int, Int) -> Void)? = nil) -> Int {
        let pattern = Array("<machine ".utf8)
        var count = 0
        let reportInterval = 8_000_000
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            let n = bytes.count
            let m = pattern.count
            guard n >= m else { return }
            var i = 0
            var nextReportAt = reportInterval
            while i <= n - m {
                if bytes[i] == pattern[0] {
                    var matched = true
                    var j = 1
                    while j < m {
                        if bytes[i + j] != pattern[j] { matched = false; break }
                        j += 1
                    }
                    if matched {
                        count += 1
                        i += m
                        continue
                    }
                }
                i += 1
                if i >= nextReportAt {
                    onByteProgress?(i, n)
                    nextReportAt += reportInterval
                }
            }
        }
        return count
    }
}

private final class MAMEXMLParserDelegate: NSObject, XMLParserDelegate {
    fileprivate var sawRoot = false
    fileprivate var machines: [MAMEMachine] = []
    fileprivate var thrownError: MAMEParsingError?
    /// Set by `MAMEListXMLParser.parse` only when a caller asked for
    /// progress — throttled to roughly every 100 machines (plus always the
    /// last one) so a huge driver set doesn't flood the caller with a
    /// callback per machine.
    fileprivate var onProgress: ((Int) -> Void)?
    /// Set (and the parser aborted) the moment a cooperative-cancellation
    /// check finds the enclosing `Task` cancelled — checked at the same
    /// throttle point as `onProgress`, so a cancel is noticed within ~100
    /// machines rather than only after the whole (hundreds-of-MB) document
    /// finishes parsing.
    fileprivate var wasCancelled = false
    private var machinesSeen = 0

    private var currentText = ""

    private var inMachine = false
    private var name = ""
    private var machineDescription = ""
    private var year = ""
    private var manufacturer = ""
    private var cloneOf: String?
    private var romOf: String?
    private var isBios = false
    private var isDevice = false
    private var biosSets: [MAMEBiosSet] = []
    private var roms: [DATRom] = []
    private var disks: [MAMEDisk] = []
    private var deviceRefs: [String] = []
    private var hasSamples = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""
        switch elementName {
        case "mame":
            sawRoot = true
        case "machine":
            inMachine = true
            name = attributeDict["name"] ?? ""
            machineDescription = ""
            year = ""
            manufacturer = ""
            cloneOf = attributeDict["cloneof"]
            romOf = attributeDict["romof"]
            isBios = attributeDict["isbios"] == "yes"
            isDevice = attributeDict["isdevice"] == "yes"
            biosSets = []
            roms = []
            disks = []
            deviceRefs = []
            hasSamples = false
        case "biosset":
            guard inMachine, let biosName = attributeDict["name"] else { break }
            biosSets.append(MAMEBiosSet(name: biosName, description: attributeDict["description"] ?? ""))
        case "rom":
            guard inMachine, thrownError == nil else { break }
            guard let romName = attributeDict["name"] else {
                thrownError = .missingRomAttribute(machine: name, attribute: "name")
                break
            }
            guard let sizeString = attributeDict["size"], let size = Int64(sizeString) else {
                thrownError = .missingRomAttribute(machine: name, attribute: "size")
                break
            }
            roms.append(
                DATRom(
                    name: romName, size: size, crc: attributeDict["crc"], md5: attributeDict["md5"], sha1: attributeDict["sha1"],
                    status: RomDumpStatus(rawValue: attributeDict["status"] ?? "good") ?? .good,
                    mergeName: attributeDict["merge"]
                )
            )
        case "disk":
            guard inMachine, let diskName = attributeDict["name"] else { break }
            disks.append(MAMEDisk(name: diskName, sha1: attributeDict["sha1"]))
        case "device_ref":
            guard inMachine, let refName = attributeDict["name"] else { break }
            deviceRefs.append(refName)
        case "sample":
            guard inMachine else { break }
            hasSamples = true
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
        case "description" where inMachine:
            machineDescription = text
        case "year" where inMachine:
            year = text
        case "manufacturer" where inMachine:
            manufacturer = text
        case "machine":
            inMachine = false
            machines.append(
                MAMEMachine(
                    name: name,
                    description: machineDescription,
                    year: year,
                    manufacturer: manufacturer,
                    cloneOf: cloneOf,
                    romOf: romOf,
                    isBios: isBios,
                    isDevice: isDevice,
                    biosSets: biosSets,
                    roms: roms,
                    disks: disks,
                    deviceRefs: deviceRefs,
                    hasSamples: hasSamples
                )
            )
            machinesSeen += 1
            // Cancellation checked every machine, not throttled — real bug
            // found live by jensyleo (2026-08-04): the same class of issue
            // fixed throughout `ROMMatcher`/`AuditReporter`/`DiskAuditor`/
            // `DATLoader` — a lock-free `Task.isCancelled` read is
            // negligible next to parsing even one machine's own XML
            // element, so throttling this ever skipped real cancellation
            // opportunities for no actual performance benefit. `onProgress`
            // (a real UI callback) stays throttled to every 100 — that one
            // *does* have a genuine reason to stay cheap.
            if Task.isCancelled {
                wasCancelled = true
                parser.abortParsing()
                return
            }
            if machinesSeen % 100 == 0 {
                onProgress?(machinesSeen)
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
