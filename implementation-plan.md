# NookPlay Concrete Implementation Plan

Given the current repo is still the default visionOS template, the fastest correct path is to build the app in thin vertical slices, with the player foundation first and DLNA last.

1. Establish app structure and routing.
2. Build the reusable native player and resume persistence.
3. Add the local-file flow end to end.
4. Add the web flow with embedded browsing.
5. Add DLNA discovery and browsing after the app already plays local and remote URLs reliably.

## Phase 0: Restructure the Template

Create a minimal folder layout inside `NookPlay/NookPlay`:

- `App`
- `Features/Home`
- `Features/Player`
- `Features/LocalVideo`
- `Features/WebVideo`
- `Features/DLNA`
- `Core/Models`
- `Core/Persistence`
- `Core/Playback`
- `Core/Networking`

Initial files to add:

- `App/NookPlayApp.swift` update to own shared app state
- `App/AppRoute.swift`
- `App/AppModel.swift`
- `Features/Home/HomeView.swift`
- `Core/Models/PlaybackSourceType.swift`
- `Core/Models/PlaybackItemID.swift`
- `Core/Models/RecentItem.swift`
- `Core/Models/ResumeEntry.swift`

Goal for this phase:

- Replace the template `ContentView` with a real home screen.
- Show three source cards: Local Video, Web Video, Media Server.
- Keep navigation simple with `NavigationStack` in one `WindowGroup`.

## Phase 1: Player Foundation

Build the player before source integrations.

Files:

- `Features/Player/PlayerView.swift`
- `Features/Player/PlayerViewModel.swift`
- `Core/Playback/PlayableMediaSource.swift`
- `Core/Playback/PlaybackCoordinator.swift`
- `Core/Persistence/PlaybackProgressStore.swift`

Scope:

- Wrap `AVPlayer`
- Support play/pause/seek
- Show title, progress, duration
- Restore resume position on open
- Save progress periodically and on disappear/background
- Accept any `PlayableMediaSource` with stable `PlaybackItemID`

Implementation details:

- Use a protocol-based source model so local and DLNA both feed the same player.
- Start with a lightweight JSON-backed store in Application Support.
- Only move to SwiftData if the persistence needs actually grow.

Exit criteria:

- A hardcoded local or remote `.mp4` can open and resume correctly.
- Build succeeds cleanly.

## Phase 2: Local Video MVP

Files:

- `Features/LocalVideo/LocalVideoPickerView.swift`
- `Features/LocalVideo/LocalPlayableMedia.swift`
- `Features/LocalVideo/LocalVideoAccessManager.swift`

Scope:

- Use `fileImporter`
- Restrict initial selection to movie types, with `.mp4` as the tested target
- Convert chosen file into `LocalPlayableMedia`
- Start playback in `PlayerView`
- Derive stable item identity from bookmark or normalized file URL
- Save and restore resume position

Notes:

- Support security-scoped resource access immediately.
- Handle iCloud-backed files conservatively: loading state, playback failure state, readable errors.

Exit criteria:

- User can launch app, choose Local Video, pick an `.mp4`, play it, close it, and resume.

## Phase 3: Recent Items and Home Screen State

Files:

- `Core/Persistence/RecentItemsStore.swift`
- `Features/Home/RecentItemsSection.swift`

Scope:

- Persist recently opened items
- Show recent items on the home screen
- Tapping a recent local item should reopen if access is still valid

Notes:

- Only add items after successful playback start.
- If bookmark restore fails, show a recoverable error rather than silently dropping the item.

Exit criteria:

- Home screen reflects recent local content and can reopen it.

## Phase 4: Web Video MVP

Files:

- `Features/WebVideo/WebEntryView.swift`
- `Features/WebVideo/WebBrowserView.swift`
- `Features/WebVideo/WKWebViewContainer.swift`
- `Features/WebVideo/WebBrowserViewModel.swift`

Scope:

- Accept a URL string
- Normalize missing schemes where reasonable
- Open the page in `WKWebView`
- Enable inline media playback
- Provide back, forward, reload, and address bar
- Keep this separate from native `AVPlayer` playback for MVP

Notes:

- Treat web as “video-focused in-app browser,” not stream extraction.
- Do not attempt site-specific parsing or DRM handling in first pass.

Exit criteria:

- User can enter a video website URL and use it inside the app in a stable browsing view.

## Phase 5: Optional Viewing Mode / Immersive Support

Only after local playback and web browsing are stable.

Files:

- `App/SceneCoordinator.swift`
- `Features/Player/ImmersivePlaybackCoordinator.swift`

Scope:

- Add optional immersive environment entry from the player
- Keep video playback logic unchanged
- Use immersion as presentation enhancement, not core architecture

Exit criteria:

- Player works normally in windowed mode and can optionally switch into the designed viewing environment.

## Phase 6: DLNA MVP

Files:

- `Core/Networking/SSDPClient.swift`
- `Features/DLNA/DLNAServerListView.swift`
- `Features/DLNA/DLNABrowserView.swift`
- `Features/DLNA/DLNAService.swift`
- `Features/DLNA/DIDLParser.swift`
- `Features/DLNA/DLNAPlayableMedia.swift`

Scope:

- Discover servers via SSDP
- List discovered servers
- Browse containers/items
- Extract playable `.mp4` resources
- Convert selected item into `DLNAPlayableMedia`
- Feed into shared `PlayerView`
- Save resume using server UUID + object ID/resource URL

Notes:

- This is the most failure-prone integration.
- Keep parsing and networking isolated from UI.
- Expect partial interoperability across servers.

Exit criteria:

- App can discover at least one standards-compliant DLNA server, browse folders, and play supported items.

## Testing Plan

Use the built-in Testing framework from the start.

Add tests for:

- `PlaybackItemID` stability
- resume entry save/load behavior
- recent item persistence
- URL normalization for web input
- DLNA XML parsing once introduced

UI/manual validation milestones:

1. Home screen navigation works.
2. Local `.mp4` playback works.
3. Resume works after relaunch.
4. Web browser loads and plays inline media on basic sites.
5. DLNA discovery and browsing work on a local network.

## Recommended Build Order in This Repo

1. Replace `ContentView.swift` with a real home screen.
2. Add core models and JSON persistence.
3. Build the reusable player.
4. Wire local file import into the player.
5. Add recent items.
6. Add the web browser flow.
7. Add optional immersive presentation.
8. Add DLNA.

## Pragmatic Decisions

- Remove the RealityKit template content unless you specifically want a branded 3D home scene.
- Do not introduce SwiftData yet unless you want schema-driven persistence soon.
- Do not split into multiple windows early; one window with route-based navigation is enough for MVP.
- Do not start with DLNA. It will slow down the whole project if playback fundamentals are not already solid.
