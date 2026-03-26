//
//  AppModel.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

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

    /// The current shared playback session, if one is active.
    var activePlayerViewModel: PlayerViewModel?
    /// Whether the windowed player UI should currently be presented.
    var isPlayerPresented = false
    /// Whether the immersive playback environment is currently open.
    var isImmersiveSpacePresented = false

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

    /// Starts a new shared playback session using an already-prepared player view model.
    ///
    /// - Parameter viewModel: The playback session to present.
    func presentPlayer(_ viewModel: PlayerViewModel) {
        activePlayerViewModel = viewModel
        isPlayerPresented = true
    }

    /// Updates app state to match the immersive space visibility.
    ///
    /// - Parameter isPresented: Whether the immersive playback environment is currently open.
    func setImmersiveSpacePresented(_ isPresented: Bool) {
        isImmersiveSpacePresented = isPresented
    }

    /// Ends the current shared playback session when its owning player view is dismissed.
    ///
    /// - Parameter viewModel: The player view model being dismissed.
    func endPlayback(for viewModel: PlayerViewModel) {
        guard activePlayerViewModel === viewModel else {
            return
        }

        isPlayerPresented = false
        isImmersiveSpacePresented = false
        activePlayerViewModel = nil
    }
}
