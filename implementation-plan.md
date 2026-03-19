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
- `LocalVideoAccessManager.swift` manages session-scoped local file access.
- `LocalPlayableMedia.swift` adapts imported files to the shared playback model.
- Imported local video is presented with `fullScreenCover`.

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

### Deferred / Known Limits

1. Persistent local-file reopening across launches

- The current local-file flow is session-first.
- visionOS persistent bookmark / reopen behavior has not been finalized.
- Do not assume macOS-like bookmark persistence is correct here without verification.

2. Recent items reopening for local files

- A Recent section exists visually on the home screen, but recent-item persistence has not been implemented yet.
- Reopening local recents across launches should stay deferred until persistent local-file access is solved.

3. Minimum window size enforcement

- Multiple approaches were attempted and then reverted:
  - SwiftUI content sizing
  - scene-level window sizing
  - UIKit visionOS geometry requests
- A TODO remains in `NookPlayApp.swift`.
- For now, the layout should simply remain resilient in small windows.

4. Web Video

- The route exists, but it is still a placeholder.

5. Media Server / DLNA

- The route exists, but it is still a placeholder.

## Recommended Next Step

Build Phase 4: Web Video MVP.

This is the best next slice because:

- Local playback already works.
- The shared player foundation is already in place.
- Web Video does not depend on solving visionOS local-file persistence first.
- DLNA remains the highest-risk feature and should stay later.

## Next Implementation Slice: Web Video MVP

### Target Files

- `NookPlay/NookPlay/Features/WebVideo/WebEntryView.swift`
- `NookPlay/NookPlay/Features/WebVideo/WebBrowserView.swift`
- `NookPlay/NookPlay/Features/WebVideo/WKWebViewContainer.swift`
- `NookPlay/NookPlay/Features/WebVideo/WebBrowserViewModel.swift`

### Scope

- Replace the Web Video placeholder route with a real feature flow.
- Add a URL entry screen.
- Normalize simple user input like missing `https://` where appropriate.
- Present a `WKWebView`-based browser.
- Support:
  - back
  - forward
  - reload
  - address entry
- Enable inline media playback where the site allows it.

### Non-Goals

- No stream extraction.
- No site-specific parsing.
- No DRM work.
- Do not try to force websites into the shared native player pipeline for this first pass.

### Exit Criteria

- A user can choose Web Video from the home screen.
- A user can enter a URL and open it in an in-app browser.
- Basic navigation controls work.
- The project builds cleanly.

## After Web Video

1. Add Recent items in a safe form

- Start with display-oriented recent metadata.
- Avoid depending on cross-launch reopening of local files until that storage strategy is confirmed.

2. Revisit the player only if there is a concrete product need

- Keep native controls.
- Avoid reintroducing custom playback chrome unless required.

3. Begin DLNA only after Web Video is stable

- Add SSDP discovery.
- Add server browsing.
- Add DIDL parsing.
- Feed selected media into the existing shared player flow.

## Working Rules For The Next Agent

- Prefer Swift Observation over old `ObservableObject` patterns.
- If a view owns the model, prefer `@State`.
- Keep detailed property/function comments.
- Keep `// MARK:` sections in larger files.
- Use Apple docs or `DocumentationSearch` before relying on newer SwiftUI or visionOS APIs.
- Ask the user before making assumptions on unresolved platform behavior.
