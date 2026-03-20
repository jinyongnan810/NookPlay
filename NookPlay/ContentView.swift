//
//  ContentView.swift
//  NookPlay
//
//  Created by Yuunan kin on 2026/03/19.
//

import SwiftUI

/// The root container for the main app window.
///
/// This view owns the main `NavigationStack` and maps app routes to feature views.
struct ContentView: View {
    // MARK: Environment

    /// Shared app state injected from `NookPlayApp`.
    @Environment(AppModel.self) private var appModel

    // MARK: Body

    var body: some View {
        /// A bindable projection of the shared app model for navigation updates.
        @Bindable var appModel = appModel

        NavigationStack(path: $appModel.path) {
            HomeView(openRoute: appModel.open)
                .navigationDestination(for: AppRoute.self) { route in
                    destinationView(for: route)
                }
        }
    }

    // MARK: Navigation

    /// Returns the destination view for a given high-level app route.
    ///
    /// - Parameter route: The route requested by the root navigation stack.
    /// - Returns: The feature view associated with that route.
    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case .localVideo:
            // Local playback is the first implemented vertical slice, so it
            // gets a real feature flow while the others remain placeholders.
            LocalVideoPickerView()
        case .webVideo:
            WebEntryView()
        case .mediaServer:
            MediaServerView()
        }
    }
}

/// Temporary placeholder for feature areas that haven't been implemented yet.
private struct RoutePlaceholderView: View {
    // MARK: Properties

    /// The unimplemented route that this placeholder is describing.
    let route: AppRoute

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(32)
        .navigationTitle(title)
    }

    // MARK: Derived Values

    /// The screen title for the placeholder route.
    private var title: String {
        switch route {
        case .localVideo:
            "Local Video"
        case .webVideo:
            "Web Video"
        case .mediaServer:
            "Media Server"
        }
    }

    /// A short explanation of what the unfinished feature will eventually contain.
    private var message: String {
        switch route {
        case .localVideo:
            "This flow will host file importing and local playback."
        case .webVideo:
            "This flow will host URL entry and the embedded web player."
        case .mediaServer:
            "This flow will host DLNA discovery and media browsing."
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
