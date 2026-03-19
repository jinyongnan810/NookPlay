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
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var errorMessage: String?
    private(set) var videoAspectRatio: CGFloat = 16 / 9

    let player: AVPlayer
    let mediaSource: AnyPlayableMediaSource

    @ObservationIgnored
    private let progressStore: PlaybackProgressStore
    @ObservationIgnored
    private var timeObserverToken: Any?
    @ObservationIgnored
    private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored
    private var presentationSizeObservation: NSKeyValueObservation?
    @ObservationIgnored
    private var endObserver: NSObjectProtocol?
    private var hasAppliedInitialResume = false

    init(
        mediaSource: AnyPlayableMediaSource,
        progressStore: PlaybackProgressStore = PlaybackProgressStore()
    ) {
        self.mediaSource = mediaSource
        self.progressStore = progressStore
        player = AVPlayer(url: mediaSource.streamURL)
    }

    deinit {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func prepare() {
        observePlayer()
        observeCompletion()
        player.play()
        isPlaying = true
    }

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

    func seek(to seconds: Double) {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    func handleDisappear() {
        player.pause()
        isPlaying = false

        Task {
            await saveProgress()
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase != .active else {
            return
        }

        Task {
            await saveProgress()
        }
    }

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

    var preferredWindowSize: CGSize {
        let baseHeight: CGFloat = 720
        let clampedAspectRatio = max(videoAspectRatio, 0.5)
        let width = max(640, min(1600, baseHeight * clampedAspectRatio))
        return CGSize(width: width, height: baseHeight)
    }

    private func updateDuration(using item: AVPlayerItem) async {
        do {
            let loadedDuration = try await item.asset.load(.duration)
            duration = loadedDuration.seconds.isFinite ? loadedDuration.seconds : 0
        } catch {
            duration = 0
        }
    }

    private func updateAspectRatio(using presentationSize: CGSize) {
        guard presentationSize.width > 0, presentationSize.height > 0 else {
            return
        }

        videoAspectRatio = presentationSize.width / presentationSize.height
    }

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
