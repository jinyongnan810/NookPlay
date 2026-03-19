//
//  SystemVideoPlayer.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import AVFoundation
import AVKit
import SwiftUI

struct SystemVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity

    func makeUIViewController(context _: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = videoGravity
        controller.view.backgroundColor = .black
        controller.updatesNowPlayingInfoCenter = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context _: Context) {
        if controller.player !== player {
            controller.player = player
        }

        if controller.videoGravity != videoGravity {
            controller.videoGravity = videoGravity
        }
    }
}
