//
//  WebBrowserView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import SwiftUI

/// An in-app browser for web-hosted video sites.
struct WebBrowserView: View {
    // MARK: Environment

    /// Shared app state used to present the native fullscreen player.
    @Environment(AppModel.self) private var appModel

    // MARK: State

    /// The browser state and navigation coordinator for this screen.
    @State private var viewModel: WebBrowserViewModel

    // MARK: Initialization

    /// Creates a browser screen for a specific destination URL.
    ///
    /// - Parameter initialURL: The first URL to load.
    init(initialURL: URL) {
        _viewModel = State(initialValue: WebBrowserViewModel(initialURL: initialURL))
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }

            WKWebViewContainer(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
        .background(Color.black.opacity(0.04))
        .navigationTitle(viewModel.pageTitle.isEmpty ? "Browser" : viewModel.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Reassign the callback during appearance so the view model always targets the
            // current shared app model rather than capturing stale presentation state.
            viewModel.onNativePlaybackRequested = { mediaSource in
                appModel.presentPlayer(for: mediaSource)
            }
        }
    }
}

#Preview {
    NavigationStack {
        WebBrowserView(initialURL: URL(string: "https://www.apple.com")!)
    }
}
