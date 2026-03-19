//
//  LocalVideoAccessManager.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

actor LocalVideoAccessManager {
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

final class SecurityScopedAccess {
    let url: URL
    private let isAccessing: Bool

    init(url: URL) throws {
        self.url = url
        isAccessing = url.startAccessingSecurityScopedResource()

        if !isAccessing {
            throw LocalVideoAccessError.couldNotAccessFile
        }
    }

    deinit {
        guard isAccessing else {
            return
        }

        url.stopAccessingSecurityScopedResource()
    }
}

enum LocalVideoAccessError: LocalizedError {
    case couldNotAccessFile

    var errorDescription: String? {
        switch self {
        case .couldNotAccessFile:
            "NookPlay couldn’t access the selected file."
        }
    }
}
