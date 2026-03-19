//
//  LocalVideoPickerView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import SwiftUI
import UniformTypeIdentifiers

struct LocalVideoPickerView: View {
    @State private var accessManager = LocalVideoAccessManager()
    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var importedMediaSource: AnyPlayableMediaSource?
    @State private var importErrorMessage: String?

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
