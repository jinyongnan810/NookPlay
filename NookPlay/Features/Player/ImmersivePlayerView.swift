//
//  ImmersivePlayerView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import AVFoundation
import SwiftUI

struct ImmersivePlayerView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let player = appModel.immersivePlayer {
                SystemVideoPlayer(player: player, videoGravity: .resizeAspect)
                    .aspectRatio(appModel.immersiveAspectRatio, contentMode: .fit)
                    .frame(width: 1600)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 30)
            }
        }
        .preferredSurroundingsEffect(.dark)
        .persistentSystemOverlays(.hidden)
    }
}
