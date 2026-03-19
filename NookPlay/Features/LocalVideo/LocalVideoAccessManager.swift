//
//  LocalVideoAccessManager.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

/// Coordinates access to locally imported video files.
///
/// The manager turns a security-scoped file URL from `fileImporter` into a
/// playback-ready model that the shared player can consume.
actor LocalVideoAccessManager {
    /// The temporary subdirectory used for copied photo-library playback files.
    private static let temporaryPlaybackDirectoryName = "LocalPlaybackCache"

    // MARK: File Preparation

    /// Converts an imported file URL into a playable local media model.
    ///
    /// - Parameter url: The security-scoped file URL returned by `fileImporter`.
    /// - Returns: A playable local media model that keeps file access alive.
    /// - Throws: `LocalVideoAccessError` if the selected file can't be accessed.
    @MainActor
    func importPlayableMedia(from url: URL) throws -> LocalPlayableMedia {
        let accessSession = try SecurityScopedAccess(url: url)
        return Self.makePlayableMedia(from: url, accessSession: accessSession)
    }

    /// Converts an app-accessible local file URL into a playable local media model.
    ///
    /// This path is used for media copied into the app sandbox, such as videos
    /// imported from the photo library through `PhotosPicker`.
    ///
    /// - Parameters:
    ///   - url: The local file URL that the app can already read directly.
    ///   - title: An optional display title override.
    ///   - subtitle: An optional display subtitle override.
    /// - Returns: A playable local media model for the provided file URL.
    func makePlayableMedia(
        from url: URL,
        title: String? = nil,
        subtitle: String? = nil,
        playbackIDRawValue: String? = nil,
        playbackLifetime: PlaybackLifetimeResource? = nil
    ) -> LocalPlayableMedia {
        Self.makePlayableMedia(
            from: url,
            title: title,
            subtitle: subtitle,
            playbackIDRawValue: playbackIDRawValue,
            accessSession: nil,
            playbackLifetime: playbackLifetime
        )
    }

    /// Builds a local media model from a file URL and optional access session.
    private static func makePlayableMedia(
        from url: URL,
        title: String? = nil,
        subtitle: String? = nil,
        playbackIDRawValue: String? = nil,
        accessSession: SecurityScopedAccess?,
        playbackLifetime: PlaybackLifetimeResource? = nil
    ) -> LocalPlayableMedia {
        let standardizedURL = url.standardizedFileURL
        let resolvedTitle = title ?? standardizedURL.deletingPathExtension().lastPathComponent
        let resolvedSubtitle = subtitle ?? standardizedURL.lastPathComponent

        let playbackID = PlaybackItemID(
            sourceType: .local,
            rawID: playbackIDRawValue ?? standardizedURL.path
        )

        return LocalPlayableMedia(
            playbackID: playbackID,
            title: resolvedTitle,
            subtitle: resolvedSubtitle,
            streamURL: standardizedURL,
            accessSession: accessSession,
            playbackLifetime: playbackLifetime
        )
    }

    // MARK: Temporary Playback Storage

    /// Returns the dedicated temporary directory for copied playback files.
    ///
    /// The directory is created on demand so launch-time cleanup and on-import
    /// copying can share the same storage location.
    static func temporaryPlaybackDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(temporaryPlaybackDirectoryName, isDirectory: true)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        return directoryURL
    }

    /// Deletes stale copied playback files left behind by interrupted app sessions.
    ///
    /// This is safe to run on app launch because the directory is used only for
    /// disposable copies made from the photo library import flow.
    static func removeStaleTemporaryPlaybackFiles() {
        do {
            let directoryURL = try temporaryPlaybackDirectory()
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )

            for fileURL in fileURLs {
                try? FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            // Best-effort cleanup only. Playback can still proceed without failing launch.
        }
    }
}

/// Holds an active security-scoped file access session for a local file.
final class SecurityScopedAccess {
    /// The file URL associated with this access session.
    let url: URL
    /// Indicates whether `startAccessingSecurityScopedResource()` succeeded.
    private let isAccessing: Bool

    /// Starts security-scoped access for the given file URL.
    ///
    /// - Parameter url: The file URL returned by the importer.
    /// - Throws: `LocalVideoAccessError.couldNotAccessFile` if access fails.
    init(url: URL) throws {
        self.url = url
        isAccessing = url.startAccessingSecurityScopedResource()

        if !isAccessing {
            throw LocalVideoAccessError.couldNotAccessFile
        }
    }

    /// Stops security-scoped access when the session is deallocated.
    deinit {
        guard isAccessing else {
            return
        }

        url.stopAccessingSecurityScopedResource()
    }
}

extension SecurityScopedAccess: PlaybackLifetimeResource {}

/// Deletes a temporary imported file when playback no longer needs it.
final class TemporaryPlaybackFile: PlaybackLifetimeResource {
    /// The file URL that should be deleted when the resource is released.
    private let url: URL

    /// Creates a temporary playback file cleanup token.
    ///
    /// - Parameter url: The copied file URL to delete later.
    init(url: URL) {
        self.url = url
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
        print("[LocalVideoAccessManager] Deleted temporary playback file at \(url.path)")
    }
}

/// Errors produced while preparing local file playback.
enum LocalVideoAccessError: LocalizedError {
    /// The selected local file couldn't be opened through security-scoped access.
    case couldNotAccessFile

    /// A user-facing description of the access failure.
    var errorDescription: String? {
        switch self {
        case .couldNotAccessFile:
            "NookPlay couldn’t access the selected file."
        }
    }
}
