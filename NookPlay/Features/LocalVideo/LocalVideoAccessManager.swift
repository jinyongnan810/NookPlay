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
    /// Converts an imported file URL into a playable local media model.
    ///
    /// - Parameter url: The security-scoped file URL returned by `fileImporter`.
    /// - Returns: A playable local media model that keeps file access alive.
    /// - Throws: `LocalVideoAccessError` if the selected file can't be accessed.
    @MainActor
    func importPlayableMedia(from url: URL) throws -> LocalPlayableMedia {
        let accessSession = try SecurityScopedAccess(url: url)

        let playbackID = PlaybackItemID(
            sourceType: .local,
            rawID: url.standardizedFileURL.path
        )

        return LocalPlayableMedia(
            playbackID: playbackID,
            title: url.deletingPathExtension().lastPathComponent,
            subtitle: url.lastPathComponent,
            streamURL: url,
            accessSession: accessSession
        )
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
