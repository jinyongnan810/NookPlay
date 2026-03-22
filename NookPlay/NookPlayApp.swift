//
//  NookPlayApp.swift
//  NookPlay
//
//  Created by Yuunan kin on 2026/03/19.
//

import SwiftUI

@main
struct NookPlayApp: App {
    private static let mainWindowID = "main-window"

    // MARK: State

    /// Shared app state injected into both the main window and immersive scene.
    @State private var appModel = AppModel()

    /// The currently selected immersion style for the app's immersive playback scene.
    @State private var immersionStyle: ImmersionStyle = .full

    init() {
        LocalVideoAccessManager.removeStaleTemporaryPlaybackFiles()
    }

    // MARK: Scenes

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            ContentView()
                .environment(appModel)
        }
        // TODO: Revisit minimum window sizing on visionOS. The current runtime
        // doesn't appear to honor the attempted SwiftUI and UIKit minimum-size
        // constraints for this regular window, so the home layout should remain
        // resilient when the window is manually shrunk.

        ImmersiveSpace(id: "player-immersive-space") {
            ImmersivePlayerView()
                .environment(appModel)
        }
        .immersionStyle(selection: $immersionStyle, in: .full)
        .upperLimbVisibility(.visible)
        .persistentSystemOverlays(.hidden)
    }
}
