//
//  PlayerView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import AVKit
import SwiftUI

struct PlayerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: PlayerViewModel

    init(mediaSource: AnyPlayableMediaSource) {
        _viewModel = State(initialValue: PlayerViewModel(mediaSource: mediaSource))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VideoPlayer(player: viewModel.player)
                .frame(minHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.mediaSource.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                if let subtitle = viewModel.mediaSource.subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(32)
        .navigationTitle("Player")
        .task {
            viewModel.prepare()
        }
        .onDisappear {
            viewModel.handleDisappear()
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(newPhase)
        }
    }
}

#Preview {
    NavigationStack {
        PlayerView(mediaSource: DemoMediaSource.bigBuckBunny)
    }
}
