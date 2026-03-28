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
    @State private var viewModel: MediaServerViewModel

    // MARK: Initialization

    /// Creates the live discovery screen with its own empty view model.
    ///
    /// This keeps the production call site simple while ensuring the initialization happens
    /// on the main actor, which is required by the observable view model.
    /// Allows previews to inject representative discovery state while the live screen still
    /// defaults to an empty model that performs discovery only when the user requests it.
    @MainActor
    init() {
        _viewModel = State(initialValue: MediaServerViewModel())
    }

    /// Accepts a preconfigured view model for previews and other controlled render contexts.
    @MainActor
    init(viewModel: MediaServerViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

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
                    Label("Scan for Servers", systemImage: "dot.radiowaves.left.and.right")
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
                NavigationLink {
                    MediaServerBrowserView(server: server)
                } label: {
                    MediaServerRow(server: server)
                }
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
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: server.contentDirectory != nil ? "externaldrive.connected.to.line.below" : "network")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text(primaryTitle)
                        .font(.headline)

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The most useful display title available for the server.
    private var primaryTitle: String {
        // Reuse the model's shared display-name fallback chain so every place that renders a server
        // title behaves consistently, including provisional devices with sparse metadata.
        server.displayName
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
        MediaServerView(
            viewModel: MediaServerViewModel(
                discoveredServers: [
                    DLNAMediaServer(
                        id: "preview-plex-server",
                        usn: "uuid:preview-plex-server::upnp:rootdevice",
                        location: URL(string: "http://192.168.1.50:32469/description.xml")!,
                        searchTarget: "urn:schemas-upnp-org:device:MediaServer:1",
                        serverHeader: "Plex Media Server/1.41.0.8994",
                        friendlyName: "Living Room Plex",
                        manufacturer: "Plex, Inc.",
                        modelName: "Plex Media Server",
                        contentDirectory: DLNAContentDirectoryService(
                            serviceType: "urn:schemas-upnp-org:service:ContentDirectory:1",
                            controlURL: URL(string: "http://192.168.1.50:32469/upnp/control/content_directory")!,
                            eventSubURL: URL(string: "http://192.168.1.50:32469/upnp/event/content_directory"),
                            scpdURL: URL(string: "http://192.168.1.50:32469/xml/content_directory.xml")
                        ),
                        isConfirmedMediaServer: true,
                        responseHeaders: [
                            "location": "http://192.168.1.50:32469/description.xml",
                            "server": "Plex Media Server/1.41.0.8994",
                        ]
                    ),
                ]
            )
        )
    }
}
