//
//  HomeView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import SwiftUI

struct HomeView: View {
    let openRoute: (AppRoute) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("NookPlay")
                        .font(.extraLargeTitle)
                        .fontWeight(.semibold)

                    Text("Choose how you want to watch video.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    SourceCard(
                        title: "Local Video",
                        subtitle: "Open an MP4 from Files or iCloud.",
                        systemImage: "internaldrive.fill"
                    ) {
                        openRoute(.localVideo)
                    }

                    SourceCard(
                        title: "Web Video",
                        subtitle: "Open a video website in an in-app browser.",
                        systemImage: "globe"
                    ) {
                        openRoute(.webVideo)
                    }

                    SourceCard(
                        title: "Media Server",
                        subtitle: "Browse DLNA servers on your local network.",
                        systemImage: "network"
                    ) {
                        openRoute(.mediaServer)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.title2)
                        .fontWeight(.medium)

                    Text("Recently played items will appear here once playback is implemented.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32)
        }
        .navigationTitle("Home")
    }
}

private struct SourceCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        HomeView { _ in }
    }
}
