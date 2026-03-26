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

    // MARK: Environment

    @Environment(AppModel.self) private var appModel

    // MARK: State

    /// The helper that converts imported file URLs into playable media.
    @State private var accessManager = LocalVideoAccessManager()
    /// Controls presentation of the SwiftUI file importer.
    @State private var isImporterPresented = false
    /// Controls presentation of the system photo library picker.
    @State private var isPhotosPickerPresented = false
    /// Tracks whether the app is currently processing the selected file.
    @State private var isImporting = false
    /// The active import task, if the current import is cancellable.
    @State private var importTask: Task<Void, Never>?
    /// The transfer progress reported by the current import, when available.
    @State private var importTransferProgress: Progress?
    /// A polled fraction-complete value for the current import.
    @State private var importProgressValue: Double?
    /// A polling task that mirrors `Progress.fractionCompleted` into SwiftUI state.
    @State private var importProgressPollingTask: Task<Void, Never>?
    /// The selected photo library item awaiting import.
    @State private var selectedPhotoItem: PhotosPickerItem?

    /// The latest user-facing import error, if any.
    @State private var importErrorMessage: String?

    // MARK: Body

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Browse supported videos from Files, iCloud, or your photo library.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HStack(spacing: 18) {
                    localSourceButton(
                        title: "Files",
                        subtitle: "Browse local files and iCloud Drive.",
                        systemImage: "folder.fill"
                    ) {
                        importErrorMessage = nil
                        isImporterPresented = true
                    }

                    localSourceButton(
                        title: "Photos",
                        subtitle: "Import a video from your library.",
                        systemImage: "photo.on.rectangle.angled"
                    ) {
                        importErrorMessage = nil
                        isPhotosPickerPresented = true
                    }
                }

                if let importErrorMessage {
                    Text(importErrorMessage)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .disabled(isImporting)

            if isImporting {
                importOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Local Video")
        .navigationBarTitleDisplayMode(.inline)
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
            beginImport()
            importTask = Task {
                await importPhotoLibraryItem(newItem)
            }
        }
        .onDisappear {
            cancelImport()
        }
    }

    // MARK: View Building

    /// Creates a local-source action button sized to share row space evenly.
    ///
    /// - Parameters:
    ///   - title: The main label for the source.
    ///   - subtitle: The supporting description for the source.
    ///   - systemImage: The SF Symbol representing the source.
    ///   - isProminent: Whether to use the prominent bordered style.
    ///   - action: The action to run when the button is selected.
    /// - Returns: A consistently sized source button view.
    @ViewBuilder
    private func localSourceButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        let label = VStack(alignment: .center, spacing: 18) {
            Spacer(minLength: 0)

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.accentColor.tertiary)
                    .frame(width: 100, height: 100)

                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .center)
        .padding(24)

        Button(action: action) {
            label
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 30))
        .controlSize(.large)
    }

    /// A full-screen overlay describing the current import and offering cancellation.
    private var importOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.2))
                .ignoresSafeArea()

            VStack(spacing: 18) {
                if let importProgressValue {
                    ProgressView(value: importProgressValue)
                        .frame(width: 260)

                    Text("Preparing video \(Int(importProgressValue * 100))%")
                        .font(.headline)
                } else {
                    ProgressView()
                        .controlSize(.large)

                    Text("Preparing video…")
                        .font(.headline)
                }

                Text("You can cancel now and return to the picker.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Cancel Loading") {
                    cancelImport()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    // MARK: Actions

    /// Handles the result from the system file importer.
    ///
    /// - Parameter result: The URL chosen by the user, or an import error.
    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            beginImport()
            importTask = Task {
                do {
                    let media = try await MainActor.run {
                        try accessManager.importPlayableMedia(from: url)
                    }
                    let preparedPlayerItem = await PlayerViewModel.makePreparedPlayerItem(for: media.asMediaSource)

                    guard !Task.isCancelled else {
                        return
                    }

                    await MainActor.run {
                        let viewModel = PlayerViewModel(
                            mediaSource: media.asMediaSource,
                            preparedPlayerItem: preparedPlayerItem
                        )
                        appModel.presentPlayer(viewModel)
                        finishImport()
                    }
                } catch {
                    await MainActor.run {
                        guard !isImportCancelled(error) else {
                            finishImport()
                            return
                        }

                        importErrorMessage = error.localizedDescription
                        finishImport()
                    }
                }
            }
        case let .failure(error):
            importErrorMessage = error.localizedDescription
            finishImport()
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
            guard let importedMovie = try await loadImportedMovie(from: item) else {
                importErrorMessage = "NookPlay couldn’t load the selected photo library video."
                finishImport()
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
            let preparedPlayerItem = await PlayerViewModel.makePreparedPlayerItem(for: media.asMediaSource)

            guard !Task.isCancelled else {
                finishImport()
                return
            }

            let viewModel = PlayerViewModel(
                mediaSource: media.asMediaSource,
                preparedPlayerItem: preparedPlayerItem
            )
            appModel.presentPlayer(viewModel)
            finishImport()
        } catch {
            guard !isImportCancelled(error) else {
                finishImport()
                return
            }

            importErrorMessage = error.localizedDescription
            finishImport()
        }
    }

    /// Loads a photo-library movie while capturing any available transfer progress.
    ///
    /// - Parameter item: The selected photo-library item to import.
    /// - Returns: The imported movie file, or `nil` if the provider returns no file.
    private func loadImportedMovie(from item: PhotosPickerItem) async throws -> ImportedMovieFile? {
        try await withCheckedThrowingContinuation { continuation in
            let progress = item.loadTransferable(type: ImportedMovieFile.self) { result in
                Task { @MainActor in
                    switch result {
                    case let .success(movie):
                        continuation.resume(returning: movie)
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }
            }

            Task { @MainActor in
                trackImportProgress(progress)
            }
        }
    }

    /// Starts a new import session and resets transient import UI state.
    @MainActor
    private func beginImport() {
        importTask?.cancel()
        importProgressPollingTask?.cancel()
        importTask = nil
        importTransferProgress = nil
        importProgressValue = nil
        isImporting = true
    }

    /// Completes the current import session and clears transient progress state.
    @MainActor
    private func finishImport() {
        importTask?.cancel()
        importProgressPollingTask?.cancel()
        importTask = nil
        importTransferProgress = nil
        importProgressValue = nil
        isImporting = false
    }

    /// Cancels the active import work and clears the overlay state.
    @MainActor
    private func cancelImport() {
        importTransferProgress?.cancel()
        importTask?.cancel()
        finishImport()
    }

    /// Tracks a `Progress` object so the overlay can show percentage updates.
    ///
    /// - Parameter progress: The import progress reported by the current provider.
    @MainActor
    private func trackImportProgress(_ progress: Progress) {
        importTransferProgress = progress
        importProgressValue = progress.totalUnitCount > 0 ? progress.fractionCompleted : nil
        importProgressPollingTask?.cancel()
        // ⭐️ Update progress
        importProgressPollingTask = Task {
            while !Task.isCancelled, !progress.isFinished {
                await MainActor.run {
                    importProgressValue = progress.totalUnitCount > 0 ? progress.fractionCompleted : nil
                }

                try? await Task.sleep(for: .milliseconds(120))
            }

            await MainActor.run {
                importProgressValue = progress.totalUnitCount > 0 ? progress.fractionCompleted : importProgressValue
            }
        }
    }

    /// Determines whether an error represents user-driven or programmatic cancellation.
    ///
    /// - Parameter error: The error to inspect.
    /// - Returns: `true` when the error is a cancellation error.
    private func isImportCancelled(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
            || nsError.domain == NSItemProvider.errorDomain && nsError.code == NSUserCancelledError
            || nsError.domain == "CoreTransferable.TransferableSupportError"
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
