//
//  DemoMediaSource.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

enum DemoMediaSource {
    static let bigBuckBunny = AnyPlayableMediaSource(
        playbackID: PlaybackItemID(
            sourceType: .local,
            rawID: "demo-big-buck-bunny"
        ),
        title: "Sample Playback",
        subtitle: "Temporary source for player foundation work.",
        streamURL: URL(string: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4")!,
        accessSession: nil
    )
}
