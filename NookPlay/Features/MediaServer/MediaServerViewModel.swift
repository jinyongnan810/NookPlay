//
//  MediaServerViewModel.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation
import Observation

@MainActor
@Observable
final class MediaServerViewModel {
    // MARK: Observable State

    /// The media servers discovered during the latest scan.
    private(set) var discoveredServers: [DLNAMediaServer] = []
    /// Indicates whether a discovery scan is currently active.
    private(set) var isScanning = false
    /// A user-facing discovery error, if one occurs.
    private(set) var errorMessage: String?

    // MARK: Private Dependencies

    /// The SSDP discovery service for DLNA media servers.
    @ObservationIgnored
    private let discoveryService = DLNAServiceDiscovery()

    // MARK: Initialization

    /// Creates the discovery view model with optional preloaded state.
    ///
    /// The default values preserve production behavior. The seeded values exist so previews
    /// can render realistic discovery results without triggering live local-network work.
    init(
        discoveredServers: [DLNAMediaServer] = [],
        isScanning: Bool = false,
        errorMessage: String? = nil
    ) {
        self.discoveredServers = discoveredServers
        self.isScanning = isScanning
        self.errorMessage = errorMessage
    }

    // MARK: Public Actions

    /// Starts a new DLNA discovery scan on the local network.
    func scanForServers() {
        guard !isScanning else {
            return
        }

        isScanning = true
        errorMessage = nil
        discoveredServers = []

        Task {
            do {
                let result = try await discoveryService.discover()
                discoveredServers = result.servers
                isScanning = false
            } catch {
                errorMessage = error.localizedDescription
                isScanning = false
            }
        }
    }
}
