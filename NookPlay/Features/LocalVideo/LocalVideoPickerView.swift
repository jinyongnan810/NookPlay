//
//  LocalVideoPickerView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import SwiftUI
import UniformTypeIdentifiers

/// The local video entry flow.
///
/// This screen lets the user pick a video file from Files/iCloud and immediately
/// presents playback when the import succeeds.
struct LocalVideoPickerView: View {
    // MARK: State

    /// The helper that converts imported file URLs into playable media.
    @State private var accessManager = LocalVideoAccessManager()
    /// Controls presentation of the SwiftUI file importer.
    @State private var isImporterPresented = false
    /// Tracks whether the app is currently processing the selected file.
    @State private var isImporting = false

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
                Text("Choose an MP4 from Files or iCloud to play it in NookPlay.")
            } actions: {
                Button("Choose Video") {
                    importErrorMessage = nil
                    isImporting = true
                    isImporterPresented = true
                }
                .buttonStyle(.borderedProminent)

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
            allowedContentTypes: [.mpeg4Movie],
            onCompletion: handleImportResult
        )
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
}

#Preview {
    NavigationStack {
        LocalVideoPickerView()
    }
}
