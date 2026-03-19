//
//  WebBrowserViewModel.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class WebBrowserViewModel {
    // MARK: Observable State

    /// The current page title, when available.
    private(set) var pageTitle = ""
    /// Indicates whether the current page is loading.
    private(set) var isLoading = false
    /// A user-facing load error, if one occurs.
    private(set) var errorMessage: String?

    // MARK: Private State

    /// The current page URL.
    private(set) var currentURL: URL?
    /// The initial URL requested for the browser session.
    let initialURL: URL
    /// The hosted web view, retained weakly to avoid lifecycle cycles.
    @ObservationIgnored
    private weak var webView: WKWebView?

    // MARK: Initialization

    /// Creates a browser view model for an initial URL.
    ///
    /// - Parameter initialURL: The first page the embedded browser should load.
    init(initialURL: URL) {
        self.initialURL = initialURL
        currentURL = initialURL
    }

    // MARK: Public Actions

    /// Attaches a web view instance to the model and loads the initial request once.
    ///
    /// - Parameter webView: The `WKWebView` managed by the representable wrapper.
    func attach(webView: WKWebView) {
        let shouldLoadInitialURL = self.webView !== webView
        self.webView = webView
        syncState(from: webView)

        if shouldLoadInitialURL, webView.url == nil {
            load(initialURL)
        }
    }

    /// Loads a specific URL in the browser.
    ///
    /// - Parameter url: The destination to request.
    func load(_ url: URL) {
        currentURL = url
        errorMessage = nil
        webView?.load(URLRequest(url: url))
    }

    /// Updates browser state from the latest web view navigation state.
    ///
    /// - Parameter webView: The web view to read from.
    func syncState(from webView: WKWebView) {
        currentURL = webView.url ?? currentURL
        pageTitle = webView.title ?? pageTitle
        isLoading = webView.isLoading
    }

    /// Updates the error message for a failed navigation.
    ///
    /// - Parameter error: The navigation error reported by WebKit.
    func handleNavigationError(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }

        errorMessage = error.localizedDescription
        isLoading = false
    }

    // MARK: URL Normalization

    /// Converts free-form user input into a loadable URL when possible.
    ///
    /// - Parameter rawValue: The user-entered address text.
    /// - Returns: A normalized URL, or `nil` if the text can't produce a valid web URL.
    static func normalizedURL(from rawValue: String) -> URL? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if let explicitURL = URL(string: trimmedValue), explicitURL.scheme != nil {
            return explicitURL
        }

        guard !trimmedValue.contains(" ") else {
            return nil
        }

        return URL(string: "https://\(trimmedValue)")
    }
}
