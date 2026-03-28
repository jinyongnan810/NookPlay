//
//  DLNAPlayableMedia.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

/// A concrete playable source for DLNA media items.
///
/// DLNA browse results provide enough information to route remote items through the same
/// playback pipeline the app already uses for local and web media. This adapter keeps the
/// server-specific identifier construction close to the DLNA feature instead of leaking it
/// into the generic player flow.
struct DLNAPlayableMedia: PlayableMediaSource {
    /// The stable playback identifier used for resume persistence.
    let playbackID: PlaybackItemID
    /// The title shown in the player and resume history.
    let title: String
    /// The subtitle shown when the server exposed supporting metadata.
    let subtitle: String?
    /// The remote media URL loaded by `AVPlayer`.
    let streamURL: URL

    /// Converts the concrete DLNA source into the type-erased media source used by the app shell.
    var asMediaSource: AnyPlayableMediaSource {
        AnyPlayableMediaSource(
            playbackID: playbackID,
            title: title,
            subtitle: subtitle,
            streamURL: streamURL,
            accessSession: nil,
            playbackLifetime: nil
        )
    }
}

extension DLNAPlayableMedia {
    /// Builds a playable media source from a browsed DLNA item.
    ///
    /// The raw playback identifier includes the server identity, DLNA object ID, and concrete
    /// stream URL. That combination keeps resume entries stable across launches while still
    /// separating two different files that might share the same object ID on different servers.
    init?(server: DLNAMediaServer, item: DLNABrowseItem) {
        guard let streamURL = item.streamURL else {
            return nil
        }

        playbackID = PlaybackItemID(
            sourceType: .dlna,
            rawID: "\(server.id)::\(item.objectID)::\(streamURL.absoluteString)"
        )
        title = item.title
        subtitle = item.subtitle ?? server.displayName
        self.streamURL = streamURL
    }
}
