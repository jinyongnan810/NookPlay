//
//  WKWebViewContainer.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import SwiftUI
import WebKit

/// A SwiftUI wrapper around `WKWebView` for the in-app browser flow.
struct WKWebViewContainer: UIViewRepresentable {
    /// The browser state model that owns navigation actions and UI state.
    let viewModel: WebBrowserViewModel

    /// Creates a configured web view for interactive browsing.
    ///
    /// - Parameter context: The representable context from SwiftUI.
    /// - Returns: A configured `WKWebView` instance.
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = .black
        webView.isOpaque = false

        viewModel.attach(webView: webView)
        return webView
    }

    /// Updates the browser model whenever SwiftUI refreshes the wrapped view.
    ///
    /// - Parameters:
    ///   - webView: The wrapped `WKWebView`.
    ///   - context: The representable context from SwiftUI.
    func updateUIView(_ webView: WKWebView, context _: Context) {
        viewModel.attach(webView: webView)
    }

    /// Creates the delegate coordinator used to observe navigation changes.
    ///
    /// - Returns: A new web view coordinator.
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
}

// MARK: - Coordinator

extension WKWebViewContainer {
    /// Bridges WebKit navigation callbacks back into the observable browser model.
    final class Coordinator: NSObject, WKNavigationDelegate {
        /// The browser model receiving navigation state updates.
        private let viewModel: WebBrowserViewModel

        /// Creates a coordinator for a specific browser model.
        ///
        /// - Parameter viewModel: The observable browser state model.
        init(viewModel: WebBrowserViewModel) {
            self.viewModel = viewModel
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            viewModel.syncState(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit _: WKNavigation!) {
            viewModel.syncState(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            viewModel.syncState(from: webView)
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            viewModel.syncState(from: webView)
            viewModel.handleNavigationError(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            viewModel.syncState(from: webView)
            viewModel.handleNavigationError(error)
        }
    }
}
