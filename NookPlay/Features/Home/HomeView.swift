//
//  HomeView.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import SwiftUI

/// The app's landing screen.
///
/// This view presents the three top-level source choices and a placeholder area
/// for recent items.
struct HomeView: View {
    // MARK: Actions

    /// Callback used when the user selects one of the source entry points.
    let openRoute: (AppRoute) -> Void

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Choose how you want to watch video.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(spacing: 16) {
                    // The three source cards establish the product's core mental
                    // model: choose where the video comes from first, then browse.
                    SourceCard(
                        title: "Local Video",
                        subtitle: "Open a supported video from Files, iCloud, or Photos.",
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
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .navigationTitle("NookPlay")
    }
}

// MARK: - SourceCard

private struct SourceCard: View {
    // MARK: Properties

    /// The primary title shown on the card.
    let title: String
    /// The supporting description shown below the title.
    let subtitle: String
    /// The SF Symbol used to visually identify the source type.
    let systemImage: String
    /// The action to run when the card is selected.
    let action: () -> Void

    // MARK: Body

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)

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
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 24))
        .controlSize(.large)
    }
}

#Preview {
    NavigationStack {
        HomeView { _ in }
    }
}
