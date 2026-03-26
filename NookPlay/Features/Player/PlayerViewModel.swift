//
//  PlayerViewModel.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import AVFoundation
import AVKit
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
    /// Indicates whether initial player preparation work is still running.
    private(set) var isPreparing = false
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
    /// A player item that was fully prepared before the player screen was presented.
    @ObservationIgnored
    private var preparedPlayerItem: AVPlayerItem?

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
        preparedPlayerItem: AVPlayerItem? = nil,
        progressStore: PlaybackProgressStore = PlaybackProgressStore()
    ) {
        self.mediaSource = mediaSource
        self.preparedPlayerItem = preparedPlayerItem
        self.progressStore = progressStore

        player = AVPlayer()
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
    ///
    /// This is the point where the view model performs the expensive one-time setup
    /// for the current `AVPlayerItem`. That includes waiting for the item to become
    /// ready, attaching any transform-correcting `AVVideoComposition`, loading basic
    /// playback metadata, and restoring resume position.
    ///
    /// The composition graph created during this phase is retained by the player item
    /// and player while playback is active. It is not exported to disk. Once the
    /// player view model and its `AVPlayerItem` are released, ARC can release the
    /// composition objects as well.
    func prepare() async {
        guard !hasPreparedPlayer else {
            player.play()
            isPlaying = true
            return
        }

        hasPreparedPlayer = true
        isPreparing = true

        defer {
            isPreparing = false
        }

        do {
            let item = try await makePlayerItemIfNeeded()
            player.replaceCurrentItem(with: item)
            observePlayer()
            observeCompletion()

            let readyItem = try await waitUntilItemReady(item)
            await debugVideoMetadata(readyItem)
            await updateDuration(using: readyItem)
            updateAspectRatio(using: readyItem.presentationSize)
            await restoreResumePositionIfNeeded()

            guard errorMessage == nil else {
                return
            }

            player.play()
        } catch {
            errorMessage = error.localizedDescription
        }
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
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                switch item.status {
                case .readyToPlay:
                    break
                case .failed:
                    errorMessage = item.error?.localizedDescription ?? "This video could not be played."
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

    /// Waits for the current player item to become ready before running expensive setup.
    ///
    /// The view presents a loading state while this awaits readiness. Doing the work here
    /// keeps the expensive transform/composition path inside a visible preparation phase
    /// instead of triggering it after the player UI has already appeared.
    private func waitUntilItemReady(_ item: AVPlayerItem) async throws -> AVPlayerItem {
        switch item.status {
        case .readyToPlay:
            return item
        case .failed:
            throw item.error ?? NSError(
                domain: "NookPlay.PlayerViewModel",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "This video could not be played."]
            )
        case .unknown:
            return try await withCheckedThrowingContinuation { continuation in
                var readinessObservation: NSKeyValueObservation?
                readinessObservation = item.observe(\.status, options: [.new]) { item, _ in
                    switch item.status {
                    case .readyToPlay:
                        readinessObservation?.invalidate()
                        readinessObservation = nil
                        continuation.resume(returning: item)
                    case .failed:
                        let error = item.error ?? NSError(
                            domain: "NookPlay.PlayerViewModel",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "This video could not be played."]
                        )
                        readinessObservation?.invalidate()
                        readinessObservation = nil
                        continuation.resume(throwing: error)
                    default:
                        break
                    }
                }
            }
        @unknown default:
            throw NSError(
                domain: "NookPlay.PlayerViewModel",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "The selected video entered an unsupported playback state."]
            )
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

    /// Returns the already-prepared item if one exists, otherwise creates and prepares one.
    private func makePlayerItemIfNeeded() async throws -> AVPlayerItem {
        if let preparedPlayerItem {
            self.preparedPlayerItem = nil
            return preparedPlayerItem
        }

        return await Self.makePreparedPlayerItem(for: mediaSource)
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
        #if DEBUG
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
        #endif
    }

    /// Ensures the player item has a transform-correcting video composition when needed.
    ///
    /// This method is deliberately conservative:
    /// - It exits immediately if a composition is already attached.
    /// - It attempts to build a composition only after AVFoundation reports the item is ready.
    /// - It preserves playback even if composition creation fails.
    ///
    /// That behavior matters because the composition is a presentation fix, not a playback
    /// prerequisite. If the transform-correction path fails, the app still prefers to play
    /// the media rather than turning a recoverable presentation issue into a hard failure.
    private static func configureVideoCompositionIfNeeded(for item: AVPlayerItem) async {
        guard item.videoComposition == nil else {
            return
        }

        do {
            item.videoComposition = try await makeVideoComposition(for: item.asset)
            item.seekingWaitsForVideoCompositionRendering = item.videoComposition != nil
        } catch {
            print("=== VIDEO DEBUG ===")
            print("Failed to configure video composition:", error)
        }
    }

    /// Builds a configuration-based `AVVideoComposition` that applies the source track's
    /// preferred transform during playback.
    ///
    /// AVFoundation commonly stores orientation as metadata on the video track. When that
    /// metadata is non-identity, the safest way to normalize presentation is to create a
    /// composition that respects the asset's own track properties and transforms.
    ///
    /// The function returns `nil` for the no-op cases so the caller can keep the direct
    /// asset playback path:
    /// - the asset has no video track
    /// - the track transform is already `.identity`
    private static func makeVideoComposition(for asset: AVAsset) async throws -> AVVideoComposition? {
        let tracks = try await asset.loadTracks(withMediaType: .video)

        guard let sourceTrack = tracks.first else {
            return nil
        }

        let preferredTransform = try await sourceTrack.load(.preferredTransform)
        let naturalSize = try await sourceTrack.load(.naturalSize)
        // If the encoded track does not require an extra transform, avoid composition
        // overhead and keep the simpler direct-asset playback path.
        if preferredTransform == .identity {
            return nil
        }
        let videoComposition = try await AVVideoComposition.videoComposition(withPropertiesOf: asset)
        let transformedSize = naturalSize.applying(preferredTransform)
        let expectedRenderSize = CGSize(
            width: abs(transformedSize.width),
            height: abs(transformedSize.height)
        )

        // Keep the system-generated instruction graph, but normalize render size to the
        // transformed bounds we expect for rotated video.
        if videoComposition.renderSize != expectedRenderSize {
            var configuration = try await AVVideoComposition.Configuration(for: asset, prototypeInstruction: nil)
            configuration.instructions = videoComposition.instructions
            configuration.frameDuration = videoComposition.frameDuration
            configuration.renderSize = expectedRenderSize
            configuration.renderScale = videoComposition.renderScale
            configuration.sourceTrackIDForFrameTiming = videoComposition.sourceTrackIDForFrameTiming
            configuration.sourceSampleDataTrackIDs = videoComposition.sourceSampleDataTrackIDs
            configuration.spatialVideoConfigurations = videoComposition.spatialVideoConfigurations
            return AVVideoComposition(configuration: configuration)
        }

        return videoComposition
    }

    /// Creates a player item and attaches any required video composition before playback UI appears.
    static func makePreparedPlayerItem(for mediaSource: AnyPlayableMediaSource) async -> AVPlayerItem {
        let item = AVPlayerItem(asset: AVURLAsset(url: mediaSource.streamURL))
        item.externalMetadata = makeDisplayMetadata(for: mediaSource)
        await configureVideoCompositionIfNeeded(for: item)
        return item
    }

    /// Publishes display metadata that `AVPlayerViewController` can show in its transport bar.
    private static func makeDisplayMetadata(for mediaSource: AnyPlayableMediaSource) -> [AVMetadataItem] {
        var metadata: [AVMetadataItem] = [makeMetadataItem(
            identifier: .commonIdentifierTitle,
            value: mediaSource.title
        )]

        if let subtitle = mediaSource.subtitle, !subtitle.isEmpty {
            metadata.append(makeMetadataItem(
                identifier: .iTunesMetadataTrackSubTitle,
                value: subtitle
            ))
        }

        return metadata
    }

    /// Creates a mutable metadata item for system playback UI consumption.
    private static func makeMetadataItem(
        identifier: AVMetadataIdentifier,
        value: String
    ) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as? AVMetadataItem ?? item
    }
}
