//
//  PlaybackItemID.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

struct PlaybackItemID: Hashable, Codable, Sendable {
    let sourceType: PlaybackSourceType
    let rawID: String

    nonisolated var storageKey: String {
        "\(sourceType.rawValue)::\(rawID)"
    }
}
