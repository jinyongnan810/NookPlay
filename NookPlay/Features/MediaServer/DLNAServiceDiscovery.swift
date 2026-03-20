//
//  DLNAServiceDiscovery.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Darwin
import Foundation
import Network

/// The multicast host used by SSDP discovery.
private let ssdpDiscoveryHost = NWEndpoint.Host("239.255.255.250")
/// The multicast port used by SSDP discovery.
private let ssdpDiscoveryPort = NWEndpoint.Port(integerLiteral: 1900)

/// A discovered DLNA or UPnP media server announced through SSDP.
struct DLNAMediaServer: Identifiable, Hashable, Sendable {
    /// The unique service name reported by SSDP.
    let usn: String
    /// The advertised search target that matched discovery.
    let searchTarget: String
    /// The description document location for the server.
    let location: URL
    /// The raw server header, when available.
    let serverHeader: String?
    /// The device's friendly name, when available from the description document.
    let friendlyName: String?
    /// The device's manufacturer, when available from the description document.
    let manufacturer: String?
    /// The device's model name, when available from the description document.
    let modelName: String?

    /// A stable identity for list rendering and deduping.
    var id: String {
        usn
    }
}

/// Performs SSDP discovery for DLNA-compatible media servers on the local network.
actor DLNAServiceDiscovery {
    /// Scans the local network for DLNA/UPnP media servers.
    ///
    /// - Parameter timeout: The time window during which discovery responses are collected.
    /// - Returns: A sorted list of discovered media servers.
    func discover(timeout: TimeInterval = 3) async throws -> [DLNAMediaServer] {
        let operation = SSDPDiscoveryOperation(timeout: timeout)
        let discoveredResponses = try await operation.start()

        var mediaServersByUSN: [String: DLNAMediaServer] = [:]

        for response in discoveredResponses.values {
            guard let usn = response.headers["usn"],
                  let searchTarget = response.headers["st"],
                  let locationValue = response.headers["location"],
                  let location = URL(string: locationValue)
            else {
                continue
            }

            let description = await fetchDeviceDescription(from: location)
            let server = DLNAMediaServer(
                usn: usn,
                searchTarget: searchTarget,
                location: location,
                serverHeader: response.headers["server"],
                friendlyName: description?.friendlyName,
                manufacturer: description?.manufacturer,
                modelName: description?.modelName
            )
            mediaServersByUSN[usn] = server
        }

        return mediaServersByUSN.values.sorted {
            let leftName = $0.friendlyName ?? $0.modelName ?? $0.usn
            let rightName = $1.friendlyName ?? $1.modelName ?? $1.usn
            return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
        }
    }

    /// Fetches and parses a UPnP device description document.
    ///
    /// - Parameter url: The description URL reported by SSDP.
    /// - Returns: Parsed display metadata, or `nil` if loading/parsing fails.
    private func fetchDeviceDescription(from url: URL) async -> DeviceDescription? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return await MainActor.run {
                DeviceDescriptionParser.parse(data: data)
            }
        } catch {
            return nil
        }
    }
}

// MARK: - SSDPDiscoveryOperation

/// A single SSDP scan operation backed by a plain UDP socket.
private final class SSDPDiscoveryOperation {
    /// The duration to listen for SSDP responses after sending the search request.
    private let timeout: TimeInterval

    /// Creates a discovery operation with a fixed listen timeout.
    ///
    /// - Parameter timeout: The number of seconds to collect responses.
    nonisolated init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    /// Starts the SSDP scan and waits for completion.
    ///
    /// - Returns: A dictionary of deduped SSDP responses.
    func start() async throws -> [String: SSDPDiscoveryResponse] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let responses = try self.performScan()
                    continuation.resume(returning: responses)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Performs the socket-based SSDP scan synchronously.
    ///
    /// - Returns: A dictionary of deduped SSDP responses.
    private func performScan() throws -> [String: SSDPDiscoveryResponse] {
        let socketFileDescriptor = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFileDescriptor >= 0 else {
            throw SSDPDiscoveryError.socketCreationFailed(errno)
        }

        defer {
            Darwin.close(socketFileDescriptor)
        }

        var reuseAddress: Int32 = 1
        setsockopt(
            socketFileDescriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var localAddress = sockaddr_in()
        localAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        localAddress.sin_family = sa_family_t(AF_INET)
        localAddress.sin_port = in_port_t(0).bigEndian
        localAddress.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &localAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addressPointer in
                Darwin.bind(
                    socketFileDescriptor,
                    addressPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }

        guard bindResult == 0 else {
            throw SSDPDiscoveryError.bindFailed(errno)
        }

        try sendDiscoveryRequest(using: socketFileDescriptor)
        return try receiveDiscoveryResponses(using: socketFileDescriptor)
    }

    /// Sends the standard SSDP M-SEARCH payload for media-server discovery.
    ///
    /// - Parameter socketFileDescriptor: The socket used for sending and receiving.
    private func sendDiscoveryRequest(using socketFileDescriptor: Int32) throws {
        let payload = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 2\r
        ST: urn:schemas-upnp-org:device:MediaServer:1\r
        \r
        """

        guard let payloadData = payload.data(using: .utf8) else {
            throw SSDPDiscoveryError.invalidPayload
        }

        var destinationAddress = sockaddr_in()
        destinationAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destinationAddress.sin_family = sa_family_t(AF_INET)
        destinationAddress.sin_port = UInt16(ssdpDiscoveryPort.rawValue).bigEndian

        let hostString = "239.255.255.250"
        let presentationConversion = hostString.withCString { hostCString in
            inet_pton(AF_INET, hostCString, &destinationAddress.sin_addr)
        }
        guard presentationConversion == 1 else {
            throw SSDPDiscoveryError.invalidDestinationAddress
        }

        let bytesSent = payloadData.withUnsafeBytes { payloadPointer in
            withUnsafePointer(to: &destinationAddress) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    Darwin.sendto(
                        socketFileDescriptor,
                        payloadPointer.baseAddress,
                        payloadData.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }

        guard bytesSent >= 0 else {
            throw SSDPDiscoveryError.sendFailed(errno)
        }
    }

    /// Receives SSDP responses from arbitrary local-network devices until timeout.
    ///
    /// - Parameter socketFileDescriptor: The socket used for sending and receiving.
    /// - Returns: A dictionary of deduped SSDP responses.
    private func receiveDiscoveryResponses(using socketFileDescriptor: Int32) throws -> [String: SSDPDiscoveryResponse] {
        var responsesByUSN: [String: SSDPDiscoveryResponse] = [:]
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let remainingInterval = max(deadline.timeIntervalSinceNow, 0.1)
            var receiveTimeout = timeval(
                tv_sec: Int(remainingInterval.rounded(.down)),
                tv_usec: Int32((remainingInterval.truncatingRemainder(dividingBy: 1)) * 1_000_000)
            )

            let timeoutResult = setsockopt(
                socketFileDescriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &receiveTimeout,
                socklen_t(MemoryLayout<timeval>.size)
            )
            guard timeoutResult == 0 else {
                throw SSDPDiscoveryError.receiveConfigurationFailed(errno)
            }

            var buffer = [UInt8](repeating: 0, count: 65535)
            let bufferLength = buffer.count
            var sourceAddress = sockaddr_storage()
            var sourceAddressLength = socklen_t(MemoryLayout<sockaddr_storage>.size)

            let bytesRead = buffer.withUnsafeMutableBytes { bufferPointer in
                withUnsafeMutablePointer(to: &sourceAddress) { addressPointer in
                    addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                        Darwin.recvfrom(
                            socketFileDescriptor,
                            bufferPointer.baseAddress,
                            bufferLength,
                            0,
                            socketAddress,
                            &sourceAddressLength
                        )
                    }
                }
            }

            if bytesRead > 0 {
                let responseData = Data(buffer.prefix(bytesRead))
                if let response = SSDPDiscoveryResponseParser.parse(data: responseData),
                   let usn = response.headers["usn"]
                {
                    responsesByUSN[usn] = response
                }
                continue
            }

            if bytesRead == 0 {
                break
            }

            if errno == EWOULDBLOCK || errno == EAGAIN {
                break
            }

            if errno == EINTR {
                continue
            }

            throw SSDPDiscoveryError.receiveFailed(errno)
        }

        return responsesByUSN
    }
}

/// Errors produced while attempting SSDP discovery.
private enum SSDPDiscoveryError: LocalizedError {
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case invalidPayload
    case invalidDestinationAddress
    case sendFailed(Int32)
    case receiveConfigurationFailed(Int32)
    case receiveFailed(Int32)

    var errorDescription: String? {
        switch self {
        case let .socketCreationFailed(code):
            "NookPlay couldn’t create a discovery socket. (\(code))"
        case let .bindFailed(code):
            "NookPlay couldn’t bind the SSDP discovery socket. (\(code))"
        case .invalidPayload:
            "NookPlay couldn’t prepare the SSDP discovery request."
        case .invalidDestinationAddress:
            "NookPlay couldn’t prepare the SSDP multicast destination."
        case let .sendFailed(code):
            "NookPlay couldn’t send the SSDP discovery request. (\(code))"
        case let .receiveConfigurationFailed(code):
            "NookPlay couldn’t configure SSDP response listening. (\(code))"
        case let .receiveFailed(code):
            "NookPlay couldn’t read SSDP responses. (\(code))"
        }
    }
}

// MARK: - SSDP Parsing

/// A parsed SSDP response with normalized header keys.
private struct SSDPDiscoveryResponse: Sendable {
    /// The normalized header map for the SSDP response.
    let headers: [String: String]
}

/// Parses raw SSDP response datagrams into header dictionaries.
private enum SSDPDiscoveryResponseParser {
    /// Parses a UDP datagram as an SSDP response.
    ///
    /// - Parameter data: The received datagram data.
    /// - Returns: A parsed SSDP response, or `nil` if parsing fails.
    static func parse(data: Data) -> SSDPDiscoveryResponse? {
        guard let rawString = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = rawString
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let firstLine = lines.first,
              firstLine.localizedCaseInsensitiveContains("200 OK")
        else {
            return nil
        }

        var headers: [String: String] = [:]

        for line in lines.dropFirst() {
            let components = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard components.count == 2 else {
                continue
            }

            let name = components[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        return SSDPDiscoveryResponse(headers: headers)
    }
}

// MARK: - Device Description Parsing

/// Lightweight display metadata extracted from a UPnP device description document.
private struct DeviceDescription: Sendable {
    let friendlyName: String?
    let manufacturer: String?
    let modelName: String?
}

/// Parses UPnP XML device descriptions for a few display fields.
private enum DeviceDescriptionParser {
    /// Parses a UPnP device description document.
    ///
    /// - Parameter data: The XML response body.
    /// - Returns: Parsed display metadata, or `nil` if parsing fails.
    static func parse(data: Data) -> DeviceDescription? {
        let parserDelegate = DeviceDescriptionXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        parser.shouldProcessNamespaces = true

        guard parser.parse() else {
            return nil
        }

        return parserDelegate.deviceDescription
    }
}

/// An `XMLParserDelegate` that extracts display metadata from UPnP device XML.
private final class DeviceDescriptionXMLParserDelegate: NSObject, XMLParserDelegate {
    /// The parsed device description after the document finishes.
    private(set) var deviceDescription: DeviceDescription?

    /// The current element name being parsed.
    private var currentElementName: String?
    /// The active character buffer for the current element.
    private var currentValue = ""
    /// The first friendly name encountered in the device tree.
    private var friendlyName: String?
    /// The first manufacturer encountered in the device tree.
    private var manufacturer: String?
    /// The first model name encountered in the device tree.
    private var modelName: String?

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes _: [String: String] = [:]
    ) {
        currentElementName = elementName
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
        let trimmedValue = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "friendlyName" where friendlyName == nil && !trimmedValue.isEmpty:
            friendlyName = trimmedValue
        case "manufacturer" where manufacturer == nil && !trimmedValue.isEmpty:
            manufacturer = trimmedValue
        case "modelName" where modelName == nil && !trimmedValue.isEmpty:
            modelName = trimmedValue
        default:
            break
        }

        currentElementName = nil
        currentValue = ""
    }

    func parserDidEndDocument(_: XMLParser) {
        deviceDescription = DeviceDescription(
            friendlyName: friendlyName,
            manufacturer: manufacturer,
            modelName: modelName
        )
    }
}
