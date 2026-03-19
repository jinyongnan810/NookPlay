//
//  PlayableMediaSource.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

protocol PlayableMediaSource {
    var playbackID: PlaybackItemID { get }
    var title: String { get }
    var subtitle: String? { get }
    var streamURL: URL { get }
}

struct AnyPlayableMediaSource: PlayableMediaSource {
    let playbackID: PlaybackItemID
    let title: String
    let subtitle: String?
    let streamURL: URL
    let accessSession: SecurityScopedAccess?
}
