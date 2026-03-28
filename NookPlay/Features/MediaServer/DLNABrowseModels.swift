//
//  DLNABrowseModels.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

/// One parsed entry returned from a DLNA ContentDirectory browse request.
///
/// The browse response can contain both folders (`container`) and media items (`item`).
/// Keeping them in one model lets the browser UI render a single list while still making
/// it explicit whether tapping should navigate deeper or start playback.
struct DLNABrowseItem: Identifiable, Hashable, Sendable {
    /// The semantic kind of entry returned by the DIDL-Lite payload.
    enum Kind: String, Hashable, Sendable {
        case container
        case item
    }

    /// A stable identity for SwiftUI list diffing.
    ///
    /// DLNA object identifiers are only guaranteed to be unique within a server, so the
    /// browser combines the object identifier with the entry kind to avoid accidental
    /// collisions between folders and files that reuse the same raw object ID.
    let id: String
    /// The DLNA object identifier used for follow-up browse requests and playback identity.
    let objectID: String
    /// The parent object identifier reported by the server, when available.
    let parentID: String?
    /// The main label shown in the browsing UI.
    let title: String
    /// Supporting metadata shown under the main title when the server exposed something useful.
    let subtitle: String?
    /// Whether this entry is a navigable folder or a playable item.
    let kind: Kind
    /// The server-reported child count for containers, when available.
    let childCount: Int?
    /// The best stream URL parsed from the entry's resource list.
    let streamURL: URL?
    /// The MIME type inferred from the selected protocol info, when present.
    let mimeType: String?
    /// The full DLNA protocol info string for the selected resource.
    let protocolInfo: String?

    /// Whether the entry represents a folder that should push another browse screen.
    var isContainer: Bool {
        kind == .container
    }

    /// Whether the entry has enough data to start playback directly.
    ///
    /// Some servers return metadata-only items without a playable resource URL. Those should stay
    /// visible to avoid hiding server data, but the UI needs a clear way to avoid advertising them
    /// as tappable playback targets.
    var canPlay: Bool {
        kind == .item && streamURL != nil
    }
}

/// The parsed result of a single ContentDirectory browse request.
struct DLNABrowseResponse: Sendable {
    /// The object identifier whose direct children were requested.
    let containerID: String
    /// The parsed direct children returned by the server.
    let items: [DLNABrowseItem]
    /// The server-reported total match count, when provided.
    let totalMatches: Int?
}
