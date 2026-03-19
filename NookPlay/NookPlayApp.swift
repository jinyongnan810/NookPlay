//
//  NookPlayApp.swift
//  NookPlay
//
//  Created by Yuunan kin on 2026/03/19.
//

import SwiftUI

@main
struct NookPlayApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
    }
}
