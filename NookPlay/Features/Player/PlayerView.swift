//
//  PlayerView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import AVKit
import SwiftUI

/// The fullscreen playback screen for a selected media item.
///
/// This view intentionally delegates actual transport controls to the system
/// player UI and only manages lifecycle, error handling, and immersive entry.
struct PlayerView: View {
    // MARK: Environment

    /// Shared app state used for immersive playback handoff.
    @Environment(AppModel.self) private var appModel
    /// Dismiss action for the fullscreen player presentation.
    @Environment(\.dismiss) private var dismiss
    /// System action used to open the app's immersive playback scene.
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    /// System action used to dismiss the app's immersive playback scene.
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    /// The scene phase for the current player presentation.
    @Environment(\.scenePhase) private var scenePhase
    /// The playback state and lifecycle coordinator for this screen.
    @State private var viewModel: PlayerViewModel

    // MARK: Initialization

    /// Creates a playback screen for an existing shared playback session.
    ///
    /// - Parameter viewModel: The shared playback view model to present.
    init(viewModel: PlayerViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    /// Creates a playback screen for a specific media source.
    ///
    /// - Parameter mediaSource: The media item that should be played.
    init(mediaSource: AnyPlayableMediaSource) {
        self.init(viewModel: PlayerViewModel(mediaSource: mediaSource))
    }

    // MARK: Body

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
                SystemVideoPlayer(
                    player: viewModel.player,
                    videoGravity: .resizeAspect,
                    onWillEndFullScreenPresentation: closePlayer
                )
                .ignoresSafeArea()
            }
        }
        .immersiveEnvironmentPicker {
            Button(appModel.isImmersiveSpacePresented ? "Close Environment" : "Open Environment", systemImage: "vision.pro") {
                Task {
                    if appModel.isImmersiveSpacePresented {
                        await dismissImmersiveSpace()
                    } else {
                        _ = await openImmersiveSpace(id: "player-immersive-space")
                    }
                }
            }
        }
        .task {
            viewModel.prepare()
        }
        .onDisappear {
            viewModel.handleDisappear()
            appModel.endPlayback(for: viewModel)
            Task {
                await dismissImmersiveSpace()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(newPhase)
        }
    }

    // MARK: Helpers

    private func closePlayer() {
        viewModel.handleDisappear()
        appModel.endPlayback(for: viewModel)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        PlayerView(mediaSource: DemoMediaSource.bigBuckBunny)
    }
    .environment(AppModel())
}
