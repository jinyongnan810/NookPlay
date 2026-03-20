//
//  ContentView.swift
//  NookPlay
//
//  Created by Yuunan kin on 2026/03/19.
//

import SwiftUI

/// The root container for the main app window.
///
/// This view hosts the app's three top-level video areas in tabs.
struct ContentView: View {
    // MARK: Tabs

    /// The top-level tabs shown in the main window.
    private enum AppTab: Hashable {
        case local
        case web
        case mediaServer
    }

    // MARK: State

    /// The currently selected top-level app tab.
    @State private var selectedTab: AppTab = .local

    // MARK: Body

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LocalVideoPickerView()
            }
            .tabItem {
                Label("Local", systemImage: "internaldrive")
            }
            .tag(AppTab.local)

            NavigationStack {
                WebEntryView()
            }
            .tabItem {
                Label("Web", systemImage: "network")
            }
            .tag(AppTab.web)

            NavigationStack {
                MediaServerView()
            }
            .tabItem {
                Label("Server", systemImage: "cloud")
            }
            .tag(AppTab.mediaServer)
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
