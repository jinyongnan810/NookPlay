//
//  AppModel.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import AVFoundation
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var path: [AppRoute] = []
    var immersivePlayer: AVPlayer?
    var immersiveTitle: String?
    var immersiveAspectRatio: CGFloat = 16 / 9

    func open(_ route: AppRoute) {
        path.append(route)
    }

    func beginImmersivePlayback(player: AVPlayer, title: String, aspectRatio: CGFloat) {
        immersivePlayer = player
        immersiveTitle = title
        immersiveAspectRatio = aspectRatio
    }

    func endImmersivePlayback() {
        immersivePlayer = nil
        immersiveTitle = nil
        immersiveAspectRatio = 16 / 9
    }
}
