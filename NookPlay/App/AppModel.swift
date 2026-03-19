//
//  AppModel.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var path: [AppRoute] = []

    func open(_ route: AppRoute) {
        path.append(route)
    }
}
