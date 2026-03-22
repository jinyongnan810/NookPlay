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
    /// The current navigation path for the main window's `NavigationStack`.
    ///
    /// This stays in shared app state so feature views can trigger navigation
    /// without directly owning or rebuilding the root stack.
    var path: [AppRoute] = []

    /// The active player used by the immersive scene, when immersive playback is open.
    ///
    /// Keeping the `AVPlayer` here allows the windowed player and immersive
    /// player to hand off the same playback session instead of restarting it.
    var immersivePlayer: AVPlayer?

    /// The title associated with the current immersive playback session.
    ///
    /// This is stored alongside the immersive player so the immersive scene can
    /// present related metadata later if needed.
    var immersiveTitle: String?

    /// The aspect ratio of the media currently being shown in immersive playback.
    ///
    /// A fallback 16:9 value is used until actual presentation metadata is available.
    var immersiveAspectRatio: CGFloat = 16 / 9
    /// The current shared playback session, if one is active.
    var activePlayerViewModel: PlayerViewModel?
    /// Whether the windowed player UI should currently be presented.
    var isPlayerPresented = false

    /// Pushes a destination onto the main window's navigation path.
    ///
    /// - Parameter route: The app route to display next.
    func open(_ route: AppRoute) {
        path.append(route)
    }

    /// Starts a new shared playback session and presents the windowed player.
    ///
    /// - Parameter mediaSource: The media item to play.
    func presentPlayer(for mediaSource: AnyPlayableMediaSource) {
        activePlayerViewModel = PlayerViewModel(mediaSource: mediaSource)
        isPlayerPresented = true
    }

    /// Starts an immersive playback session using the same player as windowed playback.
    ///
    /// - Parameters:
    ///   - viewModel: The shared playback session that should continue in immersive space.
    ///   - aspectRatio: The current media aspect ratio for immersive layout.
    func beginImmersivePlayback(with viewModel: PlayerViewModel, aspectRatio: CGFloat) {
        activePlayerViewModel = viewModel
        immersivePlayer = viewModel.player
        immersiveTitle = viewModel.mediaSource.title
        immersiveAspectRatio = aspectRatio
        isPlayerPresented = false
    }

    /// Clears the current immersive playback state.
    ///
    /// This resets only the app-level immersive presentation model; it does not
    /// destroy the underlying playback feature objects directly.
    func endImmersivePlayback() {
        immersivePlayer = nil
        immersiveTitle = nil
        immersiveAspectRatio = 16 / 9
    }

    /// Restores the shared playback session into the windowed player UI.
    func restoreWindowedPlayback() {
        guard activePlayerViewModel != nil else {
            return
        }

        isPlayerPresented = true
    }

    /// Ends the current shared playback session when its owning player view is dismissed.
    ///
    /// - Parameter viewModel: The player view model being dismissed.
    func endPlayback(for viewModel: PlayerViewModel) {
        guard activePlayerViewModel === viewModel else {
            return
        }

        isPlayerPresented = false
        activePlayerViewModel = nil
        endImmersivePlayback()
    }
}
