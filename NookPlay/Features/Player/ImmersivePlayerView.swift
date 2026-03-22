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
    private static let playerWidth: CGFloat = 7200
    private static let playerDistance: Float = -1.25
    private static let controlsDistance: Float = -1.05

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
    @State private var sliderTime: Double = 0
    @State private var isScrubbing = false
    @State private var isSliderHovered = false

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
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.55), radius: 42)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleControlsVisibility()
            }
    }

    private var controlsSurface: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let title = appModel.immersiveTitle {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
            }

            HStack(spacing: 18) {
                Button {
                    Task {
                        await dismissImmersiveSpace()
                        appModel.endImmersivePlayback()
                        appModel.restoreWindowedPlayback()
                        openWindow(id: "main-window")
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)

                buttonIcon(systemName: "gobackward.15", action: {
                    seekBy(delta: -15)
                })
                buttonIcon(systemName: isPlaying ? "pause.fill" : "play.fill", action: togglePlayback)
                buttonIcon(systemName: "goforward.15", action: {
                    seekBy(delta: 15)
                })

                ZStack(alignment: .top) {
                    Slider(
                        value: playbackTimeBinding,
                        in: 0 ... sliderUpperBound,
                        onEditingChanged: handleSliderEditingChanged
                    )
                    .onHover { isHovered in
                        isSliderHovered = isHovered
                    }
                    .padding(.vertical, 18)

                    if showsSliderTimestamp {
                        Text(formattedTime(sliderPreviewTime))
                            .font(.headline.monospacedDigit())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.82), in: Capsule())
                            .offset(y: -28)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(.white.opacity(0.08), in: Capsule())
        }
        .frame(width: 1600)
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .font(.title2)
        .foregroundStyle(.white)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
        attachment.position = [0, 1.5, Self.playerDistance]
        anchor.addChild(attachment)
    }

    private func updateControlsAttachment(in anchor: Entity, attachments: RealityViewAttachments) {
        anchor.findEntity(named: Self.controlsAttachmentID)?.removeFromParent()

        guard let attachment = attachments.entity(for: Self.controlsAttachmentID) else {
            return
        }

        attachment.name = Self.controlsAttachmentID
        attachment.position = [0, 0.44, Self.controlsDistance]
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
            sliderTime = 0
            return
        }

        isPlaying = player.rate > 0

        guard let viewModel = appModel.activePlayerViewModel else {
            let playerTime = player.currentTime().seconds
            if playerTime.isFinite, !isScrubbing {
                sliderTime = playerTime
            }
            return
        }

        if !isScrubbing {
            sliderTime = viewModel.currentTime
        }
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

    private var playbackTimeBinding: Binding<Double> {
        Binding(
            get: {
                isScrubbing ? sliderTime : currentPlaybackTime
            },
            set: { newValue in
                sliderTime = newValue
                seek(to: newValue)
            }
        )
    }

    private var currentPlaybackTime: Double {
        guard let viewModel = appModel.activePlayerViewModel else {
            return sliderTime
        }

        return min(max(isScrubbing ? sliderTime : viewModel.currentTime, 0), sliderUpperBound)
    }

    private var playbackDuration: Double {
        guard let duration = appModel.activePlayerViewModel?.duration, duration.isFinite else {
            return 0
        }

        return max(duration, 0)
    }

    private var sliderUpperBound: Double {
        max(playbackDuration, 1)
    }

    private func handleSliderEditingChanged(_ isEditing: Bool) {
        isScrubbing = isEditing

        if isEditing {
            hideControlsTask?.cancel()
            showsControls = true
        } else {
            seek(to: sliderTime)
            showControlsTemporarily()
        }
    }

    private func seek(to seconds: Double) {
        let clampedSeconds = min(max(seconds, 0), playbackDuration)
        sliderTime = clampedSeconds
        appModel.activePlayerViewModel?.seek(to: clampedSeconds)
    }

    private func seekBy(delta: Double) {
        seek(to: currentPlaybackTime + delta)
        showControlsTemporarily()
    }

    private func formattedTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.isFinite ? max(seconds, 0) : 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    @ViewBuilder
    private func buttonIcon(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.16), in: Circle())
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
    }

    private var showsSliderTimestamp: Bool {
        isScrubbing || isSliderHovered
    }

    private var sliderPreviewTime: Double {
        isScrubbing ? sliderTime : currentPlaybackTime
    }
}
