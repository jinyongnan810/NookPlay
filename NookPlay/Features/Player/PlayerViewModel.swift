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
final class PlayerViewModel: Identifiable {
    private static let resumeCompletionThresholdSeconds: Double = 10
    private static let progressSaveIntervalSeconds: Double = 10

    let id = UUID()

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
    /// KVO observation for the player's time control status.
    @ObservationIgnored
    private var timeControlStatusObservation: NSKeyValueObservation?

    /// Indicates whether the initial resume seek has already been attempted.
    private var hasAppliedInitialResume = false
    /// The most recent playback position persisted to disk.
    private var lastSavedProgressTime: Double = 0
    /// Indicates whether player observation has already been configured.
    private var hasPreparedPlayer = false

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

//        let asset = AVURLAsset(url: mediaSource.streamURL)
//        let item = AVPlayerItem(asset: asset)
        let item = AVPlayerItem(url: mediaSource.streamURL)
        player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
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
        guard !hasPreparedPlayer else {
            player.play()
            isPlaying = true
            return
        }

        hasPreparedPlayer = true
        observePlayer()
        observeCompletion()
        player.play()
    }

    /// Toggles playback between playing and paused states.
    func togglePlayback() {
        if isPlaying {
            player.pause()
            Task {
                await saveProgress(force: true)
            }
        } else {
            player.play()
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

        Task {
            await saveProgress(force: true)
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
            await saveProgress(force: true)
        }
    }

    // MARK: Player Observation

    /// Observes the player item for readiness, presentation metadata, and time updates.
    private func observePlayer() {
        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let isPlaying = player.timeControlStatus == .playing
            Task { @MainActor [weak self, isPlaying] in
                self?.isPlaying = isPlaying
            }
        }

        statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                switch item.status {
                case .readyToPlay:
                    await self.configureVideoCompositionIfNeeded(for: item)
                    await self.debugVideoMetadata(item)
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

                self.lastSavedProgressTime = 0
                self.currentTime = self.duration
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

        let knownDuration: Double? = if duration > 0 {
            duration
        } else if let entryDuration = entry.durationSeconds, entryDuration > 0 {
            entryDuration
        } else {
            nil
        }

        if let knownDuration,
           entry.lastPositionSeconds >= knownDuration - Self.resumeCompletionThresholdSeconds
        {
            lastSavedProgressTime = 0
            await progressStore.removeResumeEntry(for: mediaSource.playbackID)
            return
        }

        let resumeTime = CMTime(seconds: entry.lastPositionSeconds, preferredTimescale: 600)
        await player.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = entry.lastPositionSeconds
        lastSavedProgressTime = entry.lastPositionSeconds
    }

    /// Saves the current playback progress for later resume.
    private func saveProgress(force: Bool = false) async {
        let currentSeconds = player.currentTime().seconds
        guard currentSeconds.isFinite, currentSeconds > 0 else {
            return
        }

        if !force, currentSeconds - lastSavedProgressTime < Self.progressSaveIntervalSeconds {
            return
        }

        let durationSeconds = player.currentItem?.duration.seconds
        let entry = ResumeEntry(
            itemID: mediaSource.playbackID,
            title: mediaSource.title,
            subtitle: mediaSource.subtitle,
            lastPositionSeconds: currentSeconds,
            durationSeconds: durationSeconds?.isFinite == true ? durationSeconds : nil,
            lastPlayedAt: .now
        )
        await progressStore.saveResumeEntry(entry)
        lastSavedProgressTime = currentSeconds
    }

    private func debugVideoMetadata(_ item: AVPlayerItem) async {
        let asset = item.asset

        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                print("=== VIDEO DEBUG ===")
                print("No video track")
                return
            }

            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let presentationSize = item.presentationSize

            let transformed = naturalSize.applying(preferredTransform)

            print("=== VIDEO DEBUG ===")
            print("url:", (asset as? AVURLAsset)?.url.absoluteString ?? "n/a")
            print("naturalSize:", naturalSize)
            print("preferredTransform:", preferredTransform)
            print("presentationSize:", presentationSize)
            print("transformedSize(abs):", CGSize(
                width: abs(transformed.width),
                height: abs(transformed.height)
            ))
            print("videoAspectRatio:", videoAspectRatio)
        } catch {
            print("=== VIDEO DEBUG ===")
            print("Failed to load video metadata:", error)
        }
    }

    private func configureVideoCompositionIfNeeded(for item: AVPlayerItem) async {
        guard item.videoComposition == nil else {
            return
        }

        do {
            item.videoComposition = try await makeVideoComposition(for: item.asset)
        } catch {
            print("=== VIDEO DEBUG ===")
            print("Failed to configure video composition:", error)
        }
    }

    private func makeVideoComposition(for asset: AVAsset) async throws -> AVVideoComposition? {
        let tracks = try await asset.loadTracks(withMediaType: .video)

        guard let sourceTrack = tracks.first else {
            return nil
        }

        let preferredTransform = try await sourceTrack.load(.preferredTransform)
        let naturalSize = try await sourceTrack.load(.naturalSize)
        let duration = try await asset.load(.duration)

        // If already upright, keep the simple path.
        if preferredTransform == .identity {
            return nil
        }

        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return nil
        }

        try compTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceTrack,
            at: .zero
        )

        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           )
        {
            try? compAudio.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioTrack,
                at: .zero
            )
        }

        var layerConfiguration = AVVideoCompositionLayerInstruction.Configuration(trackID: compTrack.trackID)
        layerConfiguration.setTransform(preferredTransform, at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfiguration)

        let instructionConfiguration = AVVideoCompositionInstruction.Configuration(
            backgroundColor: nil,
            enablePostProcessing: false,
            layerInstructions: [layerInstruction],
            requiredSourceSampleDataTrackIDs: [],
            timeRange: CMTimeRange(start: .zero, duration: duration)
        )
        let instruction = AVVideoCompositionInstruction(configuration: instructionConfiguration)

        var configuration = AVVideoComposition.Configuration()
        configuration.instructions = [instruction]
        configuration.frameDuration = CMTime(value: 1, timescale: 30)

        let transformedSize = naturalSize.applying(preferredTransform)
        configuration.renderSize = CGSize(
            width: abs(transformedSize.width),
            height: abs(transformedSize.height)
        )

        return AVVideoComposition(configuration: configuration)
    }
}
