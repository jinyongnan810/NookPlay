//
//  DLNAContentDirectoryBrowser.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

/// Fetches folder contents from a DLNA ContentDirectory service.
///
/// SSDP discovery only tells the app that a server exists and where its service endpoints live.
/// The actual folder and file hierarchy is exposed through SOAP requests against the server's
/// ContentDirectory control URL, so this actor owns that network boundary and its XML parsing.
actor DLNAContentDirectoryBrowser {
    /// Loads the direct children for a given DLNA container.
    ///
    /// - Parameters:
    ///   - server: The discovered server whose ContentDirectory should be queried.
    ///   - containerID: The DLNA object identifier to browse. `0` is the standard root container.
    /// - Returns: The parsed folder contents.
    func browse(server: DLNAMediaServer, containerID: String = "0") async throws -> DLNABrowseResponse {
        guard let contentDirectory = server.contentDirectory else {
            throw DLNAContentDirectoryBrowserError.contentDirectoryUnavailable
        }

        var request = URLRequest(url: contentDirectory.controlURL)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "\"\(contentDirectory.serviceType)#Browse\"",
            forHTTPHeaderField: "SOAPACTION"
        )
        request.httpBody = await MainActor.run {
            BrowseRequestBodyFactory.makeBrowseDirectChildrenBody(
                objectID: containerID,
                serviceType: contentDirectory.serviceType
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 12
        configuration.waitsForConnectivity = false

        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DLNAContentDirectoryBrowserError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let soapFault = await MainActor.run {
                SOAPFaultParser.parse(data: data)
            }

            if let soapFault {
                throw DLNAContentDirectoryBrowserError.soapFault(soapFault)
            }

            throw DLNAContentDirectoryBrowserError.httpFailure(statusCode: httpResponse.statusCode)
        }

        let soapResponse = try await MainActor.run {
            try SOAPBrowseResponseParser.parse(data: data)
        }
        let didlData = Data(soapResponse.resultXML.utf8)
        let items = try await MainActor.run {
            try DIDLLiteBrowseParser.parse(data: didlData)
        }

        return DLNABrowseResponse(
            containerID: containerID,
            items: items,
            totalMatches: soapResponse.totalMatches
        )
    }
}

// MARK: - Errors

private enum DLNAContentDirectoryBrowserError: LocalizedError {
    case contentDirectoryUnavailable
    case invalidResponse
    case httpFailure(statusCode: Int)
    case soapFault(String)
    case invalidSOAPResponse
    case invalidBrowsePayload

    var errorDescription: String? {
        switch self {
        case .contentDirectoryUnavailable:
            "This server does not expose a browseable media library."
        case .invalidResponse:
            "The media server returned an invalid response."
        case let .httpFailure(statusCode):
            "The media server returned HTTP \(statusCode)."
        case let .soapFault(message):
            message
        case .invalidSOAPResponse:
            "The media server returned an unreadable browse response."
        case .invalidBrowsePayload:
            "The media server returned an unreadable media listing."
        }
    }
}

// MARK: - SOAP request building

private enum BrowseRequestBodyFactory {
    static func makeBrowseDirectChildrenBody(objectID: String, serviceType: String) -> Data {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>
                <u:Browse xmlns:u="\(serviceType)">
                    <ObjectID>\(objectID.xmlEscaped)</ObjectID>
                    <BrowseFlag>BrowseDirectChildren</BrowseFlag>
                    <Filter>*</Filter>
                    <StartingIndex>0</StartingIndex>
                    <RequestedCount>0</RequestedCount>
                    <SortCriteria></SortCriteria>
                </u:Browse>
            </s:Body>
        </s:Envelope>
        """

        return Data(body.utf8)
    }
}

private extension String {
    /// Escapes XML-reserved characters before embedding user or server values in SOAP bodies.
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - SOAP response parsing

private struct SOAPBrowsePayload: Sendable {
    let resultXML: String
    let totalMatches: Int?
}

private enum SOAPBrowseResponseParser {
    static func parse(data: Data) throws -> SOAPBrowsePayload {
        let delegate = SOAPBrowseResponseParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false

        guard parser.parse(), let payload = delegate.payload else {
            throw DLNAContentDirectoryBrowserError.invalidSOAPResponse
        }

        return payload
    }
}

private final class SOAPBrowseResponseParserDelegate: NSObject, XMLParserDelegate {
    private(set) var payload: SOAPBrowsePayload?

    private var currentValue = ""
    private var resultXML: String?
    private var totalMatches: Int?

    func parser(
        _: XMLParser,
        didStartElement _: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes _: [String: String] = [:]
    ) {
        currentValue = ""
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName.localName {
        case "Result" where !value.isEmpty:
            resultXML = value
        case "TotalMatches":
            totalMatches = Int(value)
        default:
            break
        }

        currentValue = ""
    }

    func parserDidEndDocument(_: XMLParser) {
        guard let resultXML else {
            return
        }

        payload = SOAPBrowsePayload(resultXML: resultXML, totalMatches: totalMatches)
    }
}

private enum SOAPFaultParser {
    static func parse(data: Data) -> String? {
        let delegate = SOAPFaultParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return delegate.faultString
    }
}

private final class SOAPFaultParserDelegate: NSObject, XMLParserDelegate {
    private(set) var faultString: String?

    private var currentValue = ""

    func parser(
        _: XMLParser,
        didStartElement _: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes _: [String: String] = [:]
    ) {
        currentValue = ""
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName.localName == "faultstring", !value.isEmpty {
            faultString = value
        }
        currentValue = ""
    }
}

// MARK: - DIDL-Lite parsing

private enum DIDLLiteBrowseParser {
    static func parse(data: Data) throws -> [DLNABrowseItem] {
        // An empty `<Result />` is a valid browse response for an empty folder. Return an empty list
        // rather than failing the whole browse flow.
        guard !data.isEmpty else {
            return []
        }

        let delegate = DIDLLiteBrowseParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false

        guard parser.parse() else {
            throw DLNAContentDirectoryBrowserError.invalidBrowsePayload
        }

        return delegate.items
    }
}

private final class DIDLLiteBrowseParserDelegate: NSObject, XMLParserDelegate {
    private struct ResourceCandidate {
        let url: URL
        let protocolInfo: String?
        let mimeType: String?
    }

    private struct CurrentEntry {
        let kind: DLNABrowseItem.Kind
        let objectID: String
        let parentID: String?
        let childCount: Int?

        var title: String?
        var creator: String?
        var mediaClass: String?
        var resources: [ResourceCandidate] = []
        var activeResourceProtocolInfo: String?
    }

    private(set) var items: [DLNABrowseItem] = []

    private var currentValue = ""
    private var currentEntry: CurrentEntry?

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentValue = ""

        switch elementName.localName {
        case "container":
            currentEntry = CurrentEntry(
                kind: .container,
                objectID: attributeDict["id"] ?? UUID().uuidString,
                parentID: attributeDict["parentID"],
                childCount: attributeDict["childCount"].flatMap(Int.init)
            )

        case "item":
            currentEntry = CurrentEntry(
                kind: .item,
                objectID: attributeDict["id"] ?? UUID().uuidString,
                parentID: attributeDict["parentID"],
                childCount: nil
            )

        case "res":
            currentEntry?.activeResourceProtocolInfo = attributeDict["protocolInfo"]

        default:
            break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        let localName = elementName.localName
        let trimmedValue = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch localName {
        case "title":
            if currentEntry?.title == nil, !trimmedValue.isEmpty {
                currentEntry?.title = trimmedValue
            }

        case "creator":
            if currentEntry?.creator == nil, !trimmedValue.isEmpty {
                currentEntry?.creator = trimmedValue
            }

        case "class":
            if currentEntry?.mediaClass == nil, !trimmedValue.isEmpty {
                currentEntry?.mediaClass = trimmedValue
            }

        case "res":
            if let candidate = makeResourceCandidate(from: trimmedValue, entry: currentEntry) {
                currentEntry?.resources.append(candidate)
            }
            currentEntry?.activeResourceProtocolInfo = nil

        case "container", "item":
            finalizeCurrentEntry()

        default:
            break
        }

        currentValue = ""
    }

    /// Chooses the best resource URL from the entry's resource list.
    ///
    /// DLNA items often expose several URLs for the same file. Some are poster images, some are
    /// transcoded streams, and some are direct media files. The scorer prefers HTTP(S) video
    /// resources first because those are the most likely to work with AVPlayer in the current app.
    private func selectBestResource(from resources: [ResourceCandidate]) -> ResourceCandidate? {
        resources.max { lhs, rhs in
            resourceScore(lhs) < resourceScore(rhs)
        }
    }

    private func resourceScore(_ candidate: ResourceCandidate) -> Int {
        var score = 0

        if ["http", "https"].contains(candidate.url.scheme?.lowercased() ?? "") {
            score += 2
        }

        let lowerProtocolInfo = candidate.protocolInfo?.lowercased() ?? ""
        let lowerMimeType = candidate.mimeType?.lowercased() ?? ""
        if lowerProtocolInfo.contains("video") || lowerMimeType.contains("video") {
            score += 4
        }

        if lowerMimeType.contains("application/vnd.apple.mpegurl") || candidate.url.pathExtension.lowercased() == "m3u8" {
            score += 1
        }

        return score
    }

    private func makeResourceCandidate(from rawURL: String, entry: CurrentEntry?) -> ResourceCandidate? {
        guard
            let entry,
            !rawURL.isEmpty,
            let url = URL(string: rawURL)
        else {
            return nil
        }

        let mimeType = entry.activeResourceProtocolInfo?
            .split(separator: ":")
            .dropFirst(2)
            .first
            .map(String.init)

        return ResourceCandidate(
            url: url,
            protocolInfo: entry.activeResourceProtocolInfo,
            mimeType: mimeType
        )
    }

    private func finalizeCurrentEntry() {
        guard let currentEntry else {
            return
        }

        let selectedResource = selectBestResource(from: currentEntry.resources)
        let mediaClass = currentEntry.mediaClass?.replacingOccurrences(of: ".", with: " ")

        let subtitle: String? = {
            let values: [String] = [currentEntry.creator, mediaClass]
                .compactMap { value in
                    guard let value, !value.isEmpty else {
                        return nil
                    }
                    return value
                }

            return values.isEmpty ? nil : values.joined(separator: " • ")
        }()

        items.append(
            DLNABrowseItem(
                id: "\(currentEntry.kind.rawValue)::\(currentEntry.objectID)",
                objectID: currentEntry.objectID,
                parentID: currentEntry.parentID,
                title: currentEntry.title ?? "Untitled",
                subtitle: subtitle,
                kind: currentEntry.kind,
                childCount: currentEntry.childCount,
                streamURL: selectedResource?.url,
                mimeType: selectedResource?.mimeType,
                protocolInfo: selectedResource?.protocolInfo
            )
        )

        self.currentEntry = nil
    }
}

private extension String {
    /// Returns the local XML element name without any namespace prefix.
    var localName: String {
        components(separatedBy: ":").last ?? self
    }
}
