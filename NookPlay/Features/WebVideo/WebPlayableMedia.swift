//
//  WebPlayableMedia.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

/// A concrete playable source for browser-discovered video URLs.
///
/// The in-app browser can occasionally resolve a plain media URL from an HTML5
/// `<video>` element. When that happens, this adapter lets the browser hand the
/// resolved URL to the same native player flow used by local and DLNA media.
///
/// This type intentionally models only the simple case where the webpage exposes
/// a direct stream URL that `AVPlayer` can open on its own. It does not attempt
/// to preserve cookies, JavaScript state, DRM sessions, or page-specific headers.
struct WebPlayableMedia: PlayableMediaSource {
    /// The stable identifier used for resume persistence.
    let playbackID: PlaybackItemID
    /// The title shown in the native player UI.
    let title: String
    /// Additional context that helps the user understand where the stream came from.
    let subtitle: String?
    /// The direct media URL loaded by `AVPlayer`.
    let streamURL: URL

    /// Converts the concrete web source into the app's shared type-erased media source.
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

extension WebPlayableMedia {
    /// Creates a playable web source when the browser has resolved a direct media URL.
    ///
    /// The raw ID includes both the page URL and the concrete stream URL. That keeps
    /// resume history stable for the same item while still separating two different
    /// videos served from the same page.
    init?(streamURL: URL, pageURL: URL?, pageTitle: String?) {
        guard let scheme = streamURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            return nil
        }

        let resolvedTitle = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostSubtitle = pageURL?.host
        let displayTitle = if let resolvedTitle, !resolvedTitle.isEmpty {
            resolvedTitle
        } else {
            streamURL.lastPathComponent.isEmpty ? "Web Video" : streamURL.lastPathComponent
        }

        playbackID = PlaybackItemID(
            sourceType: .web,
            rawID: "\(pageURL?.absoluteString ?? "unknown-page")::\(streamURL.absoluteString)"
        )
        title = displayTitle
        subtitle = hostSubtitle
        self.streamURL = streamURL
    }
}
