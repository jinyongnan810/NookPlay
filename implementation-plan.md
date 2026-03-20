# NookPlay Implementation Plan

This file reflects the repo's current state after the latest implementation session. It is intended to let a new agent continue work quickly without re-auditing the whole project.

## Current Status

### Completed

1. App shell and routing

- `ContentView.swift` hosts the root `NavigationStack`.
- `AppRoute.swift` defines the current top-level routes.
- `AppModel.swift` owns shared navigation and immersive playback state.
- `HomeView.swift` is the current landing screen with source cards for:
  - Local Video
  - Web Video
  - Media Server

2. Shared playback foundation

- `PlayableMediaSource.swift` defines the shared source abstraction.
- `PlaybackItemID.swift`, `PlaybackSourceType.swift`, and `ResumeEntry.swift` define playback identity and persistence models.
- `PlaybackProgressStore.swift` saves resume progress in app storage.
- `PlayerViewModel.swift` prepares playback, restores progress, and saves resume state.

3. Local Video MVP

- `LocalVideoPickerView.swift` uses `fileImporter`.
- Local playback now also supports videos chosen from Photos via `PhotosPicker`.
- `LocalVideoAccessManager.swift` manages session-scoped local file access.
- `LocalPlayableMedia.swift` adapts imported files to the shared playback model.
- Imported local video is presented with `fullScreenCover`.
- Files import accepts general movie content instead of only `.mp4`.
- Photo-library videos are copied into a temporary playback cache for reliable playback.
- Temporary copied files are cleaned up both on playback release and on app launch.
- Photo-library videos use a stable playback identity for resume-progress matching.

4. Native fullscreen playback experience

- `PlayerView.swift` uses the system player UI rather than custom transport controls.
- `SystemVideoPlayer.swift` wraps `AVPlayerViewController`.
- Playback is full-bleed and relies on native controls.

5. Immersive playback

- `ImmersivePlayerView.swift` exists and is connected through `ImmersiveSpace`.
- `PlayerView.swift` contributes immersive actions through the environment picker.
- `AppModel.swift` shares the same `AVPlayer` between the windowed and immersive experiences.

6. Codebase readability improvements

- Current app files have detailed documentation comments.
- Larger files use `// MARK:` section separation.

7. Web Video MVP

- `WebEntryView.swift` provides URL entry with persisted prefilled text across launches.
- `WebBrowserView.swift` presents a minimal in-app browser using `WKWebView`.
- `WKWebViewContainer.swift` enables inline media playback where websites allow it.
- `WebBrowserViewModel.swift` normalizes entered URLs and coordinates browser state.

8. Recent playback metadata

- The Home screen now shows a display-only Recent section driven by resume metadata.
- `ResumeEntry.swift` stores lightweight display metadata alongside progress.
- Recent items do not reopen local files across launches yet.

### Deferred / Known Limits

1. Persistent local-file reopening across launches

- The current local-file flow is session-first.
- visionOS persistent bookmark / reopen behavior has not been finalized.
- Do not assume macOS-like bookmark persistence is correct here without verification.
- A future implementation should target Files-based local videos first, since they already
  have stable playback identity and are more viable than Photos-based copied imports.
- The likely path is security-scoped bookmark persistence plus explicit reopen validation on
  real hardware before wiring Recent items into playable reopen actions.

2. Recent items reopening for local files

- A Recent section now exists and is backed by persisted display metadata.
- Reopening local recents across launches should stay deferred until persistent local-file access is solved.

3. Minimum window size enforcement

- Multiple approaches were attempted and then reverted:
  - SwiftUI content sizing
  - scene-level window sizing
  - UIKit visionOS geometry requests
- A TODO remains in `NookPlayApp.swift`.
- For now, the layout should simply remain resilient in small windows.

4. Media Server / DLNA

- The route exists, but it is still a placeholder.

## Recommended Next Step

Wait for multicast entitlement approval, then resume DLNA work.

This is the correct pause point because:

- Local playback, Web Video, and Recent metadata are already in place.
- DLNA discovery code now exists, but device testing is blocked by multicast networking entitlement approval.
- Persistent Files-based local reopen also remains intentionally deferred pending platform validation.

## Next Implementation Slice After Entitlement Approval: Media Server / DLNA Discovery MVP

### Target Files

- `NookPlay/NookPlay/Features/MediaServer/MediaServerView.swift`
- `NookPlay/NookPlay/Features/MediaServer/MediaServerViewModel.swift`
- `NookPlay/NookPlay/Features/MediaServer/DLNAServiceDiscovery.swift`
- `NookPlay/NookPlay/Info.plist`

### Scope

- Replace the Media Server placeholder route with a real discovery screen.
- Send SSDP discovery requests on the local network.
- Collect responding DLNA/UPnP media servers.
- Show a list of discovered servers with lightweight metadata.
- Handle empty, loading, and error states cleanly.

### Non-Goals

- No full server browsing yet.
- No DIDL-Lite media listing yet.
- No playback handoff from DLNA selections yet.
- Do not assume multicast entitlements or local-network permissions are already configured correctly without testing.

### Exit Criteria

- A user can choose Media Server from the home screen.
- A user can trigger a scan for DLNA/UPnP servers on the local network.
- Discovered servers appear in the UI with stable deduping.
- The project builds cleanly.

## DLNA Status / Blocker

- `MediaServerView.swift`, `MediaServerViewModel.swift`, and `DLNAServiceDiscovery.swift` now implement a first-pass SSDP discovery flow.
- `Info.plist` includes local-network usage messaging.
- Device testing showed SSDP send failure with error code 65 (`No route to host`) before discovery responses were received.
- This is currently treated as a platform/signing blocker rather than an app-logic blocker.
- The likely missing requirement is Apple approval plus provisioning support for the multicast entitlement:
  - `com.apple.developer.networking.multicast`
- The user has already submitted the required request to Apple.
- Do not spend more time trying alternate SSDP transport code paths until entitlement approval/provisioning has been re-tested.

## After DLNA Discovery

1. Add server browsing and DIDL parsing

- Fetch device descriptions and content directories as needed.
- Parse DIDL-Lite containers and playable items.

2. Feed DLNA selections into the shared player pipeline

- Reuse `PlayableMediaSource` where possible.
- Decide whether remote stream resume persistence should be supported.

3. Revisit persistent Files-based local reopen on real hardware

- Validate visionOS bookmark persistence.
- Add explicit reopen flows for Recent local items only after that validation.

## Working Rules For The Next Agent

- Prefer Swift Observation over old `ObservableObject` patterns.
- If a view owns the model, prefer `@State`.
- Keep detailed property/function comments.
- Keep `// MARK:` sections in larger files.
- Use Apple docs or `DocumentationSearch` before relying on newer SwiftUI or visionOS APIs.
- Ask the user before making assumptions on unresolved platform behavior.
