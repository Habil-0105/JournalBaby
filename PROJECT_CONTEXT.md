# Project Context

## 1. Project Overview

**MiroCloneiPad** is a single‑screen iPad application that mimics the core "freeform whiteboard" experience of tools like Miro / FigJam / Apple Freeform. It is an entirely client‑side, offline SwiftUI app — there is no backend, no account, no sync.

The product surface is intentionally minimal:

- A **horizontal page carousel** (`PageCarouselView`) — pages are rendered at a reduced, paper‑like size, with the previous and next page peeking in on each side and a dynamic page number under each. The rightmost slot, when on the last page, becomes a dashed "Add Page" card.
- Each page is a freeform canvas (`PageContentView`) where the user places and arranges discrete blocks.
- Three block kinds: **text** (auto‑growing notes), **image** (from the Photos library), **audio** (microphone recordings).
- A **Scribble / Draw mode** that drops the user into Apple PencilKit's native `PKCanvasView` with the system `PKToolPicker`, identical to what Notes and Freeform ship.
- Page navigation is by **swipe** (DragGesture), by tapping a side page, by tapping the dashed "Add Page" card, or by tapping the red "Delete" pill on the current page.

Each block owns its own position (top‑left) and size on its page. There is no flow layout, no paging, no reflow — moving, adding or deleting a block never affects another block's placement. This is the deliberate design pivot from earlier git history (an earlier "pages" / 2‑page / 3D‑switch design was removed in commits `b87737e`, `d3ecd86`, `99ff378` and re‑introduced as a flatter multi‑page model — see §6/§11).

**Current state:** Working iOS app, builds in Xcode 26.6, targeted at iOS 17.6+, Swift 5, supports iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`). It is in active development but already feature‑complete for the three block kinds + Scribble + multi‑page carousel. (Pinch‑to‑zoom was removed in a prior commit — see §18.)

## 2. Technology Stack

| Layer            | Choice                                                       |
|------------------|--------------------------------------------------------------|
| Language         | Swift 5 (strict concurrency features enabled)               |
| UI framework     | SwiftUI (with two `UIViewRepresentable` bridges)            |
| Drawing          | PencilKit (`PKCanvasView`, `PKToolPicker`, `PKDrawing`)      |
| Media capture    | `AVFoundation` (`AVAudioRecorder`, `AVAudioPlayer`)         |
| Photo picker     | PhotosUI (`PhotosPicker`)                                    |
| Persistence      | Local filesystem (`FileManager` → Documents/Images & Documents/Audio) — there is **no SQLite, Core Data, or SwiftData** in this project |
| Minimum iOS      | 17.6                                                          |
| Build tool       | Xcode 26.6 (project format `objectVersion = 77`)             |
| Dependency mgmt  | None — zero Swift Package Manager dependencies, no CocoaPods |
| Architecture     | MVVM‑ish: `CanvasStore` (`ObservableObject`) is the single source of truth; SwiftUI views observe and re‑render |
| Concurrency      | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (UI‑bound by default) |
| Code signing     | Automatic, `DEVELOPMENT_TEAM = 275W6TG8C4`, bundle id `habil.MiroCloneiPad` |
| App capabilities | App Sandbox enabled, Hardened Runtime enabled, User‑Selected Files = readonly |

## 3. Project Structure

```
/Users/habil/Coding/iOS/MiroCloneiPad
├── MiroCloneiPad.xcodeproj/         Xcode project (uses PBXFileSystemSynchronizedRootGroup,
│                                     so the folder layout *is* the project layout)
│   └── project.xcworkspace/
├── MiroCloneiPad/                   Source root
│   ├── App/
│   │   └── MiroCloneApp.swift       @main App entry; launches JournalView
│   ├── Features/
│   │   └── Journal/                 The only feature module
│   │       ├── JournalView.swift    Top‑level screen + toolbar; embeds PageCarouselView
│   │       ├── Models/
│   │       │   ├── Page.swift              One page: id + elements + scribble
│   │       │   ├── CanvasElement.swift     Codable struct for one block
│   │       │   └── CanvasStore.swift       ObservableObject — single source of truth
│   │       ├── Canvas/
│   │       │   ├── PageCarouselView.swift     Horizontal page carousel + swipe nav + add
│   │       │   ├── PageContentView.swift      One page's surface (current = interactive, neighbors = static preview)
│   │       │   ├── ElementContainerView.swift Per‑block chrome: selection, drag, resize handles
│   │       │   └── ScribbleCanvasView.swift   UIViewRepresentable wrapping PKCanvasView (current page only)
│   │       └── Elements/
│   │           ├── TextElementView.swift      SwiftUI host for AutoGrowingTextView
│   │           ├── AutoGrowingTextView.swift  UIViewRepresentable wrapping UITextView
│   │           ├── ImageElementView.swift     Loads UIImage from Documents/Images
│   │           ├── AudioElementView.swift     Play/pause UI + AudioPlaybackManager
│   │           └── AudioRecorderSheet.swift   Modal sheet + AudioRecorderManager
│   ├── Shared/
│   │   └── DesignSystem.swift       Centralised spacing/sizing tokens
│   └── Assets.xcassets/             AppIcon + AccentColor (placeholders)
└── DerivedData/                     Xcode build output (not part of source)
```

### Directory responsibilities

- **`App/`** — Application bootstrap only.
- **`Features/Journal/`** — All product behavior lives here. Split into `Models/` (data + store), `Canvas/` (the page navigation + board surfaces), `Elements/` (the three block kinds). The split keeps each layer addressable.
- **`Shared/`** — Cross‑feature tokens. Currently just `DesignSystem`. Designed so future features (e.g. multiple boards, settings) can pull from the same source of constants.
- **`Assets.xcassets/`** — `AppIcon` and `AccentColor` slots are empty placeholders generated by Xcode; no custom images shipped.

## 4. Architecture

The app is a thin, single‑layer SwiftUI app with one global `ObservableObject` driving the whole UI.

```text
MiroCloneApp (@main)
   └─► JournalView            (top‑level SwiftUI screen, owns CanvasStore)
         ├─► PageCarouselView        (horizontal page carousel; swipe / tap navigation; add + delete UX)
         │     └─► PageContentView × N+1
         │           ├─► ScribbleCanvasView  (only on the current page; PKCanvasView + toolPicker)
         │           └─► ElementContainerView × M  (one per CanvasElement on that page)
         │                 └─► TextElementView | ImageElementView | AudioElementView
         ├─► PhotosPicker (toolbar)
         └─► AudioRecorderSheet (modal)
                  └─► AudioRecorderManager / AudioPlaybackManager (AVFoundation)
```

**Core data flow**

- `CanvasStore` (`@Published` `pages`, `currentPageIndex`, plus UI state `selectedElementID`, `focusedTextID`, `drawMode`, `canvasSize`) is the **single source of truth**.
- `elements` and `scribble` on the store are **computed accessors** into `pages[currentPageIndex]` so views keep reading `store.elements` / `store.scribble` without knowing which page is current. `scribble` has a custom setter that writes back to the current page.
- `PageCarouselView` and every `PageContentView` / `ElementContainerView` observe the store via `@ObservedObject`.
- All mutations go *into* the store via methods (`addText`, `addImage(data:)`, `addAudio(fileURL:duration:)`, `moveElement`, `setWidth`, `setHeight`, `setTextHeight`, `updateElementText`, `select`, `focusText`, `clearTextFocus`, `toggleDrawMode`, `remove`, `updateCanvasSize`, `addPage`, `switchToPage(at:)`, `removePage(at:)`).
- Position is a **stored** property on `CanvasElement`, not derived — this is what makes "moving one block never affects another" trivially true.

**Concurrency model**

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` means every `@Published` mutation happens on the main thread; `@MainActor` isolation is implicit.
- The only off‑main work is `Task { … await newItem.loadTransferable(type: Data.self) … }` in `JournalView` when a photo is picked.

## 5. Application Entry Points

**File:** `MiroCloneiPad/App/MiroCloneApp.swift`

```swift
@main
struct MiroCloneApp: App {
    var body: some Scene {
        WindowGroup { JournalView() }
    }
}
```

There is exactly one entry point: `@main MiroCloneApp`. The whole UI is built inside `JournalView`, which is initialised with a fresh `CanvasStore` via `@StateObject`. There is no AppDelegate, no SceneDelegate, no dependency injection container.

**Startup sequence (effectively):**

1. iOS launches `MiroCloneApp.main`.
2. `JournalView` is constructed; `@StateObject` creates `CanvasStore` (one empty `Page`, `currentPageIndex = 0`, `drawMode = false`).
3. `NavigationStack` + `PageCarouselView` lay out. `PageCarouselView` reports its computed `pageSize` (≈ 45% of container width, height‑limited) to `store.updateCanvasSize`.
4. Toolbar items are bound immediately; nothing is fetched because there is no remote data.

## 6. Core Modules

### CanvasStore (`Features/Journal/Models/CanvasStore.swift`)

- **Purpose:** Single source of truth for the entire journal screen.
- **Responsibilities:**
  - Hold `[Page]`, `currentPageIndex`, plus UI‑only state (`selectedElementID`, `focusedTextID`, `drawMode`, `canvasSize`).
  - Expose `currentPage`, `elements`, and `scribble` as computed accessors so views keep reading `store.elements` / `store.scribble` instead of reaching into a specific page index. `scribble` has a custom setter that writes back to the current page.
  - Add text / image / audio elements (on the current page) with cascading default positions (`nextDefaultPosition`).
  - Manage pages: `addPage()`, `switchToPage(at:)`, `removePage(at:)`. The board always has at least one page; deleting the last one creates a fresh empty replacement. Switching pages clears `selectedElementID`/`focusedTextID`/`drawMode` because those don't carry across.
  - Persist image bytes to `Documents/Images/<UUID>.jpg` and audio bytes to `Documents/Audio/<UUID>.m4a`.
  - Move / resize / delete elements, with clamping against `canvasSize` and `DesignSystem.minBlockWidth/minBlockHeight`. Element lookup is currently scoped to the current page.
- **Depends on:** `Page`, `DesignSystem` (shared), `UIKit` (for `UIImage`), `PencilKit` (for `PKDrawing`).
- **Consumers:** `JournalView`, `PageCarouselView`, `PageContentView`, `ScribbleCanvasView`, `ElementContainerView`, `TextElementView`, `ImageElementView`, `AudioElementView`, `AudioRecorderSheet`.

### Page (`Features/Journal/Models/Page.swift`)

- **Purpose:** A single page on the board — owns its own elements and its own scribble layer so switching pages swaps the whole visible state, the way flipping between sheets of paper does.
- **Shape:** `id: UUID`, `elements: [CanvasElement]`, `scribble: PKDrawing`. Defaults to empty.
- Conforms to `Identifiable`, `Equatable`. (Not `Codable` yet — see §18.)

### CanvasElement (`Features/Journal/Models/CanvasElement.swift`)

- **Purpose:** Pure value type for one block.
- **Shape:** `id: UUID`, `kind: ElementKind` (text / image / audio), `position: CGPoint` (stored top‑left), `width`, `height`, optional `text`, `imageFileName`, `audioFileName`, `audioDuration`.
- **`frame` computed property** is used for both rendering and implicit hit testing.
- Conforms to `Identifiable`, `Codable`, `Equatable`. (Codable exists but the store does not currently encode/decode the array to disk — see §18.)

### PageCarouselView (`Features/Journal/Canvas/PageCarouselView.swift`)

- **Purpose:** Top‑level horizontal page navigator. Renders prev / current / next pages at a reduced size and handles swipe + tap navigation and add‑page UX.
- **Key behaviour:**
  - Computes a scaled `pageSize` from the container: width is min(45% of container width, 70% of container height / 1.3), height = width × 1.3 (tall sheet‑of‑paper aspect). Reports this `pageSize` to `store.updateCanvasSize`.
  - **Resting layout:** current page is centered (offset 0). Previous / next / Add Page slots are pushed down so only the top **20%** of each side page peeks above the container bottom — the current page dominates, side pages read as the top edge of a deck beneath it. Side pages are also slightly smaller (`scaleEffect(0.95)`) for a subtle deck‑of‑cards perspective.
  - **Transitions are driven by `visualPageIndex: CGFloat`.** This is a fractional page index that drives rendering for every slot. At rest it equals `CGFloat(store.currentPageIndex)`; during a swipe it tracks the drag 1:1; on commit it springs to the new integer (with overshoot). Each slot at index `i` computes `delta = i - visualPageIndex`; that single value drives both horizontal offset (`delta * spacing`) and vertical offset (`|delta| * neighborVerticalOffset`, clamped to 1.0).
  - **Swipe gesture** (`DragGesture(minimumDistance: 20)`) updates `visualPageIndex` from drag translation in `onChanged` (no animation, so the drag tracks the finger). In `onEnded`, if the drag crossed 25% of `spacing`, it commits by setting `store.currentPageIndex` (or `store.addPage()` when swiping into the Add Page slot). `onChange(of: store.currentPageIndex)` then animates `visualPageIndex` to the new value with a spring (`response: 0.32s`, `dampingFraction: 0.62` — fast, snappy, small overshoot, quick settle). If the drag didn't commit (under‑threshold release, out‑of‑bounds swipe, draw‑mode cancel), `springVisualToCurrent()` springs `visualPageIndex` back to `currentPageIndex` directly.
  - **Delete** is *not* part of this view — it's a pill on `PageContentView` (see below).
- **Layer constants (private):** `pageWidthFraction = 0.45`, `pageAspectRatio = 1.3`, `maxPageHeightFraction = 0.7`, `spacingFactor = 1.15`, `swipeThreshold = 0.25`, `neighborVisibleFraction = 0.2`, `sidePageScale = 0.05`, `transitionResponse = 0.32`, `transitionDamping = 0.62`.

### PageContentView (`Features/Journal/Canvas/PageContentView.swift`)

- **Purpose:** Renders one page: background, scribble layer (interactive or static), elements, and (when `isCurrent`) a delete pill.
- **Key behaviour:**
  - Stack (bottom → top): page background → scribble layer → elements → optional delete pill.
  - **Scribble layer branches on `isCurrent`:**
    - `isCurrent == true` → `ScribbleCanvasView(store:)` (interactive `PKCanvasView`).
    - `isCurrent == false` → `staticScribbleImage`: a snapshot produced by `page.scribble.image(from: pageSize rect, scale: UIScreen.main.scale)`. Returns `nil` (no image rendered) when the drawing's data is empty.
  - Element layer: `ForEach(page.elements)` renders each `ElementContainerView` at `element.position`. Hit‑testing is gated to `isCurrent && !drawMode` — neighboring pages are not interactive.
  - Owns the `"canvas"` coordinate space for its own bounds, so element drag/resize/PencilKit gestures read coordinates already in the page's own coordinate system.
  - **Delete pill:** red "Delete" `Capsule` button at the top of the current page; tap → `store.removePage(at: pageIndex)` (no confirmation dialog — destructive and immediate).
  - Tap on the page background (when current + not drawing) → `store.select(nil)`.

### ElementContainerView (`Features/Journal/Canvas/ElementContainerView.swift`)

- **Purpose:** Per‑block chrome and gesture host.
- **Key behaviour:**
  - Tap → `store.select(element.id)`.
  - Double‑tap (text) → `store.focusText(element.id)`.
  - Drag (when allowed) → writes straight to `store.moveElement(_:to:)` with `start + translation`; the visual frame, model position, and hit‑test rectangle are therefore *always* the same value (no temporary offset to reconcile).
  - Width handle (right edge) and height handle (bottom edge; image/audio only) for resize; text height is auto‑measured.
  - Delete button (top‑right) visible when selected.
  - `moveEnabled = !isText || !isFocused` — text is only draggable when not being edited.
  - All drag/handle gestures use `.coordinateSpace(.named("canvas"))`, which is declared by `PageContentView` (the immediate parent in the rendering tree) — so coordinates are already in the page's own coordinate system.

### ScribbleCanvasView (`Features/Journal/Canvas/ScribbleCanvasView.swift`)

- **Purpose:** `UIViewRepresentable` wrapping `PKCanvasView`, used only inside the current page's `PageContentView`.
- **Key behaviour:**
  - When `drawMode == true`: enables interaction, becomes first responder, shows `PKToolPicker`, registers it as observer.
  - When `drawMode == false`: hides tool picker, resigns first responder, disables interaction. Sits underneath the elements layer.
  - `drawingPolicy = .anyInput` (finger + Pencil, Notes‑style).
  - Delegate forwards `canvasViewDrawingDidChange` → `store.scribble = canvasView.drawing` (via the `lastAssignedDrawingData` echo‑skip — see below).
  - Tracks `boundPageID` of the drawing currently in the `PKCanvasView`. When `currentPageIndex` changes, `updateUIView` swaps `uiView.drawing = store.scribble`.
  - **Echo suppression via `lastAssignedDrawingData`:** whenever we programmatically assign a drawing, we stash its `dataRepresentation()`. The next `canvasViewDrawingDidChange` is only skipped when the new `canvasView.drawing` is byte‑equal to that — i.e., PencilKit's echo of our own assignment. Real user strokes are never byte‑equal, so they always reach the store.

### TextElementView + AutoGrowingTextView (`Features/Journal/Elements/`)

- **TextElementView** is a thin SwiftUI host.
- **AutoGrowingTextView** is a `UIViewRepresentable` around a non‑scrolling `UITextView`. Why: SwiftUI's native `TextEditor` doesn't give a reliable intrinsic size that wraps text correctly inside a fixed‑width block.
- Reports every height change via `onHeightChange → store.setTextHeight(_:height:)`. Because the text view is non‑scrolling and `sizeThatFits` is given an exact width, the block's frame is always the height of the actual text — no flow engine.
- Editing is opt‑in (`isEditable = isFocused`); `onFocusDidBegin/End` notifies the store so drag can take over again.
- `textContainer.widthTracksTextView = true` + an explicit `sizeThatFits(_:uiView:context:)` overrides the "types past the block" bug where SwiftUI gives a `UIViewRepresentable` no reliable intrinsic width.

### ImageElementView (`Features/Journal/Elements/ImageElementView.swift`)

- Loads `UIImage(contentsOfFile: store.imagesURL.appendingPathComponent(fileName).path)`; if the file is missing it renders a gray placeholder with a system photo icon.
- Image is `resizable()` and clips to the block bounds.

### AudioElementView + AudioPlaybackManager (`Features/Journal/Elements/AudioElementView.swift`)

- One play/pause button + duration label per audio block.
- `AudioPlaybackManager` is a per‑view `StateObject`. It configures `AVAudioSession` to `.playback`, instantiates an `AVAudioPlayer`, toggles play/stop, and forwards `audioPlayerDidFinishPlaying` → `isPlaying = false`.

### AudioRecorderSheet + AudioRecorderManager (`Features/Journal/Elements/AudioRecorderSheet.swift`)

- Modal sheet launched from `JournalView` toolbar.
- `AudioRecorderManager.requestPermissionAndStart()` calls `AVAudioSession.requestRecordPermission` (async callback dispatched to main). On grant it configures `.playAndRecord`, writes to `temporaryDirectory/<UUID>.m4a` with AAC at 44.1 kHz mono, and runs a 0.1 s timer for elapsed time.
- On stop, the temp file + duration are handed back to `store.addAudio(fileURL:duration:)`, which copies it into `Documents/Audio/<UUID>.m4a`.

### DesignSystem (`Shared/DesignSystem.swift`)

- Static tokens (`cornerRadius = 16`, `blockContentPadding = 16`, `minBlockWidth = 160`, `minBlockHeight = 90`, `defaultTextWidth = 360`, `defaultImageWidth = 320`, `defaultAudioWidth = 280`).
- One source of truth for sizing; every view pulls from here so a single change ripples.

## 7. Important Files

| File | Why it matters |
|------|---------------|
| `App/MiroCloneApp.swift` | The single `@main` entry point. |
| `Features/Journal/JournalView.swift` | Top screen; embeds `PageCarouselView`; wires the toolbar (add text/image/audio, toggle Scribble), presents the audio sheet, handles `PhotosPicker` data → `store.addImage(data:)`. |
| `Features/Journal/Models/Page.swift` | One page: owns its own elements + scribble layer. |
| `Features/Journal/Models/CanvasStore.swift` | All state (pages + current page + UI state), all mutations, file I/O for images & audio. The "brain". |
| `Features/Journal/Models/CanvasElement.swift` | The data shape; defines that `position` is stored (not derived). |
| `Features/Journal/Canvas/PageCarouselView.swift` | Horizontal page carousel; swipe / tap navigation; Add Page area on the last position. |
| `Features/Journal/Canvas/PageContentView.swift` | One page's surface; interactive scribble when current, static image when neighbor; owns the `"canvas"` coordinate space; red Delete pill. |
| `Features/Journal/Canvas/ElementContainerView.swift` | All per‑block gestures (select, drag, resize, delete). Writes position back to the store on every drag tick. |
| `Features/Journal/Canvas/ScribbleCanvasView.swift` | PencilKit + system `PKToolPicker` integration; `lastAssignedDrawingData` echo‑skip. |
| `Features/Journal/Elements/AutoGrowingTextView.swift` | Why text height matches content; opt‑in editing; the `sizeThatFits` override. |
| `Features/Journal/Elements/AudioRecorderSheet.swift` | Microphone permission flow + `AVAudioRecorder` setup. |
| `Features/Journal/Elements/AudioElementView.swift` | `AVAudioPlayer` + per‑view playback manager. |
| `Shared/DesignSystem.swift` | All sizing/padding tokens. |
| `MiroCloneiPad.xcodeproj/project.pbxproj` | Build settings (iOS 17.6, Swift 5, sandbox on, hardened runtime on, mic + photos usage descriptions, app groups registered). |

## 8. Data Flow

### Adding a block

```text
Toolbar tap (JournalView)
  ├─ text   ─► store.addText()         ─► CanvasElement(kind:.text, position:cascade(), width:360, height:90)
  ├─ image  ─► PhotosPicker           ─► Task { data = await newItem.loadTransferable(type:Data.self) }
  │                                       ─► store.addImage(data:)   ─► write Documents/Images/<UUID>.jpg
  │                                                                          ─► derive height from UIImage aspect ratio
  │                                                                          ─► CanvasElement(kind:.image, …)
  └─ audio  ─► AudioRecorderSheet     ─► AudioRecorderManager.stop()
                                          ─► store.addAudio(fileURL:duration:)
                                              ─► copy temp .m4a → Documents/Audio/<UUID>.m4a
                                              ─► CanvasElement(kind:.audio, width:280, height:120, duration)
                  ▼
              store.selectedElementID = newElement.id        (each add auto‑selects)
                  ▼
              PageCarouselView re-renders (PageContentView for current page picks up the new element)
```

### Dragging a block

```text
ElementContainerView (gesture = DragGesture(coordinateSpace: .named("canvas")))
  ├─ onChanged: dragStartPosition captured on first frame
  │             store.moveElement(id, to: start + translation)   ─► clamped against canvasSize
  └─ onEnded:   dragStartPosition = nil
                   ▼
        store.elements[i].position     ─► view re‑renders at new offset
```

### Switching pages (carousel)

```text
PageCarouselView swipe gesture
  ├─ onChanged (DragGesture, minimumDistance 20)
  │       guard !drawMode
  │       visualPageIndex = CGFloat(store.currentPageIndex)
  │                         + (-value.translation.width / spacing)
  │       ─► every slot recomputes offset = delta * spacing,
  │          y = |delta| * neighborVerticalOffset,
  │          scale = 1 - 0.05 * |delta|
  │       ─► pages visibly rise from their lower resting position
  │          toward the center as the swipe progresses
  └─ onEnded
          let direction: CGFloat = value.translation.width < 0 ? +1 : -1
          let shouldCommit = abs(value.translation.width) > threshold (0.25 * spacing)

          if shouldCommit:
            if proposedIndex in [0, pages.count) → store.currentPageIndex = proposedIndex
            if proposedIndex == pages.count       → store.addPage()
            if proposedIndex < 0                  → springVisualToCurrent()
          else:
            springVisualToCurrent()

          springVisualToCurrent() = withAnimation(.spring(0.32, 0.62)):
              visualPageIndex = CGFloat(store.currentPageIndex)

store.currentPageIndex change:
  ─► onChange(of: store.currentPageIndex):
        if |delta| ≤ 1.5 → withAnimation(.spring(0.32, 0.62)): visualPageIndex = new
        else             → visualPageIndex = new  (snap, e.g. after a delete-and-replace)

Tapping a side page or pressing Add Page button:
  ─► store.switchToPage(at: that index)  /  store.addPage()
  ─► onChange of currentPageIndex animates visualPageIndex

store.switchToPage(at:) sets:
  currentPageIndex = index
  selectedElementID = nil
  focusedTextID = nil
  drawMode = false

ScribbleCanvasView.updateUIView on currentPageIndex change
  ─► boundPageID != current page ID
  ─► lastAssignedDrawingData = store.scribble.dataRepresentation()
  ─► uiView.drawing = store.scribble            (swap the PencilKit drawing)
  ─► boundPageID = currentPageID
```

The deck‑style feel comes from `|delta|` driving both the y offset and the scale at the same time: a page moving from slot 0 (deep right) toward slot 1 (center) interpolates linearly upward while the next‑page slot takes its place going down. The spring on commit adds a small overshoot (the new current briefly nudges past center and settles back).

Note: elements stay in their own coordinate system because `PageContentView` declares the `"canvas"` coordinate space per‑page. Element positions are not reflowed when the page's size changes — they stay where the user placed them.

### Adding / deleting a page

```text
Adding:
  PageCarouselView Add Page area tap (right of last page)
  ─► store.addPage()       ─► pages.append(Page())
                              ─► switchToPage(at: pages.count - 1)
  or: swipe-left past last page
  ─► store.addPage()       (same as above)

Deleting (current page only, no confirmation):
  PageContentView Delete pill tap (top of current page)
  ─► store.removePage(at: pageIndex)
        ─► pages.remove(at: index)
        ─► if pages.isEmpty → pages = [Page()]; currentPageIndex = 0
        ─► index fixup of currentPageIndex (clamp to last, or decrement if deleting before current)
        ─► clear selection / focusedTextID / drawMode
```

### Editing text

```text
Double‑tap on text block
  ─► store.focusText(id) ─► focusedTextID = id, drawMode = false
        ─► TextElementView / AutoGrowingTextView: isEditable = true → becomeFirstResponder
            ─► UITextViewDelegate.textViewDidChange ─► store.updateElementText + recalculateHeight
                                                         ─► store.setTextHeight(id, height:)
                                                             ─► element.height updated → frame matches content
        ─► store.clearTextFocus(id) on end editing ─► dragging the block is allowed again
```

### Audio playback

```text
AudioElementView "play" button
  ─► AudioPlaybackManager.toggle(url:)   ─► AVAudioSession(.playback)
                                          ─► AVAudioPlayer(contentsOf:)
                                          ─► isPlaying = true
        ─► audioPlayerDidFinishPlaying ─► isPlaying = false
```

### Pencil / Scribble

```text
Toggle Scribble toolbar button
  ─► store.toggleDrawMode() ─► drawMode = true, selectedElementID = nil, focusedTextID = nil
        ─► ScribbleCanvasView.setDrawMode(true, on:)
              ─► toolPicker.addObserver / setVisible(true, forFirstResponder:)
              ─► PKCanvasView.becomeFirstResponder()      (system tool picker appears)
        ─► canvasViewDrawingDidChange
              ─► if drawing byte-equals lastAssignedDrawingData → echo, skip
              ─► else → store.scribble = canvasView.drawing

Toggle off  ─► toolPicker hidden, PKCanvasView resigns first responder, interaction disabled,
               element layer becomes hit‑testable again.
```

### Rendering non-current pages

```text
For each non-current page, PageContentView computes:
  staticScribbleUIImage = page.scribble.image(from: pageSize rect, scale: UIScreen.main.scale)
  (returns nil if page.scribble.dataRepresentation() is empty)
Then renders Image(uiImage:).resizable().scaledToFill() at the page's offset in the carousel.
This means switching pages is just a layout update — no PKCanvasView is created for non-current pages.
```

## 9. Major Business Logic

1. **Position is the single source of truth for layout.** No derived positions, no reflow, no flow layout. `CanvasElement.position` is read for rendering, hit testing, and the drag gesture's write‑back.
2. **Drag writes on every tick, not on commit.** The drag's `onChanged` calls `store.moveElement` with the current `start + translation`, so model / visual / hit‑test rectangle are always in lockstep — no temporary visual offset to reconcile on `onEnded`.
3. **Cascading default placement for new blocks.** `nextDefaultPosition()` is a creation‑time convenience (`(inset + col*spacing, inset + row*spacing)`); once created, the element owns its position.
4. **The board renders at a fixed 1:1 scale.** There is no zoom or pan. Element drag, width/height handles, and PencilKit touches all read the `"canvas"` named coordinate space directly. Because `PageCarouselView` reports a *scaled-down* `pageSize` (≈ 45% of container width) to `store.updateCanvasSize`, the effective element coordinate space is also that scaled size — element positions are clamped against the page's own size, not the screen's.
5. **Draw mode is exclusive.** Selecting any element exits Draw mode; toggling Draw mode clears selection and text focus. Elements are non‑interactive while Draw mode is on.
6. **Text editing is opt‑in and isolated.** A text block is draggable when *not* focused, so caret/selection gestures always win during editing. Height is auto‑measured (`AutoGrowingTextView.sizeThatFits` + `recalculateHeight` → `store.setTextHeight`).
7. **Scribble strokes live in their own layer.** `store.scribble: PKDrawing` is independent of `elements`; PencilKit is the source of truth while Draw mode is on. Only the current page instantiates a `PKCanvasView`; neighbor pages render their scribbles as a static `UIImage` snapshot.
8. **Block content lives in the Documents directory.** Image bytes are written directly into `Documents/Images/<UUID>.jpg`; audio is copied from a temp recording into `Documents/Audio/<UUID>.m4a`. The `CanvasElement` stores only the file name.
9. **Min/max constraints.** Elements are clamped to `minBlockWidth × minBlockHeight` and to the (scaled) page's `canvasSize` on resize and drag.
10. **Pages are independent sheets of state.** `pages[currentPageIndex]` is what every element + scribble mutation reads and writes; switching pages clears UI‑only state (selection, text focus, draw mode) because that state can't follow across. The board always has at least one page; deleting the only page inserts a fresh empty replacement. The `PKCanvasView`'s drawing is swapped in lock‑step with `currentPageIndex` change (echo suppression by byte‑equality, so PencilKit doesn't echo the swap back into the store).
11. **UI‑state vs page‑state split.** Pages own their `elements` and `scribble`; selection, text focus, draw mode, and canvas size are global because they're tied to the user/UI, not the page.
12. **Page navigation is multi-modal.** A user can switch pages by (a) swiping horizontally on the carousel, (b) tapping a side page, (c) tapping the dashed "Add Page" card on the last position, or (d) swiping left past the last page (auto-creates the next). All paths go through `CanvasStore.switchToPage(at:)` or `CanvasStore.addPage()`.
13. **Page deletion is destructive and immediate.** A red "Delete" pill sits at the top of the current page; tapping it calls `CanvasStore.removePage(at:)` directly with no confirmation. The store still guarantees "at least one page" via its existing fallback.
14. **The carousel is a deck, not a horizontal scroll.** Side pages sit at a deep y offset such that only their top 20% peeks above the container bottom; current page is centered and slightly larger (`scale = 1.0` vs `0.95` for neighbors). A single `visualPageIndex: CGFloat` drives both horizontal and vertical offset, so a swipe makes pages visibly rise from their lower position toward center instead of sliding horizontally.

## 10. API / Routes

**None.** This is a fully offline single‑screen app. No HTTP, no network code, no backend. The "routes" that exist are user actions routed through SwiftUI → `CanvasStore`:

| Action surface         | Code path                                                          |
|------------------------|--------------------------------------------------------------------|
| Add text               | `JournalView` toolbar → `store.addText()`                          |
| Add image              | `PhotosPicker` → `Task { await loadTransferable(type:Data.self) }` → `store.addImage(data:)` |
| Add audio              | `AudioRecorderSheet` → `AudioRecorderManager.stop()` → `store.addAudio(fileURL:duration:)` |
| Toggle Scribble        | `store.toggleDrawMode()` → `ScribbleCanvasView.setDrawMode(_:on:)` |
| Select element         | `store.select(id)`                                                  |
| Edit text              | double‑tap → `store.focusText(id)`                                  |
| Move element           | drag → `store.moveElement(id, to:)`                                |
| Resize element         | width/height handle drag → `store.setWidth` / `setHeight`          |
| Auto‑resize text       | `AutoGrowingTextView` → `store.setTextHeight(id, height:)`         |
| Delete element         | delete button → `store.remove(id)`                                  |
| Switch page (swipe)    | `PageCarouselView` `DragGesture` → `store.switchToPage(at:)` / `store.addPage()` (past last) |
| Switch page (tap)      | Tap a side `PageContentView` → `store.switchToPage(at:)`            |
| Add page (tap)         | Tap dashed "Add Page" card → `store.addPage()`                      |
| Add page (swipe)       | Swipe left past last page → `store.addPage()`                       |
| Delete page            | Tap red "Delete" pill on current `PageContentView` → `store.removePage(at:)` |

## 11. Database / Data Model

- **No database.** All persistence is filesystem‑based, via `FileManager`.
  - `Documents/Images/<UUID>.jpg` — image bytes written by `CanvasStore.addImage(data:)`.
  - `Documents/Audio/<UUID>.m4a` — recorded audio copied from the temporary directory by `CanvasStore.addAudio(fileURL:duration:)`.
- `CanvasElement` and `Page` are both value‑type structs (Element is `Codable`, Page is not yet). However, `CanvasStore.pages` is **not currently persisted across launches.** On app relaunch the canvas resets to a single empty page and the on‑disk images / audio files become orphaned. (See §18.)
- Entities:
  - `Page { id: UUID, elements: [CanvasElement], scribble: PKDrawing }` — owns a page's elements + drawing. Switching `currentPageIndex` swaps the visible state.
  - `CanvasElement { id, kind, position, width, height, text?, imageFileName?, audioFileName?, audioDuration? }` — one block. Position is stored.

## 12. Authentication & Authorization

None. No login, no account, no token, no permission gate beyond the OS‑level privacy prompts:

- `NSMicrophoneUsageDescription` ("This app needs microphone access to record audio notes on the board.") declared in both Debug and Release Info.plist (`INFOPLIST_KEY_NSMicrophoneUsageDescription`).
- `NSPhotoLibraryUsageDescription` ("This app needs photo library access so you can place images on the board.") declared the same way.
- Microphone permission is requested at runtime via `AVAudioSession.sharedInstance().requestRecordPermission` inside `AudioRecorderManager.requestPermissionAndStart()`.
- Photo library access is implicit through `PhotosPicker`, which does not require an `NSPhotoLibraryUsageDescription` in iOS 16+ but the project declares one anyway (harmless).

## 13. External Integrations

| Integration | Purpose | Where | Failure behavior |
|-------------|---------|-------|------------------|
| Apple Photos (via `PhotosPicker`) | Source of image bytes for new image blocks | `JournalView` toolbar | If load fails, the picker is silently dismissed; `store.addImage(data:)` is never called. |
| PencilKit (`PKCanvasView`, `PKToolPicker`, `PKDrawing`) | Free‑form drawing layer, system tool palette | `ScribbleCanvasView` (inside current `PageContentView`) | Wrapped in `UIViewRepresentable`; if PencilKit unavailable on the OS version this would crash — but iOS 17.6+ guarantees it. |
| AVFoundation (`AVAudioRecorder`, `AVAudioPlayer`) | Audio capture & playback | `AudioRecorderManager`, `AudioPlaybackManager` | Errors logged via `print("Recording error: …")` / `print("Playback error: …")`. No user‑facing error UI besides "Microphone access is disabled. Enable it in Settings…". |

No third‑party SDKs. No network. No analytics. No crash reporting.

## 14. Configuration & Environment

There is **no environment configuration layer** in the app — no `.plist` of keys, no `.xcconfig` files, no `Bundle.main.object(forInfoDictionaryKey:)` reads beyond what Apple manages. Build configuration is all in `project.pbxproj`.

Key build settings (verified from `MiroCloneiPad.xcodeproj/project.pbxproj`):

- `IPHONEOS_DEPLOYMENT_TARGET = 17.6`
- `MACOSX_DEPLOYMENT_TARGET = 26.5`
- `XROS_DEPLOYMENT_TARGET = 26.5`
- `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad)
- `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`
- `SWIFT_VERSION = 5.0`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`
- `ENABLE_APP_SANDBOX = YES`, `ENABLE_HARDENED_RUNTIME = YES`, `ENABLE_USER_SELECTED_FILES = readonly`
- `PRODUCT_BUNDLE_IDENTIFIER = habil.MiroCloneiPad`
- `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`
- `DEVELOPMENT_TEAM = 275W6TG8C4` (Apple developer team ID — not a secret, just identifies the signing team)
- `INFOPLIST_KEY_NSMicrophoneUsageDescription`, `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` set on both Debug and Release
- `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`, `STRING_CATALOG_GENERATE_SYMBOLS = YES` — there is no `.xcstrings` file in the repo yet, so all visible strings ("Journal", "Add Text", "Add Page", "Type here…", "Ready to record", "Delete", "Cancel", etc.) are hardcoded English literals inline.

There are no `.env`, no `Secrets.swift`, no API keys.

## 15. Testing

**There is no test target.** The `.xcodeproj/project.pbxproj` has only one native target (`MiroCloneiPad`, application), no `PBXNativeTarget` of test bundle type, no `Test` action, no `*.xcTest` files. `find` over the repo confirms no test files at all.

There is also no `Package.swift` and no SPM dependency that could bring testing infrastructure.

Verification today is manual, plus `#Preview { JournalView() }` is defined on `JournalView` to enable SwiftUI Previews.

## 16. Important Development Commands

Because there is no SPM, no CocoaPods, and no `Makefile`, the canonical commands are Xcode's. There is no build script in‑repo.

| Task | Command |
|------|---------|
| Open the project | `open MiroCloneiPad.xcodeproj` (or `xed MiroCloneiPad.xcodeproj`) |
| Build (Debug, simulator) | `xcodebuild -project MiroCloneiPad.xcodeproj -scheme MiroCloneiPad -configuration Debug -destination 'generic/platform=iOS Simulator' build` |
| Build (Release, device) | `xcodebuild -project MiroCloneiPad.xcodeproj -scheme MiroCloneiPad -configuration Release -destination 'generic/platform=iOS' build` |
| Run on simulator | `xcrun simctl boot … && xcodebuild … -destination 'platform=iOS Simulator,name=…' build` (then open the generated `.app` from `DerivedData/`) |
| Reset simulator | `xcrun simctl erase all` |
| Preview a view | Open the file in Xcode and use the canvas (e.g. `JournalView` has a `#Preview`) |

There is no `lint`, `format`, or `test` step wired into the project. There is no CI configuration file in the repo.

## 17. Important Conventions

These are patterns repeatedly used in the code that future work should follow:

1. **Store as the single source of truth.** Every state change goes through a `CanvasStore` method; views never mutate `CanvasElement` or `Page` directly. (`ElementContainerView` writes only via `store.moveElement`, `store.setWidth`, etc.)
2. **Stored position, no derived layout.** New block kinds or layout strategies should keep position stored on the element. Resist any "reflow on neighbour change" temptation.
3. **Drag‑writes‑on‑every‑tick.** Gestures that change geometry should update the model on `onChanged`, not on `onEnded` (matches `ElementContainerView.moveGesture`). This keeps the visual frame, hit test, and model position identical at all times.
4. **DesignSystem is the only place for sizing tokens.** Don't hardcode `cornerRadius`, `minBlockWidth`, padding, etc. in views.
5. **UIViewRepresentable wrappers are the bridge, not the model.** `AutoGrowingTextView` and `ScribbleCanvasView` are intentionally thin; all state lives in `CanvasStore` and is mirrored via delegate callbacks.
6. **Coordinate space per-page.** `PageContentView` declares `.coordinateSpace(.named("canvas"))`. Drag gestures inside `ElementContainerView` rely on this to read coordinates already in the page's own coordinate system. Don't move the declaration or wrap the page in a `scaleEffect` / `offset` modifier — element drag math is written against the page's 1:1 frame.
7. **Opt‑in editing for text blocks.** Anything that involves the caret / selection must check `isFocused` first so drag can take over otherwise.
8. **File‑backed content, name in the model.** Heavy media lives in `Documents/Images` / `Documents/Audio`; the `CanvasElement` only stores a filename. Future media kinds should follow the same pattern.
9. **Concurrency isolation.** Because `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, prefer keeping work on the main actor. The only off‑main work today is the `Task` around `PhotosPickerItem.loadTransferable`.
10. **No third‑party dependencies.** The project intentionally has none; don't add a SPM dependency for something SwiftUI/AVFoundation/PencilKit already covers.

## 18. Known Issues / Technical Debt

### Confirmed

- **No persistence of `CanvasStore.pages`.** `CanvasElement` is `Codable`, the store is `ObservableObject` with `@Published pages`, but no code reads or writes the page list to disk. On relaunch the canvas resets to a single empty page; the previously written image/audio files in `Documents/Images` and `Documents/Audio` are orphaned (no cleanup, no referencing record). `Page` itself isn't `Codable` yet either, so persisting it requires a tiny follow‑up.
- **No tests.** No test target, no `*Tests*` folders, no SPM `Testing` glue. (Verified by repo search and project inspection.)
- **Scribble strokes are not persisted.** `pages[i].scribble` is in‑memory only; closing/reopening the app loses every page's drawing. PencilKit itself could persist via `PKDrawing.dataRepresentation()` if desired.
- **No image/audio cleanup on page delete.** `CanvasStore.removePage(at:)` removes the `Page` (and its `elements`) but does not delete the underlying files at `Documents/Images/<fileName>` or `Documents/Audio/<fileName>`. Same issue applies to `CanvasStore.remove(id:)` for individual element deletes.
- **No undo/redo.** Despite PencilKit offering it natively for scribble, the app provides no undo for element moves/resizes/deletes or text edits.
- **Page deletion is destructive with no confirmation.** The red "Delete" pill on the current page calls `store.removePage(at:)` directly — a single tap destroys a page (and all its elements).
- **Logging is `print`-based** (`print("Failed to save image: …")`, `print("Recording error: …")`, `print("Playback error: …")`). No structured logging, no OSLog.
- **No localization infrastructure in place.** Strings are inline English literals; `STRING_CATALOG_GENERATE_SYMBOLS = YES` is set but no `.xcstrings` catalog is present yet.
- **`AudioPlaybackManager` per element.** Each `AudioElementView` creates its own `AudioPlaybackManager`. There's no shared audio session coordinator — playing two audio blocks simultaneously will both set the session to `.playback` and both play at once. The intent is unclear.
- **Carousel reports a scaled-down `canvasSize` to the store.** Because `PageCarouselView` calls `store.updateCanvasSize(pageSize)` with the paper‑like size (≈ 45% of container width), element drag/resize clamping uses that small size. Elements placed near the "right" edge of the user's view will hit the `canvasSize.width - element.width` clamp before reaching the visible page edge. The user has no visual cue that the coordinate space ends before the visible page does.
- **Neighboring pages re-render their static scribble image on every render.** `PageContentView.staticScribbleImage` calls `page.scribble.image(from:scale:)` per body evaluation. PencilKit's `PKDrawing.image(from:scale:)` is not free; on a 5‑page board this fires 4× per SwiftUI invalidation.

### Likely

- The `INFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleDefault` is set on both iOS SDKs but no custom status bar styling is actually used in code — likely a default Xcode template residue.
- The `XROS_DEPLOYMENT_TARGET = 26.5` and `MACOSX_DEPLOYMENT_TARGET = 26.5` are likely default Xcode values; nothing in the Swift source targets visionOS or macOS.

### Unknown

- Whether persistence of `CanvasStore.pages` is planned for an imminent change.
- Whether the orphaned image/audio files are intended to be cleaned up or retained (e.g., for a future "media library" feature).
- Roadmap: multi‑board, undo/redo, share/export, iCloud sync, visionOS port — none of these appear in code.
- Whether `DocumentPicker` integration is on the table (the `ENABLE_USER_SELECTED_FILES = readonly` and `READ‑ONLY` entitlement suggest it might be, but no code uses `UIDocumentPickerViewController`).
- Localization strategy: `STRING_CATALOG_GENERATE_SYMBOLS = YES` is on but no `.xcstrings` is present, so the eventual plan is unclear.
- Real‑device behaviour of the iOS 17.6 PencilKit tool picker inside the new `PageContentView` layout was not exercised; only the source is verified.
- The carousel's swipe gesture is suppressed while `drawMode == true` (good), but the gesture lives at the top of `PageCarouselView`'s body — whether it correctly defers to PencilKit's pan + Pencil double‑tap gestures inside the current `PageContentView` was not empirically verified.

## 19. Important Dependencies Between Modules

```text
MiroCloneApp
   └── JournalView
         ├── CanvasStore                    (created here, passed down)
         ├── PageCarouselView              ── reads/writes store.pages, store.currentPageIndex; calls store.switchToPage / store.addPage; reports scaled pageSize to store.updateCanvasSize
         │     └── PageContentView × (pages.count ± 1)
         │           ├── ScribbleCanvasView       (only when isCurrent)  ── reads/writes store.scribble (current page), store.drawMode; boundPageID + lastAssignedDrawingData track identity + echo
         │           ├── ElementContainerView × N  ── reads/writes store.selectedElementID, store.moveElement, .setWidth, .setHeight, .remove
         │           │     ├── TextElementView    ── store.updateElementText, store.setTextHeight, store.focusText, store.clearTextFocus
         │           │     │     └── AutoGrowingTextView  (UIViewRepresentable)
         │           │     ├── ImageElementView   ── reads store.imagesURL
         │           │     └── AudioElementView   ── reads store.audioURL + own AudioPlaybackManager (AVFoundation)
         │           └── deleteButton            ── store.removePage(at: pageIndex)
         ├── PhotosPicker (PhotosUI)        ── on selection: store.addImage(data:)
         └── AudioRecorderSheet              ── on stop: store.addAudio(fileURL:duration:)
                  └── AudioRecorderManager    (AVFoundation, microphone permission)

CanvasStore ──► Page            (array of pages; elements + scribble live here)
CanvasStore ──► FileManager     (Documents/Images, Documents/Audio)
CanvasStore ──► DesignSystem    (Shared)
PageCarouselView ──► DesignSystem (cornerRadius)
PageContentView ──► DesignSystem (cornerRadius)
ElementContainerView ──► DesignSystem (cornerRadius, minBlockWidth/Height, blockContentPadding)
```

Notable: there is **one** store, injected top‑down from `JournalView`. No singletons, no service locator, no DI container. All cross‑module references flow through `CanvasStore` (or, for media, through `store.imagesURL` / `store.audioURL` helpers that resolve to the Documents subdirectory). Page identity is opaque to views — they read `store.elements` / `store.scribble` and the store resolves to the current page behind a computed accessor.

## 20. Key Mental Model

Read `MiroCloneApp` → it launches a `JournalView`. `JournalView` creates a `CanvasStore` (the brain) and a `NavigationStack` containing a `PageCarouselView` plus a toolbar. The toolbar is the only way new content enters the current page: an Add‑Text button, a `PhotosPicker`, a Mic button (which presents `AudioRecorderSheet`), and a Scribble toggle.

The carousel is the entire board, modeled as a deck of pages. Pages are rendered at paper‑like size (≈ 45% of container width), with the current page centered and the previous / next pages pushed far below — only their top 20% peeks above the container bottom edge, reading as the top of a deck beneath the viewport. Side pages are also slightly smaller (`0.95×`) for a hint of perspective. A dynamic page number sits under each page. The rightmost slot, when on the last page, becomes a dashed "Add Page" card. The current page has a red "Delete" pill at the top. Navigation is by swipe, by tapping a side page, by tapping the Add Page card, or by swiping past the last page. Transitions are driven by a single fractional `visualPageIndex` that springs on commit, making the incoming page visibly rise from its lower side position into the center while the outgoing page falls into the side position — a deck‑of‑cards feel rather than a simple horizontal slide.

Each `PageContentView` renders one page: a paper background, a scribble layer (interactive `PKCanvasView` for the current page, static `UIImage` snapshot for neighbors), and a `ForEach` of `ElementContainerView`s for each element. `PageContentView` owns its own `"canvas"` coordinate space, so element drag math is always in the page's own coordinate system.

The store holds a list of `Page`s and a `currentPageIndex`. Every `elements` / `scribble` read or write goes through the current page — views don't know which page is current, only the store does. UI‑only state (selection, text focus, draw mode, canvas size) is global because it follows the user, not the page; switching pages clears it. The board always has at least one page; deleting the only one inserts a fresh empty replacement.

The store owns geometry. The `ElementContainerView`'s drag gesture does not maintain a "visual offset" — it computes the new top‑left point on every frame and writes it straight to `store.moveElement(_:to:)`, so the model is always the truth and there is nothing to reconcile. Resize handles work the same way. Text editing is opt‑in: a double‑tap focuses a block, a `UITextView` becomes the first responder, every change bubbles a measured height back so the block's frame matches the actual text.

When the user switches pages, `ScribbleCanvasView` swaps `uiView.drawing` to the new page's drawing. The echo of that programmatic swap is filtered out by byte‑equality against `lastAssignedDrawingData`, so PencilKit doesn't bounce the new page's strokes back into the old page (and real user strokes, which are always byte‑different, always reach the store).

Media content is stored as files in the app sandbox — `Documents/Images/<UUID>.jpg` and `Documents/Audio/<UUID>.m4a` — with only the filename kept on the element. Audio playback is per‑element via `AVAudioPlayer`; audio capture is a modal sheet driven by `AVAudioRecorder`. Drawing is a `PKDrawing` mirrored between PencilKit and the store via a delegate, scoped to the current page.

There is one screen, one store, no network, no database, no third‑party dependencies. Everything is local, observable, and reactive.

## 21. Confidence & Unknowns

### Confirmed

- All Swift source files in `MiroCloneiPad/` were read end‑to‑end (18 files: the original 16, plus `Page.swift`, `PageCarouselView.swift`, and `PageContentView.swift`; the legacy `FreeformCanvasView.swift` and `PageStripView.swift` were removed in a cleanup pass).
- Build is clean (`xcodebuild` succeeds; only the pre-existing `requestRecordPermission` deprecation warning).
- `JournalView`'s body is `PageCarouselView` (confirmed by reading `JournalView.swift`).
- `PageContentView` declares the `"canvas"` coordinate space per-page.
- `ScribbleCanvasView` uses `lastAssignedDrawingData: Data?` for echo‑skipping (verified by reading `ScribbleCanvasView.swift`).
- App entry point is `MiroCloneApp` (`@main`, `WindowGroup { JournalView() }`).
- `CanvasStore` is the single `ObservableObject` driving the entire UI; it holds `[Page]` plus UI‑only state (`selectedElementID`, `focusedTextID`, `drawMode`, `canvasSize`).
- `elements` and `scribble` on the store are computed accessors into `pages[currentPageIndex]`.
- Three element kinds: `.text`, `.image`, `.audio` (via `ElementKind` enum).
- Multi‑page behavior: app starts with one empty page, `addPage()` appends, `removePage(at:)` removes (no confirmation in the new design) and falls back to an empty page if the last one is deleted, `switchToPage(at:)` clears selection/focus/draw mode.
- Media persistence path: `Documents/Images/` and `Documents/Audio/` (`CanvasStore.imagesURL` / `audioURL`).
- `CanvasElement` is `Codable` but `CanvasStore.pages` is **not currently persisted** across launches.
- No test target, no third‑party dependencies.
- Bundle identifier `habil.MiroCloneiPad`, marketing version `1.0`, team `275W6TG8C4`.

### Likely

- `INFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleDefault`, `XROS_DEPLOYMENT_TARGET = 26.5`, `MACOSX_DEPLOYMENT_TARGET = 26.5` are default Xcode template residues, not intentional platform expansion.
- The app groups entitlement is enabled (`REGISTER_APP_GROUPS = YES`) but no app group identifier is used in code; it's speculative.
- Each `AudioElementView` owning its own `AudioPlaybackManager` is an intentional per‑element decision rather than oversight, but the code does not document why.
- The `pageAspectRatio = 1.3`, `pageWidthFraction = 0.45`, `neighborVisibleFraction = 0.2`, `sidePageScale = 0.05`, and the spring `response = 0.32, damping = 0.62` in `PageCarouselView` are tuned for iPad; on iPhone the same constants would produce a different visual density — likely intentional (single design across device families).

### Unknown

- Whether persistence of `CanvasStore.pages` is planned for an imminent change.
- Whether the orphaned image/audio files are intended to be cleaned up or retained.
- Roadmap: multi‑board, undo/redo, share/export, iCloud sync, visionOS port — none of these appear in code.
- Whether `DocumentPicker` integration is on the table.
- Localization strategy: `STRING_CATALOG_GENERATE_SYMBOLS = YES` is on but no `.xcstrings` is present, so the eventual plan is unclear.
- Real‑device behaviour of the iOS 17.6 PencilKit tool picker inside `PageContentView` was not exercised; only the source is verified.
- Whether the carousel's swipe gesture correctly defers to PencilKit's pan + Pencil double‑tap inside the current `PageContentView` on a real iPad.
- Why the deletion UX has no confirmation; whether that's final or temporary.
