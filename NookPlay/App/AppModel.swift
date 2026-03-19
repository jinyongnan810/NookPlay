//
//  AppModel.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var path: [AppRoute] = []

    func open(_ route: AppRoute) {
        path.append(route)
    }
}
