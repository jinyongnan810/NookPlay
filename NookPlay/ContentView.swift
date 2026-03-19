//
//  ContentView.swift
//  NookPlay
//
//  Created by Yuunan kin on 2026/03/19.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        NavigationStack(path: $appModel.path) {
            HomeView(openRoute: appModel.open)
                .navigationDestination(for: AppRoute.self) { route in
                    destinationView(for: route)
                }
        }
    }

    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case .localVideo:
            PlayerView(mediaSource: DemoMediaSource.bigBuckBunny)
        case .webVideo, .mediaServer:
            RoutePlaceholderView(route: route)
        }
    }
}

private struct RoutePlaceholderView: View {
    let route: AppRoute

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
