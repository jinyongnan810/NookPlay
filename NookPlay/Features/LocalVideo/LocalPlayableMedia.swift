//
//  LocalPlayableMedia.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

struct LocalPlayableMedia: PlayableMediaSource {
    let playbackID: PlaybackItemID
    let title: String
    let subtitle: String?
    let streamURL: URL
    let accessSession: SecurityScopedAccess?

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
