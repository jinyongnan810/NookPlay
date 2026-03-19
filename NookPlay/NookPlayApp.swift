//
//  NookPlayApp.swift
//  NookPlay
//
//  Created by Yuunan kin on 2026/03/19.
//

import SwiftUI

@main
struct NookPlayApp: App {
    @State private var appModel = AppModel()
    @State private var immersionStyle: ImmersionStyle = .progressive

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: "player-immersive-space") {
            ImmersivePlayerView()
                .environment(appModel)
        }
        .immersionStyle(selection: $immersionStyle, in: .progressive)
        .upperLimbVisibility(.visible)
        .persistentSystemOverlays(.hidden)
    }
}
