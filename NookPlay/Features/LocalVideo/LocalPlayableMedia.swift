//
//  LocalPlayableMedia.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

/// A concrete playable source for user-imported local video files.
struct LocalPlayableMedia: PlayableMediaSource {
    /// The stable playback identifier derived from the imported file URL.
    let playbackID: PlaybackItemID
    /// The title shown for the imported file.
    let title: String
    /// The subtitle shown for the imported file.
    let subtitle: String?
    /// The file URL used for playback.
    let streamURL: URL
    /// The security-scoped access session that keeps the imported file readable.
    let accessSession: SecurityScopedAccess?

    /// Converts the local media item into the app's type-erased playable source.
    var asMediaSource: AnyPlayableMediaSource {
        AnyPlayableMediaSource(
            playbackID: playbackID,
            title: title,
            subtitle: subtitle,
            streamURL: streamURL,
            accessSession: accessSession
        )
    }
}
