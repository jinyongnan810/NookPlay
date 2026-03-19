//
//  PlayableMediaSource.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

/// A source of playable media that can be handed to the shared player flow.
///
/// Keeping this protocol small lets local, web, and DLNA items all feed the
/// same playback UI and persistence logic.
protocol PlayableMediaSource {
    /// The stable identifier used for resume persistence and recents.
    var playbackID: PlaybackItemID { get }
    /// The main display title for the media item.
    var title: String { get }
    /// A secondary label for the media item, when available.
    var subtitle: String? { get }
    /// The URL the player should open.
    var streamURL: URL { get }
}

/// A type-erased playable source used by views and view models.
struct AnyPlayableMediaSource: PlayableMediaSource {
    /// The stable identifier for this media item.
    let playbackID: PlaybackItemID
    /// The user-facing title for this media item.
    let title: String
    /// The optional subtitle shown alongside the title.
    let subtitle: String?
    /// The URL loaded by `AVPlayer`.
    let streamURL: URL
    /// A live security-scoped access session for local files, if one is required.
    ///
    /// Remote sources leave this as `nil`.
    let accessSession: SecurityScopedAccess?
    /// A retained cleanup token for resources that should live for the playback session.
    ///
    /// Local photo-library imports use this to delete temporary copied files when
    /// the player releases the source.
    let playbackLifetime: PlaybackLifetimeResource?
}

/// A resource that should remain alive for the duration of a playback session.
protocol PlaybackLifetimeResource: AnyObject {}
