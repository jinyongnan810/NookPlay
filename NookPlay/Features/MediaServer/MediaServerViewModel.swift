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
    /// Diagnostics from the most recent scan, whether it succeeded or not.
    private(set) var diagnostics: DLNAScanDiagnostics?

    // MARK: Private Dependencies

    /// The SSDP discovery service for DLNA media servers.
    @ObservationIgnored
    private let discoveryService = DLNAServiceDiscovery()

    // MARK: Public Actions

    /// Starts a new DLNA discovery scan on the local network.
    func scanForServers() {
        guard !isScanning else {
            return
        }

        isScanning = true
        errorMessage = nil
        discoveredServers = []
        diagnostics = nil

        Task {
            do {
                let result = try await discoveryService.discover()
                discoveredServers = result.servers
                diagnostics = result.diagnostics
                isScanning = false
            } catch {
                errorMessage = error.localizedDescription
                isScanning = false
            }
        }
    }
}
