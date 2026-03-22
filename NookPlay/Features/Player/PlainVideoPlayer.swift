//
//  PlainVideoPlayer.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import AVFoundation
import SwiftUI
import UIKit

/// A minimal video renderer backed directly by `AVPlayerLayer`.
struct PlainVideoPlayer: UIViewRepresentable {
    /// The player that provides the video frames.
    let player: AVPlayer
    /// The gravity used by the underlying player layer.
    let videoGravity: AVLayerVideoGravity

    func makeUIView(context _: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context _: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }

        if view.playerLayer.videoGravity != videoGravity {
            view.playerLayer.videoGravity = videoGravity
        }
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
