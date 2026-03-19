//
//  ResumeEntry.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

struct ResumeEntry: Codable, Sendable {
    let itemID: PlaybackItemID
    var lastPositionSeconds: Double
    var durationSeconds: Double?
    var lastPlayedAt: Date
}
