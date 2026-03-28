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
    /// The JavaScript bridge name used for browser-to-native media interception.
    private static let videoBridgeMessageName = "nookPlayVideoBridge"

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
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.videoInterceptionScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )
        configuration.userContentController.add(
            context.coordinator,
            name: Self.videoBridgeMessageName
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
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

    /// A focused interception script for plain HTML5 video.
    ///
    /// This intentionally targets the narrow case where a page exposes a direct media URL on
    /// a `<video>` element. Sites that use DRM, blob URLs, cross-origin iframes, or heavily
    /// customized playback pipelines may never produce a handoff payload, in which case the
    /// browser should continue behaving as a normal web view.
    private static let videoInterceptionScript = #"""
    (function() {
        if (window.__nookPlayVideoBridgeInstalled) {
            return;
        }

        window.__nookPlayVideoBridgeInstalled = true;

        function resolvedStreamURL(video) {
            if (!video) {
                return null;
            }

            return video.currentSrc || video.src || null;
        }

        function postVideoPayload(video, reason) {
            var streamURL = resolvedStreamURL(video);
            if (!streamURL || streamURL.indexOf('http') !== 0) {
                return;
            }

            window.webkit.messageHandlers.nookPlayVideoBridge.postMessage({
                reason: reason,
                streamURL: streamURL,
                pageURL: window.location.href,
                pageTitle: document.title || '',
                isFullscreen: !!document.fullscreenElement
            });
        }

        function attachVideo(video) {
            if (!video || video.__nookPlayHandlersInstalled) {
                return;
            }

            video.__nookPlayHandlersInstalled = true;

            video.addEventListener('webkitbeginfullscreen', function() {
                postVideoPayload(video, 'webkitbeginfullscreen');
            });

            video.addEventListener('fullscreenchange', function() {
                if (document.fullscreenElement === video) {
                    postVideoPayload(video, 'fullscreenchange');
                }
            });

            video.addEventListener('play', function() {
                if (document.fullscreenElement === video) {
                    postVideoPayload(video, 'play-while-fullscreen');
                }
            });
        }

        var originalRequestFullscreen = HTMLVideoElement.prototype.requestFullscreen;
        if (originalRequestFullscreen) {
            HTMLVideoElement.prototype.requestFullscreen = function() {
                postVideoPayload(this, 'requestFullscreen');
                return originalRequestFullscreen.apply(this, arguments);
            };
        }

        var originalWebkitEnterFullscreen = HTMLVideoElement.prototype.webkitEnterFullscreen;
        if (originalWebkitEnterFullscreen) {
            HTMLVideoElement.prototype.webkitEnterFullscreen = function() {
                postVideoPayload(this, 'webkitEnterFullscreen');
                return originalWebkitEnterFullscreen.apply(this, arguments);
            };
        }

        document.querySelectorAll('video').forEach(attachVideo);

        var observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                mutation.addedNodes.forEach(function(node) {
                    if (!node || node.nodeType !== Node.ELEMENT_NODE) {
                        return;
                    }

                    if (node.tagName === 'VIDEO') {
                        attachVideo(node);
                    }

                    if (node.querySelectorAll) {
                        node.querySelectorAll('video').forEach(attachVideo);
                    }
                });
            });
        });

        observer.observe(document.documentElement || document.body, {
            childList: true,
            subtree: true
        });
    })();
    """#
}

// MARK: - Coordinator

extension WKWebViewContainer {
    /// Bridges WebKit navigation callbacks back into the observable browser model.
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
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

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == WKWebViewContainer.videoBridgeMessageName,
                  let payload = message.body as? [String: Any]
            else {
                return
            }

            Task { @MainActor [viewModel] in
                await viewModel.handleInterceptedVideoPayload(payload)
            }
        }
    }
}
