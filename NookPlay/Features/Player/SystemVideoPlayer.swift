//
//  SystemVideoPlayer.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import AVFoundation
import AVKit
import SwiftUI

/// A SwiftUI wrapper around `AVPlayerViewController`.
///
/// This is the native system media player on visionOS, so using it preserves
/// expected controls, fullscreen behavior, and immersive affordances.
struct SystemVideoPlayer: UIViewControllerRepresentable {
    // MARK: Properties

    /// The player instance that the system player view controller should present.
    let player: AVPlayer
    /// The gravity used to display video content inside the player view controller.
    let videoGravity: AVLayerVideoGravity

    // MARK: UIViewControllerRepresentable

    /// Creates the underlying `AVPlayerViewController`.
    ///
    /// - Parameter context: The representable context from SwiftUI.
    /// - Returns: A configured system player view controller.
    func makeUIViewController(context _: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player

        controller.showsPlaybackControls = true
        controller.videoGravity = videoGravity
        controller.view.backgroundColor = .black
        controller.updatesNowPlayingInfoCenter = true
        return controller
    }

    /// Updates the underlying system player view controller when SwiftUI state changes.
    ///
    /// - Parameters:
    ///   - controller: The existing player view controller instance.
    ///   - context: The representable context from SwiftUI.
    func updateUIViewController(_ controller: AVPlayerViewController, context _: Context) {
        if controller.player !== player {
            controller.player = player
        }

        if controller.videoGravity != videoGravity {
            controller.videoGravity = videoGravity
        }
    }
}
