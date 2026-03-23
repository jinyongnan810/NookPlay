//
//  ImmersivePlayerView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import RealityKit
import RealityKitContent
import SwiftUI

/// The content shown inside the app's immersive playback scene.
///
/// The system docks the full-screen AVKit player into the immersive space
/// automatically. This view only provides the docking region that defines where
/// the docked player should appear.
struct ImmersivePlayerView: View {
    private static let environmentRootName = "dark-environment"

    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        RealityView { content in
            if content.entities.first(where: { $0.name == Self.environmentRootName }) == nil {
                let environmentRoot = await makeEvironment()
                environmentRoot.name = Self.environmentRootName
                content.add(environmentRoot)
            }
        }
        .onAppear {
            appModel.setImmersiveSpacePresented(true)
        }
        .onDisappear {
            appModel.setImmersiveSpacePresented(false)
        }
        .onChange(of: scenePhase) { _, newPhase in
            appModel.activePlayerViewModel?.handleScenePhaseChange(newPhase)
        }
        .persistentSystemOverlays(.hidden)
    }
}
