//
//  PlayerViewModel.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import AVFoundation
import CoreGraphics
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class PlayerViewModel {
    // MARK: Observable State

    /// The most recently observed playback time in seconds.
    private(set) var currentTime: Double = 0
    /// The loaded duration of the current item in seconds.
    private(set) var duration: Double = 0
    /// Indicates whether the player is currently playing.
    private(set) var isPlaying = false
    /// A user-facing playback error, if one occurred.
    private(set) var errorMessage: String?
    /// The aspect ratio of the presented video content.
    private(set) var videoAspectRatio: CGFloat = 16 / 9

    /// The underlying AVPlayer used for playback.
    let player: AVPlayer
    /// The media item that this view model is responsible for playing.
    let mediaSource: AnyPlayableMediaSource

    // MARK: Private Dependencies

    /// The persistence layer used to store and restore resume progress.
    @ObservationIgnored
    private let progressStore: PlaybackProgressStore
    /// The token for the periodic time observer attached to the player.
    @ObservationIgnored
    private var timeObserverToken: Any?
    /// KVO observation for the current item's playback readiness.
    @ObservationIgnored
    private var statusObservation: NSKeyValueObservation?
    /// KVO observation for the current item's presentation size.
    @ObservationIgnored
    private var presentationSizeObservation: NSKeyValueObservation?
    /// Notification token for playback completion events.
    @ObservationIgnored
    private var endObserver: NSObjectProtocol?

    /// Indicates whether the initial resume seek has already been attempted.
    private var hasAppliedInitialResume = false

    // MARK: Initialization

    /// Creates a player view model for a given media item.
    ///
    /// - Parameters:
    ///   - mediaSource: The media item to play.
    ///   - progressStore: The persistence store for resume data.
    init(
        mediaSource: AnyPlayableMediaSource,
        progressStore: PlaybackProgressStore = PlaybackProgressStore()
    ) {
        self.mediaSource = mediaSource
        self.progressStore = progressStore
        player = AVPlayer(url: mediaSource.streamURL)
    }

    // MARK: Lifecycle

    /// Cleans up player observation when the view model is released.
    deinit {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: Public Actions

    /// Prepares the player for presentation and starts playback.
    func prepare() {
        observePlayer()
        observeCompletion()
        player.play()
        isPlaying = true
    }

    /// Toggles playback between playing and paused states.
    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
            Task {
                await saveProgress()
            }
        } else {
            player.play()
            isPlaying = true
        }
    }

    /// Seeks playback to a specific timestamp.
    ///
    /// - Parameter seconds: The destination time in seconds.
    func seek(to seconds: Double) {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    /// Handles cleanup when the player screen disappears.
    func handleDisappear() {
        player.pause()
        isPlaying = false

        Task {
            await saveProgress()
        }
    }

    /// Responds to scene phase changes to preserve playback progress.
    ///
    /// - Parameter phase: The new scene phase for the player screen.
    func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase != .active else {
            return
        }

        Task {
            await saveProgress()
        }
    }

    // MARK: Player Observation

    /// Observes the player item for readiness, presentation metadata, and time updates.
    private func observePlayer() {
        statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                switch item.status {
                case .readyToPlay:
                    await self.updateDuration(using: item)
                    self.updateAspectRatio(using: item.presentationSize)
                    await self.restoreResumePositionIfNeeded()
                case .failed:
                    self.errorMessage = item.error?.localizedDescription ?? "This video could not be played."
                default:
                    break
                }
            }
        }

        presentationSizeObservation = player.currentItem?.observe(\.presentationSize, options: [.initial, .new]) { [weak self] item, _ in
            guard let model = self else {
                return
            }

            let presentationSize = item.presentationSize
            Task { @MainActor [model, presentationSize] in
                model.updateAspectRatio(using: presentationSize)
            }
        }

        let interval = CMTime(seconds: 2, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                await self.saveProgress()
            }
        }
    }

    /// Observes playback completion so resume data can be cleared at the end.
    private func observeCompletion() {
        guard let item = player.currentItem else {
            return
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isPlaying = false
                await self.progressStore.removeResumeEntry(for: self.mediaSource.playbackID)
            }
        }
    }

    // MARK: Derived Values

    /// A preferred window size derived from the current video aspect ratio.
    ///
    /// This remains useful as layout metadata even though the fullscreen system
    /// player now owns most of the active presentation behavior.
    var preferredWindowSize: CGSize {
        let baseHeight: CGFloat = 720
        let clampedAspectRatio = max(videoAspectRatio, 0.5)
        let width = max(640, min(1600, baseHeight * clampedAspectRatio))
        return CGSize(width: width, height: baseHeight)
    }

    // MARK: Metadata Updates

    /// Loads the duration metadata from the current player item.
    ///
    /// - Parameter item: The player item whose duration should be loaded.
    private func updateDuration(using item: AVPlayerItem) async {
        do {
            let loadedDuration = try await item.asset.load(.duration)
            duration = loadedDuration.seconds.isFinite ? loadedDuration.seconds : 0
        } catch {
            duration = 0
        }
    }

    /// Updates the cached aspect ratio from a presentation size.
    ///
    /// - Parameter presentationSize: The rendered size reported by the player item.
    private func updateAspectRatio(using presentationSize: CGSize) {
        guard presentationSize.width > 0, presentationSize.height > 0 else {
            return
        }

        videoAspectRatio = presentationSize.width / presentationSize.height
    }

    // MARK: Resume Persistence

    /// Restores the saved playback position for the current media item, if available.
    private func restoreResumePositionIfNeeded() async {
        guard !hasAppliedInitialResume else {
            return
        }

        hasAppliedInitialResume = true

        guard let entry = await progressStore.loadResumeEntry(for: mediaSource.playbackID),
              entry.lastPositionSeconds > 0
        else {
            return
        }

        let resumeTime = CMTime(seconds: entry.lastPositionSeconds, preferredTimescale: 600)
        await player.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = entry.lastPositionSeconds
    }

    /// Saves the current playback progress for later resume.
    private func saveProgress() async {
        let currentSeconds = player.currentTime().seconds
        guard currentSeconds.isFinite, currentSeconds > 0 else {
            return
        }

        let durationSeconds = player.currentItem?.duration.seconds
        let entry = ResumeEntry(
            itemID: mediaSource.playbackID,
            lastPositionSeconds: currentSeconds,
            durationSeconds: durationSeconds?.isFinite == true ? durationSeconds : nil,
            lastPlayedAt: .now
        )
        await progressStore.saveResumeEntry(entry)
    }
}
