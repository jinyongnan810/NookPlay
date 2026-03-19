# NookPlay Implementation Roadmap

## 1. Goal

Build **NookPlay**, a visionOS app for Apple Vision Pro that lets users enjoy:

- **Local video**
- **Web video**
- **Media-server video** via **DLNA**

The app should feel simple at launch: the user first chooses **what kind of video source** they want to use, then browses and plays content in a comfortable windowed or immersive viewing experience.

---

## 2. Product Scope

## Phase 1 target

Deliver a working MVP with these capabilities:

### Local video
- User chooses **Local / iCloud files**
- Supports **`.mp4`**
- Opens selected file and plays it in-app
- Saves **playback position per video**
- User can watch in normal window and optionally use Vision Pro immersive environment while viewing

### Web video
- User enters a URL
- App opens webpage
- User can play website video inside the app
- User can watch while using a Vision Pro environment
- No VR-specific parsing yet

### Media-server video
- Discover **DLNA servers**
- Browse folders / containers
- Show playable video items
- Play **`.mp4`** files from DLNA
- Save playback position per video item if stable ID can be derived

---

## 3. Non-goals for initial release

Do not build these in the first pass:

- Full MKV support
- Advanced subtitle support
- VR video metadata detection / stereoscopic playback modes
- Plex / Jellyfin / SMB / WebDAV
- Downloads / offline caching
- Multi-window advanced workflows
- User accounts / sync across devices
- Rich library database with posters and metadata scraping

These can be added later after the playback foundations are stable.

---

## 4. Recommended Tech Stack

- **Language:** Swift
- **UI:** SwiftUI
- **Platform:** visionOS
- **Playback:** `AVPlayer`, `AVKit`, `AVAsset`
- **File importing:** `fileImporter`
- **Web rendering:** `WKWebView` via `UIViewRepresentable`
- **Persistence:** SwiftData or lightweight local persistence layer
- **Networking for DLNA:** URLSession + custom SSDP / UPnP / DIDL-Lite parsing
- **Immersive support:** visionOS scene management with `WindowGroup` + `ImmersiveSpace` only where useful

### Recommendation
For this app, I would use:

- **SwiftUI**
- **AVPlayer**
- **SwiftData** for resume positions and recent items
- A **small custom DLNA client layer**

That gives a clean foundation without over-engineering.

---

## 5. High-level Architecture

Use a modular structure from the start.

```text
NookPlay
├── App
│   ├── NookPlayApp.swift
│   ├── AppRouter.swift
│   └── SceneCoordinator.swift
│
├── Features
│   ├── Home
│   ├── LocalLibrary
│   ├── WebPlayer
│   ├── DLNA
│   └── Player
│
├── Core
│   ├── Models
│   ├── Persistence
│   ├── Playback
│   ├── Networking
│   ├── Utilities
│   └── Extensions
│
├── Integrations
│   ├── AVFoundation
│   ├── WebKit
│   └── DLNA
│
└── Resources
```

---

## 6. Core User Flow

## App launch
User sees a simple start screen with three choices:

- **Local Video**
- **Web Video**
- **Media Server**

This is the core mental model of the app.

## Local flow
1. Tap **Local Video**
2. Tap **Choose Video**
3. File picker opens
4. User selects `.mp4`
5. App stores security-scoped access if needed
6. Player opens
7. App restores playback position if available
8. User watches in window or immersive environment

## Web flow
1. Tap **Web Video**
2. Enter URL
3. Open webpage in embedded web view
4. User starts video on page
5. Web view is shown in a viewing-focused layout
6. User can enable environment for a more immersive feeling

## DLNA flow
1. Tap **Media Server**
2. App discovers DLNA servers on local network
3. User selects server
4. App browses folders / containers
5. User selects playable file
6. Player opens stream URL
7. Resume position is restored if known

---

## 7. Data Model

Keep data models small and stable.

## Playback source

```swift
enum PlaybackSourceType: String, Codable {
    case local
    case web
    case dlna
}
```

## Video identity

Each playable item needs a stable ID for playback resume.

```swift
struct PlaybackItemID: Hashable, Codable {
    let sourceType: PlaybackSourceType
    let rawID: String
}
```

### ID strategy
- **Local:** bookmark/file URL path hash
- **Web:** page URL or direct video URL if available
- **DLNA:** content item ID + resource URL, or server UUID + object ID

## Resume entry

```swift
struct ResumeEntry: Codable {
    let itemID: PlaybackItemID
    var lastPositionSeconds: Double
    var durationSeconds: Double?
    var lastPlayedAt: Date
}
```

## Recent item

```swift
struct RecentItem: Codable {
    let itemID: PlaybackItemID
    let title: String
    let subtitle: String?
    let sourceType: PlaybackSourceType
    let thumbnailURL: URL?
    let lastOpenedAt: Date
}
```

For MVP, these can live in SwiftData or even JSON-backed local persistence.

---

## 8. Scene and Navigation Design

For Vision Pro, keep the app structure calm and spatially simple.

## Scenes
- **Main window scene**
  - Home screen
  - Browsers
  - URL entry
  - DLNA server list
- **Player window**
  - Dedicated playback view
- **Optional immersive space**
  - Used for environmental viewing mood, not necessarily full custom 3D playback initially

## Recommendation
Start with:
- One main `WindowGroup`
- One dedicated player route
- Add immersive scene only after basic playback works

Avoid building the app around immersion too early. First make browsing and playback reliable.

---

## 9. Detailed Feature Breakdown

# 9.1 Home Screen

## Responsibilities
- Present source choices
- Show recently played items
- Keep entry friction low

## UI
- App logo / title
- Three large source cards
- Recent items section below

## Tasks
- Build `HomeView`
- Add route enum for navigation
- Add recent items storage and display
- Add friendly empty states

---

# 9.2 Local Video

## Functional requirements
- Pick video from Files app
- Support local and iCloud-backed files
- Access selected file reliably
- Play selected video
- Save playback timestamp

## Technical considerations

### File import
Use `fileImporter` with allowed content types for `.mp4`.

Later, add custom type handling for `.mkv` when playback support is decided.

### Security-scoped resources
Imported file URLs may require security-scoped access. If the file needs to be reopened later, store a bookmark.

### iCloud behavior
Some iCloud files may need downloading before playback. Expect delays and failure states.

## Suggested components
- `LocalVideoPickerView`
- `LocalVideoImporter`
- `LocalVideoAccessManager`
- `LocalVideoMetadataService`
- `LocalPlaybackRepository`

## Implementation steps
1. Build button to open file importer
2. Limit to movie/video types, initially `.mp4`
3. Test local file selection
4. Test iCloud file selection
5. Start playback with `AVPlayer`
6. Save last playback time every few seconds and on app background
7. Restore playback time when reopening same file
8. Store bookmarks for reopening if needed

## Risks
- iCloud files may not be fully available immediately
- Bookmark persistence can become tricky if files move
- Some containers may import fine but fail to play

---

# 9.3 Player

This is the core of the app. Build it early and build it carefully.

## Functional requirements
- Play/pause/seek
- Show current time and duration
- Restore last watched timestamp
- Save progress
- Work with local file URLs and remote HTTP URLs
- Be reusable across local, web-direct, and DLNA-direct playback

## Suggested components
- `PlayerView`
- `PlayerViewModel`
- `PlaybackCoordinator`
- `PlaybackProgressStore`
- `PlayerContainerView`
- `ImmersivePlaybackCoordinator`

## Core behaviors
- Auto-resume if saved timestamp exists
- Periodic time observer every few seconds
- Save on:
  - periodic timer
  - pause
  - app background
  - leaving player
- Mark item complete if near the end, and optionally clear resume point

## AVPlayer integration notes
- Wrap `AVPlayer`
- Observe status and buffering state
- Handle `AVPlayerItemFailedToPlayToEndTime`
- Surface readable error messages

## Recommended playback abstraction

```swift
protocol PlayableMediaSource {
    var playbackID: PlaybackItemID { get }
    var title: String { get }
    var streamURL: URL { get }
    var subtitle: String? { get }
}
```

Then implement:
- `LocalPlayableMedia`
- `DLNAPlayableMedia`
- possibly `DirectWebPlayableMedia` later

This keeps the player independent from source type.

---

# 9.4 Web Video

## Functional requirements
- Enter URL
- Open website
- Let user interact with webpage
- Let website play video inside embedded browser
- Provide pleasant viewing experience in Vision Pro

## Constraints
Web playback is the least predictable part, because:
- every site behaves differently
- some sites block embedding
- some sites require auth
- some videos are not accessible as direct AVPlayer streams
- DRM content may not behave as expected

For MVP, treat this as:
- **A built-in browser page dedicated to video websites**

## Suggested components
- `WebEntryView`
- `WebBrowserView`
- `WebBrowserViewModel`
- `WKWebViewRepresentable`

## Important implementation notes

### Use WKWebView
You will likely need:
- inline media playback enabled
- media playback without user gesture only if allowed
- navigation delegate
- progress / loading state
- back / forward / refresh controls

### UX recommendation
After URL entry:
- push to browser screen
- provide simple controls:
  - address field
  - back
  - forward
  - reload
  - open in Safari optionally in future

## Future path
Later, if you want richer control:
- detect direct video URLs
- extract playable streams where legal and technically appropriate
- route direct streams into your native AVPlayer

Do not start there. Start with reliable browser embedding.

---

# 9.5 DLNA Media Server

This is the most technically involved part outside playback.

## Functional requirements
- Discover DLNA/UPnP media servers on local network
- Show server list
- Browse folders/containers
- Show videos
- Play selected `.mp4` media resource

## DLNA/UPnP concepts you need
- **SSDP** for server discovery
- **Device description XML**
- **ContentDirectory service**
- **SOAP requests** for browsing
- **DIDL-Lite XML** parsing for media items and containers

## Suggested components
- `DLNADiscoveryService`
- `DLNADevice`
- `DLNAContentDirectoryService`
- `DLNABrowserViewModel`
- `DLNAObject`
- `DIDLParser`

## Discovery flow
1. Send SSDP M-SEARCH to multicast
2. Receive device responses
3. Fetch device description XML
4. Extract:
   - friendly name
   - UUID
   - services
   - ContentDirectory control URL
5. Keep discovered devices in memory
6. Show list in UI

## Browsing flow
1. User taps server
2. Browse root container `"0"`
3. Send SOAP `Browse` request
4. Parse containers and items from DIDL-Lite
5. Show folders and playable items
6. Navigate deeper through container IDs

## Playback flow
1. User taps media item
2. Extract playable resource URL
3. Pass URL to `AVPlayer`
4. Save progress against stable DLNA content identifier

## Networking and permissions
- Local network permission is required
- DLNA devices often vary in standards compliance
- Expect quirks across Synology, Windows media sharing, Plex DLNA, etc.

## MVP simplifications
- Read-only browsing
- Only support items with direct HTTP resource URLs
- Prefer first playable `res` element
- Ignore transcoding profiles initially
- Only display video items

## Risks
- XML namespaces and parser complexity
- Some servers respond with inconsistent metadata
- Some files may advertise playable MIME types but fail in AVPlayer

---

## 10. Persistence Strategy

Use a simple persistence layer from day one.

## What to store
- Resume positions
- Recent items
- Local file bookmarks if reopening is needed
- Last entered URLs
- Optional user preferences

## Recommended storage split
- **SwiftData** for structured entities
- **UserDefaults** only for trivial preferences

## Suggested entities
- `ResumePlaybackEntity`
- `RecentItemEntity`
- `BookmarkedFileEntity`
- `AppPreferenceEntity`

## Resume save policy
Save at:
- every 5–10 seconds during playback
- pause
- scene phase change
- player dismissal

Avoid saving every second.

---

## 11. Permissions and Platform Concerns

## Required permissions
- **Local network access** for DLNA discovery
- File access via importer / security-scoped bookmarks

## visionOS-specific concerns
- Window sizing and viewing comfort matter a lot
- Avoid cluttered multi-pane UI at first
- Favor large tap targets and legible typography
- Playback view should feel calm and focused

## Browser concerns
- Some websites may not allow the same behavior as Safari
- Fullscreen behavior inside `WKWebView` may vary

---

## 12. Project Setup Roadmap

# Stage 0 — Blank project setup
Create a new visionOS app using SwiftUI.

## Deliverables
- Base app launches
- Home screen exists
- Navigation skeleton exists
- App folders organized

## Tasks
- Create project
- Set deployment target
- Create folder structure
- Add route enums and view placeholders
- Add app theme / spacing constants

---

# Stage 1 — Build the player foundation first
Do this before DLNA or advanced web work.

## Deliverables
- Reusable player screen
- `AVPlayer` playback from URL
- Resume position save / restore
- Error state handling

## Tasks
- Build `PlayerView`
- Create `PlaybackItemID`
- Create playback progress storage
- Add time observer
- Add resume-on-open logic
- Add test with bundled sample MP4 and remote MP4 URL

## Why first
If playback is unstable, every source feature will also be unstable.

---

# Stage 2 — Local video MVP
## Deliverables
- File picker
- Open local/iCloud MP4
- Play selected file
- Resume playback per file

## Tasks
- Add file importer
- Restrict supported formats to MP4
- Add bookmark handling if needed
- Integrate with player
- Save recent items
- Handle iCloud availability edge cases

## Exit criteria
- User can open an MP4 from Files and resume where they stopped

---

# Stage 3 — Web video MVP
## Deliverables
- URL entry screen
- Embedded browser
- Website video playback in app

## Tasks
- Add URL input validation
- Build `WKWebView` wrapper
- Configure media playback options
- Add navigation controls
- Save recent URLs
- Test several common video sites

## Exit criteria
- User can paste a URL, navigate, and play a webpage video

---

# Stage 4 — DLNA discovery MVP
## Deliverables
- Discover DLNA servers
- Show server list

## Tasks
- Request local network permission
- Implement SSDP M-SEARCH
- Parse discovery responses
- Fetch device description XML
- Extract media server info
- Display device list with refresh support

## Exit criteria
- App reliably shows at least common DLNA servers on local network

---

# Stage 5 — DLNA browsing MVP
## Deliverables
- Browse root and nested folders
- Show playable video items

## Tasks
- Build SOAP browse requests
- Parse DIDL-Lite XML
- Support folders vs items
- Add list navigation
- Extract resource URLs and titles

## Exit criteria
- User can navigate server folders and reach video items

---

# Stage 6 — DLNA playback integration
## Deliverables
- Play DLNA MP4 items
- Save and restore progress

## Tasks
- Convert DLNA item into common playable model
- Reuse existing player
- Save resume positions
- Handle unavailable URLs and playback failures

## Exit criteria
- User can browse DLNA and watch MP4 with progress resume

---

# Stage 7 — Vision Pro viewing refinement
## Deliverables
- Better playback presentation
- Environment-friendly viewing experience

## Tasks
- Tune player window size and controls
- Add “watching mode” UI
- Explore immersive environment support
- Make sure controls remain comfortable in spatial UI
- Test lighting/readability and distraction levels

## Exit criteria
- Watching feels pleasant in Vision Pro, not just technically functional

---

## 13. Suggested Milestones

## Milestone A — Core playback prototype
- Home screen
- Reusable player
- Resume save/restore
- Sample video playback

## Milestone B — Local video complete
- File picker
- iCloud support
- Recent items
- Resume playback

## Milestone C — Web browsing complete
- URL entry
- Embedded website playback
- Basic browser controls

## Milestone D — DLNA complete
- Discovery
- Browsing
- Playback
- Resume for DLNA items

## Milestone E — Vision Pro polish
- Better layouts
- Playback comfort improvements
- Environment support refinement

---

## 14. Suggested View Models and Services

## View models
- `HomeViewModel`
- `LocalVideoViewModel`
- `WebBrowserViewModel`
- `DLNAServerListViewModel`
- `DLNABrowserViewModel`
- `PlayerViewModel`

## Services
- `PlaybackProgressService`
- `RecentItemsService`
- `FileBookmarkService`
- `DLNADiscoveryService`
- `DLNADeviceDescriptionService`
- `DLNAContentDirectoryService`

## Parsers
- `DeviceDescriptionXMLParser`
- `DIDLParser`
- `SSDPResponseParser`

---

## 15. Important Technical Decisions to Make Early

## A. Persistence choice
Choose one:
- **SwiftData**
- or simple JSON persistence first

### Recommendation
Use **SwiftData** if you are comfortable with it.  
Use JSON-backed persistence if you want faster iteration early.

## B. Web view scope
Choose whether web video is:
- just an embedded browser
- or also a future direct-stream extractor path

### Recommendation
Start as **embedded browser only**.

## C. DLNA implementation level
Choose whether you want:
- a minimal read-only browser
- or a broader UPnP abstraction

### Recommendation
Start with **minimal DLNA-only read-only browsing**.

## D. Immersive strategy
Choose whether the player:
- only lives in a normal window initially
- or immediately includes custom immersive scenes

### Recommendation
Start with **window-first**, then add immersive refinement later.

---

## 16. Risks and Mitigations

## Risk: Web video inconsistency
Some sites will not behave well in embedded web views.

### Mitigation
- keep expectations modest
- test with a handful of target sites
- design this as “browser-based viewing,” not guaranteed universal playback

## Risk: DLNA device differences
Different servers implement UPnP differently.

### Mitigation
- test with at least 2–3 server types
- write tolerant XML parsing
- log raw responses in debug builds

## Risk: Resume position identity drift
If IDs change, resume breaks.

### Mitigation
- define stable IDs early
- make source-specific identity generation deterministic

## Risk: MKV expansion later
MKV may not play the same way as MP4.

### Mitigation
- keep file filtering and playback capability checks abstracted
- do not bake MP4 assumptions into every layer

---

## 17. Testing Plan

## Manual testing matrix

### Local
- local MP4
- iCloud MP4 already downloaded
- iCloud MP4 not yet downloaded
- reopening same file restores position
- moved or deleted file behavior

### Web
- valid URL
- invalid URL
- site with inline HTML5 video
- site with navigation redirects
- back/forward/reload behavior

### DLNA
- no servers found
- one server found
- multiple servers found
- browse nested folders
- item with valid resource URL
- item with unsupported format
- server disappears during use

### Player
- pause/resume
- scrub seek
- background/foreground save
- end-of-video behavior
- network interruption for remote media

---

## 18. Development Order I Recommend

Build in this order:

1. **App shell + navigation**
2. **Reusable native player**
3. **Resume persistence**
4. **Local file picker**
5. **Recent items**
6. **Web URL input + browser**
7. **DLNA discovery**
8. **DLNA browsing**
9. **DLNA playback**
10. **Vision Pro polish**
11. **Future formats like MKV**
12. **Future VR-specific playback**

This keeps the hardest unknowns from blocking basic progress.

---

## 19. Future Expansion Roadmap

After MVP is stable:

### Phase 2
- MKV support investigation
- subtitle support
- playback speed control
- recent/history improvements
- favorites/bookmarks

### Phase 3
- direct web stream detection where appropriate
- better metadata display
- thumbnails/posters
- folder favorites for local/DLNA

### Phase 4
- VR video handling
- stereoscopic / 180 / 360 playback modes
- custom immersive playback scenes
- richer spatial controls

---

## 20. Concrete First Week Plan

## Day 1
- Create blank visionOS SwiftUI project
- Build folder structure
- Build Home screen with three source cards

## Day 2
- Build reusable `PlayerView`
- Play a bundled MP4 and a remote MP4 URL

## Day 3
- Add playback progress save/restore
- Add recent items model and persistence

## Day 4
- Add local file importer
- Open selected MP4 and resume playback

## Day 5
- Add URL entry and `WKWebView` wrapper
- Test website video playback

## Day 6
- Implement SSDP discovery prototype
- Show DLNA server list

## Day 7
- Start ContentDirectory browse request and DIDL parsing

---

## 21. Recommended MVP Definition

You should consider MVP complete when the following are true:

- User can launch NookPlay and choose **Local**, **Web**, or **Media Server**
- User can import and play a **local/iCloud MP4**
- User can paste a URL and view/play web video through an embedded browser
- User can discover and browse at least one **DLNA server**
- User can play a **DLNA MP4**
- Playback position is saved and restored for local and DLNA items
- App feels comfortable to use in Vision Pro windowed viewing

---

## 22. Final Recommendation

The most important decision is to make **playback a shared core**, and treat local, web, and DLNA as separate **content source adapters** feeding into that core.

That means:

- one player
- one resume system
- one recent-items system
- different source modules

That structure will make future additions like MKV, subtitles, Jellyfin, SMB, or VR video much easier.

---

## 23. Starter File List

```text
NookPlayApp.swift
AppRouter.swift

HomeView.swift
HomeViewModel.swift

PlayerView.swift
PlayerViewModel.swift
PlaybackCoordinator.swift
PlaybackProgressService.swift

LocalVideoView.swift
LocalVideoImporter.swift
FileBookmarkService.swift

WebEntryView.swift
WebBrowserView.swift
WKWebViewRepresentable.swift

DLNAServerListView.swift
DLNAServerListViewModel.swift
DLNABrowserView.swift
DLNABrowserViewModel.swift
DLNADiscoveryService.swift
DLNAContentDirectoryService.swift
DIDLParser.swift

PlaybackItemID.swift
RecentItem.swift
ResumeEntry.swift
```

---

## 24. Practical Advice Before You Start Coding

Keep the first version intentionally narrow:

- support **MP4 first**
- make **native player solid first**
- make **DLNA browse-only and simple first**
- treat **web video as embedded browsing first**
- add immersive refinements after the basics are reliable

That will give you a strong base instead of three half-working playback systems.
