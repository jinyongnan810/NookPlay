//
//  PlayerView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import AVKit
import SwiftUI

struct PlayerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: PlayerViewModel

    init(mediaSource: AnyPlayableMediaSource) {
        _viewModel = State(initialValue: PlayerViewModel(mediaSource: mediaSource))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView {
                    Label("Playback Error", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(errorMessage)
                }
                .foregroundStyle(.white)
            } else {
                SystemVideoPlayer(player: viewModel.player, videoGravity: .resizeAspect)
                    .ignoresSafeArea()
            }
        }
        .immersiveEnvironmentPicker {
            Button("Immersive Theater", systemImage: "vision.pro") {
                Task {
                    appModel.beginImmersivePlayback(
                        player: viewModel.player,
                        title: viewModel.mediaSource.title,
                        aspectRatio: viewModel.videoAspectRatio
                    )
                    _ = await openImmersiveSpace(id: "player-immersive-space")
                }
            }

            Button("Exit Immersive", systemImage: "xmark.circle") {
                Task {
                    await dismissImmersiveSpace()
                    appModel.endImmersivePlayback()
                }
            }
            .disabled(appModel.immersivePlayer == nil)
        }
        .task {
            viewModel.prepare()
        }
        .onDisappear {
            viewModel.handleDisappear()
            Task {
                await dismissImmersiveSpace()
                appModel.endImmersivePlayback()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(newPhase)
        }
    }
}

#Preview {
    NavigationStack {
        PlayerView(mediaSource: DemoMediaSource.bigBuckBunny)
    }
}
