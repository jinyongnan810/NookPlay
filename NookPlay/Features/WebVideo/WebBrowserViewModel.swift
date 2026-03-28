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
    /// A browser-to-native playback request emitted when the page exposes a direct media URL.
    typealias NativePlaybackRequestHandler = @MainActor (AnyPlayableMediaSource) -> Void

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
    /// Called when the browser resolves a media URL that can be handed to the native player.
    @ObservationIgnored
    var onNativePlaybackRequested: NativePlaybackRequestHandler?

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

    // MARK: Native Playback Handoff

    /// Attempts to route an intercepted browser video into the app's native player flow.
    ///
    /// This is intentionally strict about what it accepts:
    /// - the page must expose a concrete `http` or `https` media URL
    /// - duplicate interception events for the same stream are ignored
    /// - unsupported streams stay in the browser so the user still has a fallback
    ///
    /// - Parameter payload: The JavaScript message body emitted by the embedded web page.
    func handleInterceptedVideoPayload(_ payload: [String: Any]) async {
        guard let mediaSource = makePlayableMediaSource(from: payload),
              mediaSource.streamURL != lastInterceptedStreamURL,
              let webView
        else {
            return
        }

        lastInterceptedStreamURL = mediaSource.streamURL

        // Stop the webpage's own media session before promoting the stream into the native
        // player. Without this pause, some sites keep audio or fullscreen state alive behind
        // the app's player presentation.
        await webView.pauseAllMediaPlayback()
        await webView.closeAllMediaPresentations()
        onNativePlaybackRequested?(mediaSource)
    }

    // MARK: Helpers

    /// The most recent media URL handed to the native player.
    ///
    /// Browser fullscreen hooks can fire multiple times for the same user action. This cache
    /// prevents presenting duplicate player sessions while the page is still transitioning.
    private var lastInterceptedStreamURL: URL?

    /// Builds a playable media source from a browser interception payload when possible.
    ///
    /// The JavaScript bridge sends page metadata as loose dictionary values, so this method
    /// centralizes the validation and URL filtering needed before anything reaches `AVPlayer`.
    private func makePlayableMediaSource(from payload: [String: Any]) -> AnyPlayableMediaSource? {
        guard let rawStreamURL = payload["streamURL"] as? String,
              let streamURL = URL(string: rawStreamURL),
              let scheme = streamURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            return nil
        }

        let resolvedPageURL: URL? = if let rawPageURL = payload["pageURL"] as? String {
            URL(string: rawPageURL)
        } else {
            currentURL
        }
        let resolvedPageTitle = payload["pageTitle"] as? String ?? pageTitle

        guard let media = WebPlayableMedia(
            streamURL: streamURL,
            pageURL: resolvedPageURL,
            pageTitle: resolvedPageTitle
        ) else {
            return nil
        }

        return media.asMediaSource
    }
}
