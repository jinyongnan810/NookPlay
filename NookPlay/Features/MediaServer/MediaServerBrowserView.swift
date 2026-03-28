//
//  MediaServerBrowserView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Observation
import SwiftUI

/// Browses the contents of a single DLNA media server folder.
///
/// Each screen instance is responsible for one container. Pushing a folder creates a new browser
/// view with that child container's object ID, which keeps navigation state aligned with the
/// server's own folder hierarchy.
struct MediaServerBrowserView: View {
    // MARK: Environment

    @Environment(AppModel.self) private var appModel

    // MARK: State

    /// The server and container-specific browser state displayed on this screen.
    @State private var viewModel: MediaServerBrowserViewModel

    /// A programmatic navigation target used when the user activates a folder row.
    ///
    /// This keeps folders and playable items on the same interaction path: every row is a button,
    /// and the action decides whether to navigate deeper or start playback.
    @State private var pushedContainer: BrowserDestination?

    // MARK: Initialization

    init(server: DLNAMediaServer, containerID: String = "0", title: String? = nil) {
        _viewModel = State(
            initialValue: MediaServerBrowserViewModel(
                server: server,
                containerID: containerID,
                navigationTitle: title ?? server.displayName
            )
        )
    }

    /// Creates a browser view from an already-configured view model.
    ///
    /// Previews use this to render specific loading and error states without depending on live
    /// network discovery or mutating private state after initialization.
    fileprivate init(viewModel: MediaServerBrowserViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    // MARK: Body

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                errorSection(message: errorMessage)
            }

            ForEach(viewModel.items) { item in
                MediaServerBrowserRowButton(
                    item: item,
                    isEnabled: isRowEnabled(item)
                ) {
                    activate(item)
                }
            }
        }
        .overlay {
            if viewModel.isLoading, viewModel.items.isEmpty {
                ProgressView("Loading Media…")
            } else if !viewModel.isLoading, viewModel.items.isEmpty, viewModel.errorMessage == nil {
                ContentUnavailableView {
                    Label("No Media Found", systemImage: "film.stack")
                } description: {
                    Text("This folder is empty or the server did not expose any direct children here.")
                }
            }
        }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pushedContainer) { destination in
            MediaServerBrowserView(
                server: viewModel.server,
                containerID: destination.containerID,
                title: destination.title
            )
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.reload()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if viewModel.isLoading {
                    ProgressView()
                }
            }
        }
        .alert("Playback Unavailable", isPresented: playbackAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.playbackErrorMessage ?? "This media item could not be played.")
        }
    }

    // MARK: Helpers

    /// A lightweight alert binding that derives visibility from the view model's error message.
    private var playbackAlertBinding: Binding<Bool> {
        Binding(
            get: {
                viewModel.playbackErrorMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    viewModel.clearPlaybackError()
                }
            }
        )
    }

    /// Returns whether a row should be interactive.
    ///
    /// Folders are always enabled because browsing deeper is always valid.
    /// Media items are only enabled when they expose a playable resource.
    private func isRowEnabled(_ item: DLNABrowseItem) -> Bool {
        item.isContainer || item.canPlay
    }

    /// Activates the selected row.
    ///
    /// Container rows navigate deeper into the DLNA hierarchy. Playable media rows are converted
    /// into the app's shared playback source and sent to the player flow.
    private func activate(_ item: DLNABrowseItem) {
        if item.isContainer {
            pushedContainer = BrowserDestination(
                containerID: item.objectID,
                title: item.title
            )
            return
        }

        play(item)
    }

    /// A retry section that keeps the failure state visible inside the list.
    private func errorSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unable to Load This Folder")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Try Again") {
                Task {
                    await viewModel.reload()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
    }

    /// Converts a browse item into a playable source and hands it to the shared player flow.
    private func play(_ item: DLNABrowseItem) {
        guard let mediaSource = DLNAPlayableMedia(server: viewModel.server, item: item)?.asMediaSource else {
            viewModel.reportPlaybackError("This media item does not include a playable stream URL.")
            return
        }

        appModel.presentPlayer(for: mediaSource)
    }
}

// MARK: - BrowserDestination

/// A lightweight navigation target for pushing into a child DLNA container.
private struct BrowserDestination: Hashable, Identifiable {
    let containerID: String
    let title: String

    var id: String {
        containerID
    }
}

// MARK: - MediaServerBrowserViewModel

@MainActor
@Observable
final class MediaServerBrowserViewModel {
    // MARK: Immutable State

    /// The server whose ContentDirectory is being browsed.
    let server: DLNAMediaServer

    /// The DLNA container identifier represented by this screen.
    let containerID: String

    /// The current screen title. Parent screens supply the folder title when pushing deeper.
    let navigationTitle: String

    // MARK: Observable State

    /// The current folder contents shown in the list.
    private(set) var items: [DLNABrowseItem] = []

    /// Indicates whether a browse request is currently in flight.
    private(set) var isLoading = false

    /// A user-facing loading error for the current folder.
    private(set) var errorMessage: String?

    /// A user-facing playback error when the user taps a non-playable entry.
    private(set) var playbackErrorMessage: String?

    // MARK: Private State

    /// Prevents repeated automatic loads each time SwiftUI refreshes the view body.
    private var hasLoadedOnce = false

    /// The network service that performs SOAP browse requests.
    @ObservationIgnored
    private let browser = DLNAContentDirectoryBrowser()

    // MARK: Initialization

    init(server: DLNAMediaServer, containerID: String, navigationTitle: String) {
        self.server = server
        self.containerID = containerID
        self.navigationTitle = navigationTitle
    }

    /// A preview-only initializer that seeds observable state without issuing network requests.
    ///
    /// Keeping this initializer in the primary type declaration avoids Swift's restriction on
    /// designated initializers declared in extensions while still containing the helper to this
    /// file and this specific view model.
    init(
        server: DLNAMediaServer,
        containerID: String,
        navigationTitle: String,
        items: [DLNABrowseItem],
        isLoading: Bool,
        errorMessage: String?,
        playbackErrorMessage: String?,
        hasLoadedOnce: Bool
    ) {
        self.server = server
        self.containerID = containerID
        self.navigationTitle = navigationTitle
        self.items = items
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.playbackErrorMessage = playbackErrorMessage
        self.hasLoadedOnce = hasLoadedOnce
    }

    // MARK: Public Actions

    /// Loads the current folder once when the screen first appears.
    func loadIfNeeded() async {
        guard !hasLoadedOnce else {
            return
        }

        hasLoadedOnce = true
        await load()
    }

    /// Reloads the current folder from the server.
    func reload() async {
        await load()
    }

    /// Clears the current playback error after the alert is dismissed.
    func clearPlaybackError() {
        playbackErrorMessage = nil
    }

    /// Stores a playback error that should be surfaced to the user.
    func reportPlaybackError(_ message: String) {
        playbackErrorMessage = message
    }

    // MARK: Private Helpers

    /// Performs the actual browse request and normalizes item ordering for the UI.
    ///
    /// Containers are listed first because folder-first navigation matches how users typically scan
    /// media libraries. Within each group the titles are sorted alphabetically to keep reloads stable.
    private func load() async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let response = try await browser.browse(server: server, containerID: containerID)
            items = response.items.sorted { lhs, rhs in
                if lhs.isContainer != rhs.isContainer {
                    return lhs.isContainer && !rhs.isContainer
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        } catch is CancellationError {
            // SwiftUI can cancel `.task` work during navigation transitions. Treat that as a normal
            // lifecycle event rather than surfacing a misleading error to the user.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - MediaServerBrowserRowButton

/// A custom list row button that keeps full-row hover feedback aligned with SwiftUI's list system.
///
/// visionOS `List` rows already support a row-scoped hover presentation. Using
/// `listRowHoverEffect(.highlight)` keeps the effect attached to the list row itself, which is more
/// reliable than trying to infer hover state manually from the button subtree.
private struct MediaServerBrowserRowButton: View {
    let item: DLNABrowseItem
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MediaServerBrowseRow(item: item)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(MediaServerBrowserRowButtonStyle())
        .disabled(!isEnabled)
        .listRowInsets(EdgeInsets())
        .listRowHoverEffect(isEnabled ? .highlight : nil)
    }
}

// MARK: - MediaServerBrowserRowButtonStyle

/// A lightweight button style used only for press feedback.
///
/// Hover highlighting is delegated to the containing `List` row so this style only needs to handle
/// the pressed-state response.
private struct MediaServerBrowserRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.995 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - MediaServerBrowseRow

/// The shared visual content for each media browser row.
///
/// This view is intentionally content-only. It does not own hover backgrounds or outer row padding,
/// which keeps the visual layout reusable regardless of whether the row is interactive, disabled,
/// hovered, or pressed.
private struct MediaServerBrowseRow: View {
    /// The DLNA entry displayed by this row.
    let item: DLNABrowseItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(item.canPlay || item.isContainer ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(item.canPlay || item.isContainer ? .primary : .secondary)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            trailingAccessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The trailing information or affordance displayed at the far edge of the row.
    @ViewBuilder
    private var trailingAccessory: some View {
        if item.isContainer {
            HStack(spacing: 8) {
                if let childCount = item.childCount {
                    Text("\(childCount)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        } else if !item.canPlay {
            Text("Unavailable")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// A system image that distinguishes folders from playable items.
    private var iconName: String {
        if item.isContainer {
            return "folder"
        }

        return item.canPlay ? "play.rectangle.fill" : "film"
    }

    /// A compact subtitle that favors user-meaningful metadata over low-level protocol details.
    private var subtitle: String? {
        guard item.canPlay else {
            return nil
        }

        if let subtitle = item.subtitle {
            return subtitle
        }

        if let mimeType = item.mimeType {
            return mimeType
        }

        return nil
    }
}

#Preview("Loaded") {
    NavigationStack {
        MediaServerBrowserView(
            viewModel: MediaServerBrowserViewModel.previewLoaded
        )
    }
    .environment(AppModel())
}

#Preview("Empty") {
    NavigationStack {
        MediaServerBrowserView(
            viewModel: MediaServerBrowserViewModel.previewEmpty
        )
    }
    .environment(AppModel())
}

#Preview("Error") {
    NavigationStack {
        MediaServerBrowserView(
            viewModel: MediaServerBrowserViewModel.previewError
        )
    }
    .environment(AppModel())
}

private extension MediaServerBrowserViewModel {
    /// A stable preview server that exposes a browseable ContentDirectory endpoint.
    static let previewServer = DLNAMediaServer(
        id: "preview-server",
        usn: "uuid:preview-server",
        location: URL(string: "http://192.168.1.20:8200/rootDesc.xml")!,
        searchTarget: "urn:schemas-upnp-org:device:MediaServer:1",
        serverHeader: "NookPlay Preview",
        friendlyName: "Living Room Server",
        manufacturer: "Preview Devices",
        modelName: "Media Vault",
        contentDirectory: DLNAContentDirectoryService(
            serviceType: "urn:schemas-upnp-org:service:ContentDirectory:1",
            controlURL: URL(string: "http://192.168.1.20:8200/ctl/ContentDir")!,
            eventSubURL: URL(string: "http://192.168.1.20:8200/evt/ContentDir")!,
            scpdURL: URL(string: "http://192.168.1.20:8200/scpd/ContentDir.xml")!
        ),
        isConfirmedMediaServer: true,
        responseHeaders: [:]
    )

    /// A preview configuration that shows a typical folder with both containers and media items.
    static var previewLoaded: MediaServerBrowserViewModel {
        let viewModel = MediaServerBrowserViewModel(
            server: previewServer,
            containerID: "0",
            navigationTitle: "Living Room Server"
        )
        viewModel.items = [
            DLNABrowseItem(
                id: "container::movies",
                objectID: "movies",
                parentID: "0",
                title: "Movies",
                subtitle: "library storageFolder",
                kind: .container,
                childCount: 24,
                streamURL: nil,
                mimeType: nil,
                protocolInfo: nil
            ),
            DLNABrowseItem(
                id: "container::shows",
                objectID: "shows",
                parentID: "0",
                title: "TV Shows",
                subtitle: "library storageFolder",
                kind: .container,
                childCount: 61,
                streamURL: nil,
                mimeType: nil,
                protocolInfo: nil
            ),
            DLNABrowseItem(
                id: "item::sample-video",
                objectID: "sample-video",
                parentID: "0",
                title: "Big Buck Bunny",
                subtitle: "Blender Foundation • object item videoItem movie",
                kind: .item,
                childCount: nil,
                streamURL: URL(string: "https://example.com/video.mp4"),
                mimeType: "video/mp4",
                protocolInfo: "http-get:*:video/mp4:*"
            ),
            DLNABrowseItem(
                id: "item::metadata-only",
                objectID: "metadata-only",
                parentID: "0",
                title: "Unsupported Entry",
                subtitle: "object item",
                kind: .item,
                childCount: nil,
                streamURL: nil,
                mimeType: nil,
                protocolInfo: nil
            ),
        ]
        return viewModel
    }

    /// A preview configuration for an empty folder after a successful load.
    static var previewEmpty: MediaServerBrowserViewModel {
        MediaServerBrowserViewModel(
            server: previewServer,
            containerID: "empty-folder",
            navigationTitle: "Empty Folder",
            items: [],
            isLoading: false,
            errorMessage: nil,
            playbackErrorMessage: nil,
            hasLoadedOnce: true
        )
    }

    /// A preview configuration for a browse failure before any items were loaded.
    static var previewError: MediaServerBrowserViewModel {
        MediaServerBrowserViewModel(
            server: previewServer,
            containerID: "offline-folder",
            navigationTitle: "Offline Folder",
            items: [],
            isLoading: false,
            errorMessage: "The media server returned an unreadable browse response.",
            playbackErrorMessage: nil,
            hasLoadedOnce: true
        )
    }
}
