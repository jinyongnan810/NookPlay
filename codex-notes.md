# Codex Notes

This file captures implementation decisions and constraints that came up during the current build session so a new agent can continue without rediscovering them.

## Current Product State

- The app is no longer the default template.
- The main window uses a `NavigationStack` with three top-level routes: Local Video, Web Video, and Media Server.
- Local Video is the first real vertical slice and currently works end to end for session-based `.mp4` import and playback.
- Playback uses a shared player foundation with resume persistence.
- The player also supports immersive playback inside visionOS.

## Implementation Preferences

- Prefer Swift Observation.
- If a view owns a model, use `@State`, not `@StateObject`.
- Keep detailed doc comments on properties and functions.
- Keep `// MARK:` sections in larger files.
- Prefer latest SwiftUI and platform APIs, but verify them first with Apple docs or `DocumentationSearch`.
- Ask a question before committing to platform-sensitive work if the behavior is unclear.

## Player Decisions

- Do not build custom transport controls for the main video player unless there is a strong product reason.
- Use the system player UI.
- The current implementation uses `AVPlayerViewController` via `SystemVideoPlayer.swift`.
- Local video playback is presented with `fullScreenCover`, which matched the native fullscreen behavior the user wanted.
- Keep the video full-bleed with no extra framing UI around it.
- Keep immersive playback available from the system media environment entry rather than inventing a separate player chrome layer.

## Local Video Decisions

- The local video MVP is session-first.
- `fileImporter` is currently limited to `.mpeg4Movie`.
- `LocalVideoAccessManager` handles security-scoped access for the active session.
- Persistent cross-launch reopening for local files is intentionally deferred on visionOS.
- Do not assume macOS-style persistent bookmark behavior is available or correct on visionOS without verifying it first.

## Home Screen Decisions

- Keep the home screen simple.
- The current card treatment uses native button styling:
  - `.buttonStyle(.bordered)`
  - `.buttonBorderShape(.roundedRectangle(radius: 24))`
  - `.controlSize(.large)`
- Do not reintroduce custom hover-effect code unless there is a clear reason.
- Keep the current navigation title as `NookPlay`.

## Known Constraints / TODOs

- Minimum window size enforcement was attempted through both SwiftUI sizing and UIKit visionOS scene geometry APIs, but it did not work reliably in the tested runtime.
- That work was intentionally reverted.
- There is a TODO in `NookPlayApp.swift` to revisit minimum window sizing later.
- For now, keep the home layout resilient when the window becomes small.

## Practical Next-Step Guidance

- The safest next feature is Web Video MVP.
- After that, add Recent items in a way that does not depend on persistent local-file reopening.
- DLNA should remain later work.

## Validation Expectations

- Run diagnostics on edited files.
- Build the project after meaningful changes.
- If using new Apple APIs or new SwiftUI behavior, check Apple documentation first.
