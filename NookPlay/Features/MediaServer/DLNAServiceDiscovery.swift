//
//  DLNAServiceDiscovery.swift
//  NookPlay
//
//  Investigation-oriented DLNA / UPnP SSDP discovery.
//
//  This version is intentionally more verbose and more tolerant than a
//  "production final" implementation because the current goal is to
//  understand why a server such as Plex is not showing up.
//
//  Main differences from a stricter implementation:
//  1. Any SSDP response with a valid LOCATION becomes a provisional device.
//  2. Failure to fetch / parse the description XML does NOT hide the device.
//  3. Extra diagnostics are captured so the UI can show where the pipeline failed.
//  4. ContentDirectory service endpoints are parsed if the description succeeds.
//  5. Devices are deduplicated by root-device identity, so one Plex server does
//     not appear multiple times when it answers several SSDP search targets.
//

import Darwin
import Foundation
import Network

// MARK: - SSDP constants

private let ssdpDiscoveryPort: UInt16 = 1900

/// These are intentionally broad because many real DLNA servers do not respond
/// reliably to only the narrow MediaServer target.
private let ssdpSearchTargets = [
    "urn:schemas-upnp-org:device:MediaServer:1",
    "urn:schemas-upnp-org:service:ContentDirectory:1",
    "upnp:rootdevice",
    "ssdp:all",
]

/// Private Bonjour service used only to trigger local-network permission.
private let localNetworkAuthorizationServiceType = "_nookplayauth._tcp"

// MARK: - Identity / merge helpers

/// SSDP USN values often look like:
/// `uuid:device-id::upnp:rootdevice`
/// `uuid:device-id::urn:schemas-upnp-org:device:MediaServer:1`
///
/// Those are the same physical device, so we normalize to only the root `uuid:...`
/// part before `::`.
private nonisolated func normalizedRootUSN(_ usn: String) -> String {
    let trimmed = usn.trimmingCharacters(in: .whitespacesAndNewlines)
    let root = trimmed.components(separatedBy: "::").first ?? trimmed
    return root.lowercased()
}

private nonisolated func normalizedLocationIdentity(_ url: URL) -> String {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.query = nil
    components?.fragment = nil

    let scheme = (components?.scheme ?? "http").lowercased()
    let host = (components?.host ?? "").lowercased()
    let port = components?.port.map { ":\($0)" } ?? ""
    let path = {
        let rawPath = components?.percentEncodedPath ?? ""
        return rawPath.isEmpty ? "/" : rawPath
    }()

    return "loc:\(scheme)://\(host)\(port)\(path)"
}

private nonisolated func normalizedDeviceIdentity(usn: String?, location: URL) -> String {
    if let usn, !usn.isEmpty {
        return normalizedRootUSN(usn)
    }
    return normalizedLocationIdentity(location)
}

/// Prefer a more specific SSDP target when merging repeated responses.
private nonisolated func searchTargetSpecificityScore(_ value: String) -> Int {
    let lower = value.lowercased()

    if lower.contains("device:mediaserver:1") { return 4 }
    if lower.contains("service:contentdirectory:1") { return 3 }
    if lower == "upnp:rootdevice" { return 2 }
    if lower == "ssdp:all" { return 1 }
    return 0
}

private nonisolated func preferredSearchTarget(_ lhs: String?, _ rhs: String?) -> String? {
    switch (lhs, rhs) {
    case let (left?, right?):
        searchTargetSpecificityScore(left) >= searchTargetSpecificityScore(right) ? left : right
    case let (left?, nil):
        left
    case let (nil, right?):
        right
    case (nil, nil):
        nil
    }
}

// MARK: - Public models

/// Resolved ContentDirectory service info from the device description XML.
struct DLNAContentDirectoryService: Hashable, Sendable {
    let serviceType: String
    let controlURL: URL
    let eventSubURL: URL?
    let scpdURL: URL?
}

/// One discovered DLNA / UPnP device.
///
/// `isConfirmedMediaServer` is true only when the description document strongly
/// indicates a media server. When false, the entry is still shown because the
/// current goal is investigation and visibility rather than aggressive filtering.
struct DLNAMediaServer: Identifiable, Hashable, Sendable {
    let id: String
    let usn: String?
    let location: URL
    let searchTarget: String
    let serverHeader: String?
    let friendlyName: String?
    let manufacturer: String?
    let modelName: String?
    let contentDirectory: DLNAContentDirectoryService?
    let isConfirmedMediaServer: Bool
    let responseHeaders: [String: String]

    nonisolated var displayName: String {
        friendlyName ?? modelName ?? usn ?? location.host ?? location.absoluteString
    }

    nonisolated var isProvisional: Bool {
        !isConfirmedMediaServer
    }
}

/// Diagnostics for one discovery run.
///
/// Show these in the UI while investigating. They make it much easier to tell
/// whether the problem is:
/// - no SSDP responses
/// - malformed / unexpected responses
/// - description fetch failure
/// - description parse failure
/// - over-filtering
struct DLNAScanDiagnostics: Sendable {
    let localNetworkAuthorizationSucceeded: Bool
    let discoveryTimeoutSeconds: TimeInterval

    let outboundInterfaceNames: [String]
    let outboundWarnings: [String]

    let rawDatagramCount: Int
    let parsedResponseCount: Int
    let candidateResponseCount: Int
    let parsedDescriptionCount: Int
    let confirmedMediaServerCount: Int
    let provisionalDeviceCount: Int

    /// Parsed SSDP header summaries for quick UI inspection.
    let responseHeaderSamples: [String]

    /// Raw text samples for packets that were received but did not parse as
    /// SSDP 200 OK responses.
    let parseFailurePacketSamples: [String]

    /// A log line per description fetch attempt.
    let descriptionFetchLogs: [String]
}

/// Final scan result.
struct DLNAScanResult: Sendable {
    let servers: [DLNAMediaServer]
    let diagnostics: DLNAScanDiagnostics
}

// MARK: - Local network authorization

private enum LocalNetworkAuthorizationRequester {
    private final class CompletionState: @unchecked Sendable {
        nonisolated(unsafe) var hasCompleted = false
    }

    private nonisolated static let serviceType = localNetworkAuthorizationServiceType

    static func requestAccess(timeout: TimeInterval = 5) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "NookPlay.LocalNetworkAuthorization")
            let serviceName = "NookPlay-\(UUID().uuidString)"
            let listener: NWListener

            do {
                listener = try NWListener(using: .tcp)
            } catch {
                continuation.resume(throwing: LocalNetworkAuthorizationError.listenerSetupFailed(error))
                return
            }

            listener.service = NWListener.Service(name: serviceName, type: serviceType)
            listener.newConnectionHandler = { connection in
                connection.cancel()
            }

            let browser = NWBrowser(
                for: .bonjour(type: serviceType, domain: nil),
                using: .tcp
            )

            let completionState = CompletionState()

            let complete: @Sendable (Result<Void, Error>) -> Void = { result in
                guard !completionState.hasCompleted else { return }
                completionState.hasCompleted = true

                browser.cancel()
                listener.cancel()

                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case let .failed(error):
                    complete(.failure(LocalNetworkAuthorizationError.listenerFailed(error)))
                default:
                    break
                }
            }

            browser.stateUpdateHandler = { state in
                switch state {
                case let .failed(error):
                    complete(.failure(LocalNetworkAuthorizationError.browserFailed(error)))
                case let .waiting(error):
                    complete(.failure(LocalNetworkAuthorizationError.authorizationUnavailable(error)))
                default:
                    break
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                let foundOwnService = results.contains { result in
                    switch result.endpoint {
                    case let .service(name: name, type: type, domain: _, interface: _):
                        name == serviceName && type == serviceType
                    default:
                        false
                    }
                }

                if foundOwnService {
                    complete(.success(()))
                }
            }

            queue.asyncAfter(deadline: .now() + timeout) {
                complete(.failure(LocalNetworkAuthorizationError.timedOut))
            }

            listener.start(queue: queue)
            browser.start(queue: queue)
        }
    }
}

private enum LocalNetworkAuthorizationError: LocalizedError {
    case listenerSetupFailed(Error)
    case listenerFailed(NWError)
    case browserFailed(NWError)
    case authorizationUnavailable(NWError)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .listenerSetupFailed:
            "Failed to prepare the local-network permission check."
        case .listenerFailed:
            "Failed to advertise the local-network permission check service."
        case .browserFailed:
            "Failed to browse the local network. Check Local Network permission in Settings."
        case .authorizationUnavailable:
            "Local Network access is unavailable. Check Local Network permission in Settings."
        case .timedOut:
            "Timed out while requesting Local Network access."
        }
    }
}

// MARK: - Main actor API

actor DLNAServiceDiscovery {
    /// Investigation-first scan.
    ///
    /// Timeout defaults to 6 seconds rather than 3. SSDP often works quickly,
    /// but a slightly longer window is useful while diagnosing missed servers.
    func discover(timeout: TimeInterval = 6) async throws -> DLNAScanResult {
        try await LocalNetworkAuthorizationRequester.requestAccess()

        let transportOutcome = try await SSDPDiscoveryOperation(timeout: timeout).start()
        let responses = transportOutcome.responsesByIdentity.values.sorted {
            $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending
        }

        // Convert responses into candidates and deduplicate by normalized root
        // device identity before description fetches.
        var candidatesByID: [String: DiscoveryCandidate] = [:]

        for response in responses {
            guard let locationString = response.headers["location"],
                  let location = URL(string: locationString)
            else {
                continue
            }

            let id = normalizedDeviceIdentity(
                usn: response.headers["usn"],
                location: location
            )

            let candidate = DiscoveryCandidate(
                id: id,
                usn: response.headers["usn"],
                location: location,
                st: response.headers["st"],
                nt: response.headers["nt"],
                serverHeader: response.headers["server"],
                responseHeaders: response.headers
            )

            if let existing = candidatesByID[id] {
                candidatesByID[id] = existing.merged(with: candidate)
            } else {
                candidatesByID[id] = candidate
            }
        }

        let candidates = candidatesByID.values.sorted {
            let left = $0.usn ?? $0.location.absoluteString
            let right = $1.usn ?? $1.location.absoluteString
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }

        var serversByID: [String: DLNAMediaServer] = [:]

        // Add all candidates as provisional entries first.
        for candidate in candidates {
            let searchTarget = preferredSearchTarget(candidate.st, candidate.nt) ?? "upnp:unknown"
            let strongHeaderSignal = candidate.looksLikeMediaServerFromHeaders

            serversByID[candidate.id] = DLNAMediaServer(
                id: candidate.id,
                usn: candidate.usn,
                location: candidate.location,
                searchTarget: searchTarget,
                serverHeader: candidate.serverHeader,
                friendlyName: nil,
                manufacturer: nil,
                modelName: nil,
                contentDirectory: nil,
                isConfirmedMediaServer: strongHeaderSignal,
                responseHeaders: candidate.responseHeaders
            )
        }

        var descriptionFetchLogs: [String] = []
        var parsedDescriptionCount = 0

        // Enrich candidates concurrently, but never remove a provisional entry
        // if fetching/parsing the description fails.
        await withTaskGroup(of: DescriptionFetchResult.self) { group in
            for candidate in candidates {
                group.addTask {
                    await self.fetchDeviceDescription(from: candidate.location, candidateID: candidate.id)
                }
            }

            for await result in group {
                descriptionFetchLogs.append(result.logLine)

                guard let current = serversByID[result.candidateID] else {
                    continue
                }

                guard let description = result.description else {
                    continue
                }

                parsedDescriptionCount += 1

                let isConfirmed = description.isMediaServer || current.isConfirmedMediaServer

                serversByID[result.candidateID] = DLNAMediaServer(
                    id: current.id,
                    usn: current.usn,
                    location: current.location,
                    searchTarget: description.primarySearchTarget ?? current.searchTarget,
                    serverHeader: current.serverHeader,
                    friendlyName: description.friendlyName ?? current.friendlyName,
                    manufacturer: description.manufacturer ?? current.manufacturer,
                    modelName: description.modelName ?? current.modelName,
                    contentDirectory: description.contentDirectory ?? current.contentDirectory,
                    isConfirmedMediaServer: isConfirmed,
                    responseHeaders: current.responseHeaders
                )
            }
        }

        let servers = serversByID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        let confirmedMediaServerCount = servers.filter(\.isConfirmedMediaServer).count
        let provisionalDeviceCount = servers.count - confirmedMediaServerCount

        return DLNAScanResult(
            servers: servers,
            diagnostics: DLNAScanDiagnostics(
                localNetworkAuthorizationSucceeded: true,
                discoveryTimeoutSeconds: timeout,
                outboundInterfaceNames: transportOutcome.interfaceNames,
                outboundWarnings: transportOutcome.sendWarnings,
                rawDatagramCount: transportOutcome.rawDatagramCount,
                parsedResponseCount: transportOutcome.parsedResponseCount,
                candidateResponseCount: candidates.count,
                parsedDescriptionCount: parsedDescriptionCount,
                confirmedMediaServerCount: confirmedMediaServerCount,
                provisionalDeviceCount: provisionalDeviceCount,
                responseHeaderSamples: Array(
                    transportOutcome.responsesByIdentity.values
                        .prefix(8)
                        .map(\.headerSummary)
                ),
                parseFailurePacketSamples: transportOutcome.parseFailurePacketSamples,
                descriptionFetchLogs: descriptionFetchLogs
            )
        )
    }

    private func fetchDeviceDescription(from url: URL, candidateID: String) async -> DescriptionFetchResult {
        do {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 5
            configuration.waitsForConnectivity = false

            let session = URLSession(configuration: configuration)
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                return DescriptionFetchResult(
                    candidateID: candidateID,
                    description: nil,
                    logLine: "DESCRIPTION \(url.absoluteString) -> non-HTTP response"
                )
            }

            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                return DescriptionFetchResult(
                    candidateID: candidateID,
                    description: nil,
                    logLine: "DESCRIPTION \(url.absoluteString) -> HTTP \(httpResponse.statusCode)"
                )
            }

            let description = await MainActor.run {
                DeviceDescriptionParser.parse(data: data, documentURL: url)
            }

            guard let description else {
                return DescriptionFetchResult(
                    candidateID: candidateID,
                    description: nil,
                    logLine: "DESCRIPTION \(url.absoluteString) -> XML parse failed"
                )
            }

            return DescriptionFetchResult(
                candidateID: candidateID,
                description: description,
                logLine: "DESCRIPTION \(url.absoluteString) -> ok, friendlyName=\(description.friendlyName ?? "-"), deviceType=\(description.deviceType ?? "-"), contentDirectory=\(description.contentDirectory?.controlURL.absoluteString ?? "-")"
            )
        } catch {
            return DescriptionFetchResult(
                candidateID: candidateID,
                description: nil,
                logLine: "DESCRIPTION \(url.absoluteString) -> request failed: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Internal discovery models

private struct DiscoveryCandidate: Sendable {
    let id: String
    let usn: String?
    let location: URL
    let st: String?
    let nt: String?
    let serverHeader: String?
    let responseHeaders: [String: String]

    nonisolated var looksLikeMediaServerFromHeaders: Bool {
        let values = [st, nt, usn, serverHeader]
            .compactMap { $0?.lowercased() }

        return values.contains { value in
            value.contains("mediaserver") || value.contains("contentdirectory")
        }
    }

    nonisolated func merged(with other: DiscoveryCandidate) -> DiscoveryCandidate {
        var mergedHeaders = responseHeaders

        for (key, value) in other.responseHeaders where mergedHeaders[key] == nil {
            mergedHeaders[key] = value
        }

        mergedHeaders["st"] = preferredSearchTarget(responseHeaders["st"], other.responseHeaders["st"])
        mergedHeaders["nt"] = preferredSearchTarget(responseHeaders["nt"], other.responseHeaders["nt"])

        return DiscoveryCandidate(
            id: id,
            usn: usn ?? other.usn,
            location: location,
            st: preferredSearchTarget(st, other.st),
            nt: preferredSearchTarget(nt, other.nt),
            serverHeader: serverHeader ?? other.serverHeader,
            responseHeaders: mergedHeaders
        )
    }
}

private struct DescriptionFetchResult: Sendable {
    let candidateID: String
    let description: DeviceDescription?
    let logLine: String
}

// MARK: - SSDP discovery operation

private struct SSDPDiscoveryOutcome: Sendable {
    let responsesByIdentity: [String: SSDPDiscoveryResponse]
    let rawDatagramCount: Int
    let parsedResponseCount: Int
    let interfaceNames: [String]
    let sendWarnings: [String]
    let parseFailurePacketSamples: [String]
}

private final class SSDPDiscoveryOperation {
    private struct IPv4MulticastInterface {
        let name: String
        let address: in_addr
    }

    private let timeout: TimeInterval

    nonisolated init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    func start() async throws -> SSDPDiscoveryOutcome {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let outcome = try self.performScan()
                    continuation.resume(returning: outcome)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performScan() throws -> SSDPDiscoveryOutcome {
        let socketFD = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else {
            throw SSDPDiscoveryError.socketCreationFailed(errno)
        }

        defer {
            Darwin.close(socketFD)
        }

        var reuseAddress: Int32 = 1
        _ = setsockopt(
            socketFD,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var multicastTTL: UInt8 = 2
        _ = setsockopt(
            socketFD,
            IPPROTO_IP,
            IP_MULTICAST_TTL,
            &multicastTTL,
            socklen_t(MemoryLayout<UInt8>.size)
        )

        var disableLoopback: UInt8 = 0
        _ = setsockopt(
            socketFD,
            IPPROTO_IP,
            IP_MULTICAST_LOOP,
            &disableLoopback,
            socklen_t(MemoryLayout<UInt8>.size)
        )

        var localAddress = sockaddr_in()
        localAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        localAddress.sin_family = sa_family_t(AF_INET)
        localAddress.sin_port = in_port_t(0).bigEndian
        localAddress.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &localAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addressPointer in
                Darwin.bind(
                    socketFD,
                    addressPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }

        guard bindResult == 0 else {
            throw SSDPDiscoveryError.bindFailed(errno)
        }

        let sendResult = try sendDiscoveryRequests(using: socketFD)
        let receiveResult = try receiveDiscoveryResponses(using: socketFD)

        return SSDPDiscoveryOutcome(
            responsesByIdentity: receiveResult.responsesByIdentity,
            rawDatagramCount: receiveResult.rawDatagramCount,
            parsedResponseCount: receiveResult.parsedResponseCount,
            interfaceNames: sendResult.interfaceNames,
            sendWarnings: sendResult.warnings,
            parseFailurePacketSamples: receiveResult.parseFailurePacketSamples
        )
    }

    private func sendDiscoveryRequests(using socketFD: Int32) throws -> (interfaceNames: [String], warnings: [String]) {
        let interfaces = try availableIPv4MulticastInterfaces()
        var warnings: [String] = []
        var usedInterfaceNames: [String] = []

        var destinationAddress = sockaddr_in()
        destinationAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destinationAddress.sin_family = sa_family_t(AF_INET)
        destinationAddress.sin_port = ssdpDiscoveryPort.bigEndian

        let destinationIP = "239.255.255.250"
        let conversionResult = destinationIP.withCString { cString in
            inet_pton(AF_INET, cString, &destinationAddress.sin_addr)
        }
        guard conversionResult == 1 else {
            throw SSDPDiscoveryError.invalidDestinationAddress
        }

        if interfaces.isEmpty {
            warnings.append("No eligible IPv4 multicast interface found; sent via default route only.")
            try sendDiscoveryRequestsOnCurrentRoute(
                using: socketFD,
                destinationAddress: destinationAddress
            )
            return ([], warnings)
        }

        for interface in interfaces {
            var outboundAddress = interface.address
            let setResult = setsockopt(
                socketFD,
                IPPROTO_IP,
                IP_MULTICAST_IF,
                &outboundAddress,
                socklen_t(MemoryLayout<in_addr>.size)
            )

            if setResult != 0 {
                warnings.append("Failed to select multicast interface \(interface.name). errno=\(errno)")
                continue
            }

            do {
                try sendDiscoveryRequestsOnCurrentRoute(
                    using: socketFD,
                    destinationAddress: destinationAddress
                )
                usedInterfaceNames.append(interface.name)
            } catch {
                warnings.append("Failed to send discovery on interface \(interface.name): \(error.localizedDescription)")
            }
        }

        if usedInterfaceNames.isEmpty {
            warnings.append("No interface-specific send succeeded; trying default route.")
            try sendDiscoveryRequestsOnCurrentRoute(
                using: socketFD,
                destinationAddress: destinationAddress
            )
        }

        return (usedInterfaceNames, warnings)
    }

    private func sendDiscoveryRequestsOnCurrentRoute(
        using socketFD: Int32,
        destinationAddress: sockaddr_in
    ) throws {
        var destinationAddress = destinationAddress

        for searchTarget in ssdpSearchTargets {
            let payload =
                "M-SEARCH * HTTP/1.1\r\n" +
                "HOST: 239.255.255.250:1900\r\n" +
                "MAN: \"ssdp:discover\"\r\n" +
                "MX: 2\r\n" +
                "ST: \(searchTarget)\r\n" +
                "\r\n"

            guard let payloadData = payload.data(using: .utf8) else {
                throw SSDPDiscoveryError.invalidPayload
            }

            let bytesSent = payloadData.withUnsafeBytes { payloadPointer in
                withUnsafePointer(to: &destinationAddress) { addressPointer in
                    addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                        Darwin.sendto(
                            socketFD,
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
    }

    private func availableIPv4MulticastInterfaces() throws -> [IPv4MulticastInterface] {
        var interfaceListPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceListPointer) == 0, let firstInterface = interfaceListPointer else {
            throw SSDPDiscoveryError.interfaceEnumerationFailed(errno)
        }

        defer {
            freeifaddrs(interfaceListPointer)
        }

        var interfaces: [IPv4MulticastInterface] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstInterface

        while let current = cursor?.pointee {
            defer { cursor = current.ifa_next }

            let flags = Int32(current.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let supportsMulticast = (flags & IFF_MULTICAST) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            guard isUp, isRunning, supportsMulticast, !isLoopback else {
                continue
            }

            guard let addressPointer = current.ifa_addr,
                  addressPointer.pointee.sa_family == sa_family_t(AF_INET)
            else {
                continue
            }

            let socketAddress = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee
            }

            guard socketAddress.sin_addr.s_addr != INADDR_ANY.bigEndian else {
                continue
            }

            let name = String(cString: current.ifa_name)

            if interfaces.contains(where: { $0.name == name }) {
                continue
            }

            interfaces.append(
                IPv4MulticastInterface(
                    name: name,
                    address: socketAddress.sin_addr
                )
            )
        }

        return interfaces
    }

    private func receiveDiscoveryResponses(using socketFD: Int32) throws -> (
        responsesByIdentity: [String: SSDPDiscoveryResponse],
        rawDatagramCount: Int,
        parsedResponseCount: Int,
        parseFailurePacketSamples: [String]
    ) {
        var responsesByIdentity: [String: SSDPDiscoveryResponse] = [:]
        var rawDatagramCount = 0
        var parsedResponseCount = 0
        var parseFailurePacketSamples: [String] = []

        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let remaining = max(deadline.timeIntervalSinceNow, 0.1)

            var receiveTimeout = timeval(
                tv_sec: Int(remaining.rounded(.down)),
                tv_usec: Int32((remaining.truncatingRemainder(dividingBy: 1)) * 1_000_000)
            )

            let timeoutResult = setsockopt(
                socketFD,
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
                            socketFD,
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
                rawDatagramCount += 1

                let data = Data(buffer.prefix(bytesRead))
                let rawText = (String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? "")
                    .replacingOccurrences(of: "\r", with: "\\r")
                    .replacingOccurrences(of: "\n", with: "\\n")

                if let response = SSDPDiscoveryResponseParser.parse(data: data) {
                    parsedResponseCount += 1

                    let identity: String = {
                        if let locationString = response.headers["location"],
                           let location = URL(string: locationString)
                        {
                            return normalizedDeviceIdentity(
                                usn: response.headers["usn"],
                                location: location
                            )
                        }

                        if let usn = response.headers["usn"], !usn.isEmpty {
                            return normalizedRootUSN(usn)
                        }

                        return response.headers["server"]?.lowercased() ?? UUID().uuidString
                    }()

                    if let existing = responsesByIdentity[identity] {
                        responsesByIdentity[identity] = existing.merged(with: response)
                    } else {
                        responsesByIdentity[identity] = response
                    }
                } else if parseFailurePacketSamples.count < 8 {
                    parseFailurePacketSamples.append(rawText)
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

        return (
            responsesByIdentity: responsesByIdentity,
            rawDatagramCount: rawDatagramCount,
            parsedResponseCount: parsedResponseCount,
            parseFailurePacketSamples: parseFailurePacketSamples
        )
    }
}

private enum SSDPDiscoveryError: LocalizedError {
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case interfaceEnumerationFailed(Int32)
    case invalidPayload
    case invalidDestinationAddress
    case sendFailed(Int32)
    case receiveConfigurationFailed(Int32)
    case receiveFailed(Int32)

    var errorDescription: String? {
        switch self {
        case let .socketCreationFailed(code):
            "Failed to create SSDP discovery socket. (\(code))"
        case let .bindFailed(code):
            "Failed to bind SSDP discovery socket. (\(code))"
        case let .interfaceEnumerationFailed(code):
            "Failed to inspect local interfaces for SSDP discovery. (\(code))"
        case .invalidPayload:
            "Failed to prepare SSDP discovery request."
        case .invalidDestinationAddress:
            "Failed to prepare the SSDP multicast destination."
        case let .sendFailed(code):
            "Failed to send SSDP discovery request. (\(code))"
        case let .receiveConfigurationFailed(code):
            "Failed to configure SSDP response listening. (\(code))"
        case let .receiveFailed(code):
            "Failed to receive SSDP discovery response. (\(code))"
        }
    }
}

// MARK: - SSDP parsing

private struct SSDPDiscoveryResponse: Sendable {
    let headers: [String: String]

    nonisolated var sortKey: String {
        headers["usn"] ?? headers["location"] ?? headers["server"] ?? UUID().uuidString
    }

    nonisolated var headerSummary: String {
        [
            headers["st"].map { "ST=\($0)" },
            headers["nt"].map { "NT=\($0)" },
            headers["usn"].map { "USN=\($0)" },
            headers["location"].map { "LOCATION=\($0)" },
            headers["server"].map { "SERVER=\($0)" },
        ]
        .compactMap(\.self)
        .joined(separator: " | ")
    }

    nonisolated func merged(with other: SSDPDiscoveryResponse) -> SSDPDiscoveryResponse {
        var mergedHeaders = headers

        for (key, value) in other.headers where mergedHeaders[key] == nil {
            mergedHeaders[key] = value
        }

        mergedHeaders["st"] = preferredSearchTarget(headers["st"], other.headers["st"])
        mergedHeaders["nt"] = preferredSearchTarget(headers["nt"], other.headers["nt"])

        if mergedHeaders["usn"] == nil {
            mergedHeaders["usn"] = other.headers["usn"]
        }
        if mergedHeaders["location"] == nil {
            mergedHeaders["location"] = other.headers["location"]
        }
        if mergedHeaders["server"] == nil {
            mergedHeaders["server"] = other.headers["server"]
        }

        return SSDPDiscoveryResponse(headers: mergedHeaders)
    }
}

private enum SSDPDiscoveryResponseParser {
    nonisolated static func parse(data: Data) -> SSDPDiscoveryResponse? {
        guard let rawString = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else {
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
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            if headers[name] == nil {
                headers[name] = value
            }
        }

        return SSDPDiscoveryResponse(headers: headers)
    }
}

// MARK: - Device description parsing

private struct DeviceDescription: Sendable {
    let friendlyName: String?
    let manufacturer: String?
    let modelName: String?
    let deviceType: String?
    let serviceTypes: Set<String>
    let contentDirectory: DLNAContentDirectoryService?

    nonisolated var primarySearchTarget: String? {
        if let deviceType, !deviceType.isEmpty {
            return deviceType
        }

        if let contentDirectory {
            return contentDirectory.serviceType
        }

        return serviceTypes.first
    }

    nonisolated var isMediaServer: Bool {
        if let deviceType, deviceType.localizedCaseInsensitiveContains("MediaServer") {
            return true
        }

        if contentDirectory != nil {
            return true
        }

        return serviceTypes.contains { $0.localizedCaseInsensitiveContains("ContentDirectory") }
    }
}

private struct RawParsedService {
    let serviceType: String?
    let controlURL: String?
    let eventSubURL: String?
    let scpdURL: String?
}

private enum DeviceDescriptionParser {
    static func parse(data: Data, documentURL: URL) -> DeviceDescription? {
        let delegate = DeviceDescriptionXMLParserDelegate(documentURL: documentURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true

        guard parser.parse() else {
            return nil
        }

        return delegate.deviceDescription
    }
}

private final class DeviceDescriptionXMLParserDelegate: NSObject, XMLParserDelegate {
    private let documentURL: URL

    private(set) var deviceDescription: DeviceDescription?

    private var currentValue = ""

    private var friendlyName: String?
    private var manufacturer: String?
    private var modelName: String?
    private var deviceType: String?
    private var urlBaseString: String?

    private var serviceTypes = Set<String>()

    private var insideService = false
    private var currentServiceType: String?
    private var currentControlURL: String?
    private var currentEventSubURL: String?
    private var currentSCPDURL: String?
    private var services: [RawParsedService] = []

    init(documentURL: URL) {
        self.documentURL = documentURL
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes _: [String: String] = [:]
    ) {
        currentValue = ""

        if elementName == "service" {
            insideService = true
            currentServiceType = nil
            currentControlURL = nil
            currentEventSubURL = nil
            currentSCPDURL = nil
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
        let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "friendlyName" where friendlyName == nil && !value.isEmpty:
            friendlyName = value

        case "manufacturer" where manufacturer == nil && !value.isEmpty:
            manufacturer = value

        case "modelName" where modelName == nil && !value.isEmpty:
            modelName = value

        case "deviceType" where deviceType == nil && !value.isEmpty:
            deviceType = value

        case "URLBase" where !value.isEmpty:
            urlBaseString = value

        case "serviceType" where insideService && !value.isEmpty:
            currentServiceType = value
            serviceTypes.insert(value)

        case "controlURL" where insideService && !value.isEmpty:
            currentControlURL = value

        case "eventSubURL" where insideService && !value.isEmpty:
            currentEventSubURL = value

        case "SCPDURL" where insideService && !value.isEmpty:
            currentSCPDURL = value

        case "service":
            insideService = false
            services.append(
                RawParsedService(
                    serviceType: currentServiceType,
                    controlURL: currentControlURL,
                    eventSubURL: currentEventSubURL,
                    scpdURL: currentSCPDURL
                )
            )
            currentServiceType = nil
            currentControlURL = nil
            currentEventSubURL = nil
            currentSCPDURL = nil

        default:
            break
        }

        currentValue = ""
    }

    func parserDidEndDocument(_: XMLParser) {
        let baseURL: URL = {
            if let urlBaseString,
               let urlBase = URL(string: urlBaseString)
            {
                return urlBase
            }
            return documentURL
        }()

        let contentDirectory: DLNAContentDirectoryService? = services
            .first(where: { ($0.serviceType ?? "").localizedCaseInsensitiveContains("ContentDirectory") })
            .flatMap { service in
                guard
                    let serviceType = service.serviceType,
                    let controlURLString = service.controlURL,
                    let controlURL = Self.resolveURL(controlURLString, relativeTo: baseURL)
                else {
                    return nil
                }

                let eventSubURL = service.eventSubURL.flatMap { Self.resolveURL($0, relativeTo: baseURL) }
                let scpdURL = service.scpdURL.flatMap { Self.resolveURL($0, relativeTo: baseURL) }

                return DLNAContentDirectoryService(
                    serviceType: serviceType,
                    controlURL: controlURL,
                    eventSubURL: eventSubURL,
                    scpdURL: scpdURL
                )
            }

        deviceDescription = DeviceDescription(
            friendlyName: friendlyName,
            manufacturer: manufacturer,
            modelName: modelName,
            deviceType: deviceType,
            serviceTypes: serviceTypes,
            contentDirectory: contentDirectory
        )
    }

    private static func resolveURL(_ raw: String, relativeTo baseURL: URL) -> URL? {
        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }

        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }
}
