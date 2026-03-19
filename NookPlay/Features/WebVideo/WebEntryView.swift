//
//  WebEntryView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import SwiftUI

/// The entry screen for the app's web video flow.
struct WebEntryView: View {
    /// The persisted URL text shown when the user returns to the web entry screen.
    @AppStorage("webVideoPrefilledAddress") private var storedAddressText = ""

    // MARK: State

    /// The free-form URL text entered by the user.
    @State private var addressText = ""
    /// The next browser destination requested by the user.
    @State private var destination: WebDestination?
    /// The latest validation error for URL entry.
    @State private var errorMessage: String?

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ContentUnavailableView {
                Label("Web Video", systemImage: "globe")
            } description: {
                Text("Open a video website in an in-app browser with native web navigation controls.")
            } actions: {
                HStack(spacing: 12) {
                    TextField("Enter website URL", text: $addressText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280, idealWidth: 420, maxWidth: 520)
                        .onSubmit {
                            openRequestedURL()
                        }

                    Button("Open") {
                        openRequestedURL()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
            }
        }
        .navigationTitle("Web Video")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if addressText.isEmpty {
                addressText = storedAddressText
            }
        }
        .navigationDestination(item: $destination) { destination in
            WebBrowserView(initialURL: destination.url)
        }
    }

    // MARK: Actions

    /// Validates the entered address and pushes the browser screen when valid.
    private func openRequestedURL() {
        guard let normalizedURL = WebBrowserViewModel.normalizedURL(from: addressText) else {
            errorMessage = "Enter a valid website address."
            return
        }

        let trimmedAddressText = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        storedAddressText = trimmedAddressText.isEmpty ? normalizedURL.absoluteString : trimmedAddressText
        addressText = storedAddressText
        errorMessage = nil
        destination = WebDestination(url: normalizedURL)
    }
}

/// A navigation payload for the web browser destination.
private struct WebDestination: Identifiable, Hashable {
    /// The destination URL to load in the in-app browser.
    let url: URL

    /// A stable identity for navigation updates.
    var id: String {
        url.absoluteString
    }
}

#Preview {
    NavigationStack {
        WebEntryView()
    }
}
