//
//  LocalVideoPickerView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The local video entry flow.
///
/// This screen lets the user pick a video file from Files/iCloud and immediately
/// presents playback when the import succeeds.
struct LocalVideoPickerView: View {
    /// The movie content types that the system importer should expose.
    ///
    /// `AVPlayer` supports more than the previous `.mp4`-only filter, so the file
    /// picker now accepts general movie content and lets AVFoundation validate the
    /// specific encoding at playback time.
    private static let supportedVideoContentTypes: [UTType] = [.movie]
    /// The strategy used when importing videos from the photo library.
    ///
    /// Switch this between `.copyToTemporaryFile` and `.useImportedFileDirectly`
    /// when testing real-device behavior.
    private static let photoLibraryImportMode: PhotoLibraryImportMode = .copyToTemporaryFile

    // MARK: State

    /// The helper that converts imported file URLs into playable media.
    @State private var accessManager = LocalVideoAccessManager()
    /// Controls presentation of the SwiftUI file importer.
    @State private var isImporterPresented = false
    /// Controls presentation of the system photo library picker.
    @State private var isPhotosPickerPresented = false
    /// Tracks whether the app is currently processing the selected file.
    @State private var isImporting = false
    /// The selected photo library item awaiting import.
    @State private var selectedPhotoItem: PhotosPickerItem?

    /// The currently imported media source, if import succeeded.
    ///
    /// When this becomes non-`nil`, the view presents the fullscreen player.
    @State private var importedMediaSource: AnyPlayableMediaSource?
    /// The latest user-facing import error, if any.
    @State private var importErrorMessage: String?

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ContentUnavailableView {
                Label("Local Video", systemImage: "film.stack")
            } description: {
                Text("Choose a supported video from Files, iCloud, or Photos to play it in NookPlay.")
            } actions: {
                Button("Choose from Files") {
                    importErrorMessage = nil
                    isImporterPresented = true
                }
                .buttonStyle(.borderedProminent)

                Button("Choose from Photos") {
                    importErrorMessage = nil
                    isPhotosPickerPresented = true
                }

                if isImporting {
                    ProgressView()
                        .controlSize(.large)
                        .padding(.top, 8)
                }
            }

            if let importErrorMessage {
                Text(importErrorMessage)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
            }
        }
        .navigationTitle("Local Video")
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: Self.supportedVideoContentTypes,
            onCompletion: handleImportResult
        )
        .photosPicker(
            isPresented: $isPhotosPickerPresented,
            selection: $selectedPhotoItem,
            matching: .videos,
            preferredItemEncoding: .current
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else {
                return
            }

            importErrorMessage = nil
            isImporting = true

            Task {
                await importPhotoLibraryItem(newItem)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { importedMediaSource != nil },
                set: { isPresented in
                    if !isPresented {
                        importedMediaSource = nil
                    }
                }
            )
        ) {
            if let importedMediaSource {
                PlayerView(mediaSource: importedMediaSource)
            }
        }
    }

    // MARK: Actions

    /// Handles the result from the system file importer.
    ///
    /// - Parameter result: The URL chosen by the user, or an import error.
    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            isImporting = true

            Task {
                do {
                    let media = try await MainActor.run {
                        try accessManager.importPlayableMedia(from: url)
                    }

                    await MainActor.run {
                        importedMediaSource = media.asMediaSource
                        isImporting = false
                    }
                } catch {
                    await MainActor.run {
                        importErrorMessage = error.localizedDescription
                        isImporting = false
                    }
                }
            }
        case let .failure(error):
            importErrorMessage = error.localizedDescription
            isImporting = false
        }
    }

    /// Loads a selected video from the user's photo library into local playback.
    ///
    /// - Parameter item: The selected photo library item.
    @MainActor
    private func importPhotoLibraryItem(_ item: PhotosPickerItem) async {
        defer {
            selectedPhotoItem = nil
        }

        do {
            guard let importedMovie = try await item.loadTransferable(type: ImportedMovieFile.self) else {
                importErrorMessage = "NookPlay couldn’t load the selected photo library video."
                isImporting = false
                return
            }

            let playbackIDRawValue = item.itemIdentifier ?? importedMovie.playbackIDRawValue
            let resolvedMovie = ImportedMovieFile(
                fileURL: importedMovie.fileURL,
                filename: importedMovie.filename,
                playbackIDRawValue: playbackIDRawValue
            )

            let preparedMovie = try preparePhotoLibraryMovie(resolvedMovie)
            let media = await accessManager.makePlayableMedia(
                from: preparedMovie.fileURL,
                title: preparedMovie.displayTitle,
                subtitle: preparedMovie.filename,
                playbackIDRawValue: preparedMovie.playbackIDRawValue,
                playbackLifetime: preparedMovie.playbackLifetime
            )

            importedMediaSource = media.asMediaSource
            isImporting = false
        } catch {
            importErrorMessage = error.localizedDescription
            isImporting = false
        }
    }

    /// Prepares a transferred photo-library movie for playback using the configured import mode.
    ///
    /// - Parameter movie: The transferred movie file metadata.
    /// - Returns: A playback-ready movie reference and optional cleanup resource.
    /// - Throws: Any file-system error encountered while preparing the movie.
    private func preparePhotoLibraryMovie(_ movie: ImportedMovieFile) throws -> PreparedPhotoLibraryMovie {
        switch Self.photoLibraryImportMode {
        case .copyToTemporaryFile:
            let copiedURL = try LocalVideoAccessManager.temporaryPlaybackDirectory()
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(movie.fileURL.pathExtension)

            try FileManager.default.copyItem(at: movie.fileURL, to: copiedURL)

            return PreparedPhotoLibraryMovie(
                fileURL: copiedURL,
                filename: movie.filename,
                playbackIDRawValue: movie.playbackIDRawValue,
                playbackLifetime: TemporaryPlaybackFile(url: copiedURL)
            )

        case .useImportedFileDirectly:
            return PreparedPhotoLibraryMovie(
                fileURL: movie.fileURL,
                filename: movie.filename,
                playbackIDRawValue: movie.playbackIDRawValue,
                playbackLifetime: nil
            )
        }
    }
}

/// The import mode used for videos selected from the user's photo library.
private enum PhotoLibraryImportMode {
    /// Copies the transferred file into app-owned temporary storage.
    case copyToTemporaryFile
    /// Uses the transferred file URL directly without making an app-local copy.
    ///
    /// This is useful for device testing, but the imported file lifetime may prove
    /// shorter or less stable than the copied-file path.
    case useImportedFileDirectly
}

/// A prepared photo-library movie ready to enter the playback pipeline.
private struct PreparedPhotoLibraryMovie {
    /// The file URL that `AVPlayer` should open.
    let fileURL: URL
    /// The original filename reported by the picker.
    let filename: String
    /// The stable playback identifier used for resume persistence.
    let playbackIDRawValue: String
    /// An optional retained resource that should live for the duration of playback.
    let playbackLifetime: PlaybackLifetimeResource?

    /// A display title derived from the prepared file URL.
    var displayTitle: String {
        fileURL.deletingPathExtension().lastPathComponent
    }
}

/// A temporary local movie file imported from the system photo library picker.
private struct ImportedMovieFile: Transferable {
    /// The transferred file URL provided by the system picker.
    let fileURL: URL
    /// The original filename reported by the picker, if available.
    let filename: String
    /// The stable playback identifier used for resume persistence.
    let playbackIDRawValue: String

    /// The file-based transfer representation used for large video assets.
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { receivedFile in
            let originalURL = receivedFile.file
            return ImportedMovieFile(
                fileURL: originalURL,
                filename: originalURL.lastPathComponent,
                playbackIDRawValue: originalURL.lastPathComponent
            )
        }
    }
}

#Preview {
    NavigationStack {
        LocalVideoPickerView()
    }
}
