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

    /// Pushes a destination onto the main window's navigation path.
    ///
    /// - Parameter route: The app route to display next.
    func open(_ route: AppRoute) {
        path.append(route)
    }

    /// Starts an immersive playback session using the same player as windowed playback.
    ///
    /// - Parameters:
    ///   - player: The shared player instance that should continue playing in immersive space.
    ///   - title: The user-facing title for the current media item.
    ///   - aspectRatio: The current media aspect ratio for immersive layout.
    func beginImmersivePlayback(player: AVPlayer, title: String, aspectRatio: CGFloat) {
        immersivePlayer = player
        immersiveTitle = title
        immersiveAspectRatio = aspectRatio
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
}
