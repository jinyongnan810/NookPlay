//
//  ImmersivePlayerView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import AVFoundation
import RealityKit
import SwiftUI

/// The content shown inside the app's immersive playback scene.
struct ImmersivePlayerView: View {
    // MARK: Constants

    private static let playerAttachmentID = "immersive-player"
    private static let controlsAttachmentID = "immersive-controls"
    private static let playerAnchorName = "immersive-player-anchor"
    private static let controlsAnchorName = "immersive-controls-anchor"
    private static let playerWidth: CGFloat = 9600

    // MARK: Environment

    /// Shared app state that provides the active immersive player and layout metadata.
    @Environment(AppModel.self) private var appModel
    /// System action used to dismiss the immersive scene.
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    /// Window presentation action used to restore the main app window after immersive playback ends.
    @Environment(\.openWindow) private var openWindow
    /// The current scene phase for the immersive scene.
    @Environment(\.scenePhase) private var scenePhase

    // MARK: State

    @State private var showsControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isPlaying = true

    // MARK: Body

    var body: some View {
        RealityView { content, attachments in
            let playerAnchor = Entity()
            playerAnchor.name = Self.playerAnchorName
            content.add(playerAnchor)

            let controlsAnchor = Entity()
            controlsAnchor.name = Self.controlsAnchorName
            content.add(controlsAnchor)

            updatePlayerAttachment(in: playerAnchor, attachments: attachments)
            updateControlsAttachment(in: controlsAnchor, attachments: attachments)
        } update: { content, attachments in
            guard
                let playerAnchor = content.entities.first(where: { $0.name == Self.playerAnchorName }),
                let controlsAnchor = content.entities.first(where: { $0.name == Self.controlsAnchorName })
            else {
                return
            }

            updatePlayerAttachment(in: playerAnchor, attachments: attachments)
            updateControlsAttachment(in: controlsAnchor, attachments: attachments)
        } attachments: {
            if let player = appModel.immersivePlayer {
                Attachment(id: Self.playerAttachmentID) {
                    videoSurface(player: player)
                }
            }

            if showsControls {
                Attachment(id: Self.controlsAttachmentID) {
                    controlsSurface
                }
            }
        }
        .onAppear {
            appModel.immersivePlayer?.play()
            showControlsTemporarily()
        }
        .onDisappear {
            hideControlsTask?.cancel()
        }
        .task(id: appModel.immersivePlayer) {
            while !Task.isCancelled {
                await MainActor.run {
                    syncPlaybackState()
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            appModel.activePlayerViewModel?.handleScenePhaseChange(newPhase)
        }
        .preferredSurroundingsEffect(.dark)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: Helpers

    @ViewBuilder
    private func videoSurface(player: AVPlayer) -> some View {
        PlainVideoPlayer(player: player, videoGravity: .resizeAspect)
            .aspectRatio(appModel.immersiveAspectRatio, contentMode: .fit)
            .frame(width: Self.playerWidth)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleControlsVisibility()
            }
    }

    private var controlsSurface: some View {
        HStack(spacing: 16) {
            Button(action: togglePlayback) {
                Label(
                    isPlaying ? "Pause" : "Play",
                    systemImage: isPlaying ? "pause.fill" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)

            Button("Exit", systemImage: "xmark.circle") {
                Task {
                    await dismissImmersiveSpace()
                    appModel.endImmersivePlayback()
                    appModel.restoreWindowedPlayback()
                    openWindow(id: "main-window")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .font(.title)
        .foregroundStyle(.white)
        .background(.black.opacity(0.72), in: Capsule())
        .controlSize(.large)
        .onTapGesture {
            showControlsTemporarily()
        }
        .animation(.easeInOut(duration: 0.2), value: showsControls)
    }

    private func updatePlayerAttachment(in anchor: Entity, attachments: RealityViewAttachments) {
        anchor.findEntity(named: Self.playerAttachmentID)?.removeFromParent()

        guard let attachment = attachments.entity(for: Self.playerAttachmentID) else {
            return
        }

        attachment.name = Self.playerAttachmentID
        attachment.position = [0, 1.5, -1.8]
        anchor.addChild(attachment)
    }

    private func updateControlsAttachment(in anchor: Entity, attachments: RealityViewAttachments) {
        anchor.findEntity(named: Self.controlsAttachmentID)?.removeFromParent()

        guard let attachment = attachments.entity(for: Self.controlsAttachmentID) else {
            return
        }

        attachment.name = Self.controlsAttachmentID
        attachment.position = [0, 0.48, -1.35]
        anchor.addChild(attachment)
    }

    private func togglePlayback() {
        guard let player = appModel.immersivePlayer else {
            return
        }

        if isPlaying {
            player.pause()
        } else {
            player.play()
        }

        syncPlaybackState()
        showControlsTemporarily()
    }

    private func syncPlaybackState() {
        guard let player = appModel.immersivePlayer else {
            isPlaying = false
            return
        }

        isPlaying = player.rate > 0
    }

    private func toggleControlsVisibility() {
        if showsControls {
            hideControlsTask?.cancel()
            showsControls = false
        } else {
            showControlsTemporarily()
        }
    }

    private func showControlsTemporarily() {
        hideControlsTask?.cancel()
        showsControls = true
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                showsControls = false
            }
        }
    }
}
