//
//  ImmersivePlayerView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import RealityKit
import SwiftUI

/// The content shown inside the app's immersive playback scene.
///
/// The system docks the full-screen AVKit player into the immersive space
/// automatically. This view only provides the docking region that defines where
/// the docked player should appear.
struct ImmersivePlayerView: View {
    private static let dockingAnchorName = "immersive-player-dock"
    private static let dockingWidth: Float = 8.5
    private static let dockingPosition = SIMD3<Float>(0, 2.35, -10.2)

    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        RealityView { content in
            guard content.entities.first(where: { $0.name == Self.dockingAnchorName }) == nil else {
                return
            }

            let dockingAnchor = Entity()
            dockingAnchor.name = Self.dockingAnchorName
            dockingAnchor.position = Self.dockingPosition

            var dockingRegion = DockingRegionComponent()
            dockingRegion.width = Self.dockingWidth
            dockingAnchor.components.set(dockingRegion)

            content.add(dockingAnchor)
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
        .preferredSurroundingsEffect(.dark)
        .persistentSystemOverlays(.hidden)
    }
}
