//
//  MediaServerView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import SwiftUI

/// The DLNA media-server discovery screen.
struct MediaServerView: View {
    // MARK: State

    /// The discovery state and results shown on this screen.
    @State private var viewModel = MediaServerViewModel()

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                if viewModel.discoveredServers.isEmpty {
                    emptyStateSection
                } else {
                    serverListSection
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .navigationTitle("Media Server")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    /// The page header and primary scan action.
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan your local network for DLNA or UPnP media servers.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button {
                viewModel.scanForServers()
            } label: {
                if viewModel.isScanning {
                    Label("Scanning…", systemImage: "dot.radiowaves.left.and.right")
                } else {
                    Label("Scan for Servers", systemImage: "network")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isScanning)
        }
    }

    /// The empty-state content shown before or after a scan with no results.
    private var emptyStateSection: some View {
        ContentUnavailableView {
            Label(
                viewModel.isScanning ? "Searching for Media Servers" : "No Media Servers Found",
                systemImage: viewModel.isScanning ? "dot.radiowaves.left.and.right" : "network.slash"
            )
        } description: {
            Text(emptyStateDescription)
        }
    }

    /// The list of discovered DLNA servers.
    private var serverListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discovered Servers")
                .font(.title2)
                .fontWeight(.medium)

            ForEach(viewModel.discoveredServers) { server in
                MediaServerRow(server: server)
            }
        }
    }

    /// The empty-state description matching the current scan state.
    private var emptyStateDescription: String {
        if viewModel.isScanning {
            return "NookPlay is sending SSDP discovery requests and waiting for local media-server responses."
        }

        return "Make sure your media server is on the same network, then run another scan."
    }
}

// MARK: - MediaServerRow

private struct MediaServerRow: View {
    /// The discovered media server to display.
    let server: DLNAMediaServer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(primaryTitle)
                .font(.headline)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(server.location.absoluteString)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// The most useful display title available for the server.
    private var primaryTitle: String {
        server.friendlyName ?? server.modelName ?? server.usn
    }

    /// Optional supporting metadata shown below the main title.
    private var subtitle: String? {
        let parts: [String] = [server.manufacturer, server.modelName, server.serverHeader]
            .compactMap { value in
                guard let value, !value.isEmpty else {
                    return nil
                }
                return value
            }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: " • ")
    }
}

#Preview {
    NavigationStack {
        MediaServerView()
    }
}
