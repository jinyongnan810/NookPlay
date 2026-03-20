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
    // MARK: State

    /// The recent playback entries shown on the home screen.
    @State private var recentEntries: [ResumeEntry] = []
    /// The store used to read resume metadata for the Recent section.
    @State private var progressStore = PlaybackProgressStore()

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

                    if recentEntries.isEmpty {
                        Text("Recently played items will appear here after you start watching videos.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(recentEntries, id: \.itemID.storageKey) { entry in
                                RecentPlaybackRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .navigationTitle("NookPlay")
        .task {
            await loadRecentEntries()
        }
        .onAppear {
            Task {
                await loadRecentEntries()
            }
        }
    }

    // MARK: Data Loading

    /// Refreshes the Recent section from persisted resume metadata.
    @MainActor
    private func loadRecentEntries() async {
        recentEntries = await progressStore.loadRecentEntries(limit: 6)
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

// MARK: - RecentPlaybackRow

private struct RecentPlaybackRow: View {
    /// The resume entry displayed by this row.
    let entry: ResumeEntry

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: sourceSystemImage)
                .font(.title3)
                .frame(width: 36, height: 36)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(1)

                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(progressDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.lastPlayedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// A compact progress string for the saved playback position.
    private var progressDescription: String {
        let elapsed = Duration.seconds(entry.lastPositionSeconds).formatted(.time(pattern: .minuteSecond))

        guard let durationSeconds = entry.durationSeconds, durationSeconds.isFinite, durationSeconds > 0 else {
            return "Stopped at \(elapsed)"
        }

        let duration = Duration.seconds(durationSeconds).formatted(.time(pattern: .minuteSecond))
        return "Stopped at \(elapsed) of \(duration)"
    }

    /// The icon used for the entry's playback source type.
    private var sourceSystemImage: String {
        switch entry.itemID.sourceType {
        case .local:
            "internaldrive.fill"
        case .web:
            "globe"
        case .dlna:
            "network"
        }
    }
}

#Preview {
    NavigationStack {
        HomeView { _ in }
    }
}
