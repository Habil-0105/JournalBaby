# Project Context

## 1. Project Overview

**MiroCloneiPad** is a single‑screen iPad application that mimics the core "freeform whiteboard" experience of tools like Miro / FigJam / Apple Freeform. It is an entirely client‑side, offline SwiftUI app — there is no backend, no account, no sync.

The product surface is intentionally minimal:

- One infinite‑feeling board (`FreeformCanvasView`) where the user places and arranges discrete blocks.
- Multiple **pages** (`PageStripView`): horizontal strip of page thumbnails at the bottom of the screen with a trailing "+" button to add a new page; the app always starts with one empty page and keeps at least one.
- Three block kinds: **text** (auto‑growing notes), **image** (from the Photos library), **audio** (microphone recordings).
- A **Scribble / Draw mode** that drops the user into Apple PencilKit's native `PKCanvasView` with the system `PKToolPicker`, identical to what Notes and Freeform ship.

Each block owns its own position (top‑left) and size on the board. There is no flow layout, no paging, no reflow — moving, adding or deleting a block never affects another block's placement. This is the deliberate design pivot from earlier git history (an earlier "pages" / 2‑page / 3D‑switch design was removed in commits `b87737e`, `d3ecd86`, `99ff378` and re‑introduced as a flatter multi‑page model — see §6/§11).

**Current state:** Working iOS app, builds in Xcode 26.6, targeted at iOS 17.6+, Swift 5, supports iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`). It is in active development but already feature‑complete for the three block kinds + Scribble. (Pinch‑to‑zoom was removed — see §18.)

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
│   │       ├── JournalView.swift    Top‑level screen + toolbar + page strip
│   │       ├── Models/
│   │       │   ├── Page.swift              One page: id + elements + scribble
│   │       │   ├── CanvasElement.swift   Codable struct for one block
│   │       │   └── CanvasStore.swift     ObservableObject — single source of truth
│   │       ├── Canvas/
│   │       │   ├── FreeformCanvasView.swift   Board container, element layout
│   │       │   ├── ElementContainerView.swift Per‑block chrome: selection, drag, resize handles
│   │       │   ├── ScribbleCanvasView.swift   UIViewRepresentable wrapping PKCanvasView
│   │       │   └── PageStripView.swift        Horizontal page thumbnails + "+"
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
- **`Features/Journal/`** — All product behavior lives here. Split into `Models/` (data + store), `Canvas/` (the board itself), `Elements/` (the three block kinds). The split keeps each layer addressable.
- **`Shared/`** — Cross‑feature tokens. Currently just `DesignSystem`. Designed so future features (e.g. multiple boards, settings) can pull from the same source of constants.
- **`Assets.xcassets/`** — `AppIcon` and `AccentColor` slots are empty placeholders generated by Xcode; no custom images shipped.

## 4. Architecture

The app is a thin, single‑layer SwiftUI app with one global `ObservableObject` driving the whole UI.

```
MiroCloneApp (@main)
   └─► JournalView            (top‑level SwiftUI screen, owns CanvasStore)
         ├─► VStack
         │     ├─► FreeformCanvasView   (the board surface, scoped to currentPage)
         │     │     ├─► ScribbleCanvasView (PKCanvasView, only when drawMode; swaps drawing on page change)
         │     │     └─► ElementContainerView × N (one per CanvasElement on currentPage)
         │     │           └─► TextElementView | ImageElementView | AudioElementView
         │     └─► PageStripView      (horizontal page thumbnails + add button)
         ├─► PhotosPicker (toolbar)
         └─► AudioRecorderSheet (modal)
                  └─► AudioRecorderManager / AudioPlaybackManager (AVFoundation)
```

**Core data flow**

- `CanvasStore` (`@Published` `pages`, `currentPageIndex`, plus UI state `selectedElementID`, `focusedTextID`, `drawMode`, `canvasSize`) is the **single source of truth**.
- `elements` and `scribble` on the store are **computed accessors** into `pages[currentPageIndex]` so views keep reading `store.elements` / `store.scribble` without knowing which page is current. `scribble` has a custom setter that writes back to the current page.
- `FreeformCanvasView`, every `ElementContainerView`, and `PageStripView` observe the store via `@ObservedObject`.
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
  2. `JournalView` is constructed; `@StateObject` creates `CanvasStore` (empty `elements`, `drawMode = false`).
3. `NavigationStack` + `GeometryReader` lay out. `FreeformCanvasView` appears, registers its canvas size on `onAppear`.
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
- **Consumers:** `JournalView`, `FreeformCanvasView`, `ScribbleCanvasView`, `ElementContainerView`, `TextElementView`, `ImageElementView`, `AudioElementView`, `AudioRecorderSheet`, `PageStripView`.

### Page (`Features/Journal/Models/Page.swift`)

- **Purpose:** A single page on the board — owns its own elements and its own scribble layer so switching pages swaps the whole visible state, the way flipping between sheets of paper does.
- **Shape:** `id: UUID`, `elements: [CanvasElement]`, `scribble: PKDrawing`. Defaults to empty.
- Conforms to `Identifiable`, `Equatable`. (Not `Codable` yet — see §18.)

### CanvasElement (`Features/Journal/Models/CanvasElement.swift`)

- **Purpose:** Pure value type for one block.
- **Shape:** `id: UUID`, `kind: ElementKind` (text / image / audio), `position: CGPoint` (stored top‑left), `width`, `height`, optional `text`, `imageFileName`, `audioFileName`, `audioDuration`.
- **`frame` computed property** is used for both rendering and implicit hit testing.
- Conforms to `Identifiable`, `Codable`, `Equatable`. (Codable exists but the store does not currently encode/decode the array to disk — see §18.)

### FreeformCanvasView (`Features/Journal/Canvas/FreeformCanvasView.swift`)

- **Purpose:** The board surface. Hosts the scribble layer and the element layer.
- **Key behaviour:**
  - Declares the `"canvas"` named coordinate space so child drag gestures (element drag, width/height handles) read coordinates directly from SwiftUI.
  - On `onAppear` / `onChange(of: size)` it reports the canvas size to `store.updateCanvasSize`.
- **Layer order (bottom→top):** board background → `ScribbleCanvasView` (PencilKit) → element layer (only hit‑testable when `!drawMode`).

### ElementContainerView (`Features/Journal/Canvas/ElementContainerView.swift`)

- **Purpose:** Per‑block chrome and gesture host.
- **Key behaviour:**
  - Tap → `store.select(element.id)`.
  - Double‑tap (text) → `store.focusText(element.id)`.
  - Drag (when allowed) → writes straight to `store.moveElement(_:to:)` with `start + translation`; the visual frame, model position, and hit‑test rectangle are therefore *always* the same value (no temporary offset to reconcile).
  - Width handle (right edge) and height handle (bottom edge; image/audio only) for resize; text height is auto‑measured.
  - Delete button (top‑right) visible when selected.
  - `moveEnabled = !isText || !isFocused` — text is only draggable when not being edited.

### ScribbleCanvasView (`Features/Journal/Canvas/ScribbleCanvasView.swift`)

- **Purpose:** `UIViewRepresentable` wrapping `PKCanvasView`.
- **Key behaviour:**
  - When `drawMode == true`: enables interaction, becomes first responder, shows `PKToolPicker`, registers it as observer.
  - When `drawMode == false`: hides tool picker, resigns first responder, disables interaction. Sits underneath the elements.
  - `drawingPolicy = .anyInput` (finger + Pencil, Notes‑style).
  - Delegate forwards `canvasViewDrawingDidChange` → `store.scribble = canvasView.drawing`, so Scribble strokes are persisted in the store (in memory — see §18).
  - Avoids re‑assigning `uiView.drawing` when PencilKit itself is the source of the change.
  - Tracks the `boundPageID` of the drawing currently in the `PKCanvasView`. When the page changes, `updateUIView` swaps `uiView.drawing = store.scribble` and sets `suppressNextDrawingChange` so PencilKit's first delegate call after a programmatic swap doesn't write the new page's strokes back to the old page (or vice versa).

### PageStripView (`Features/Journal/Canvas/PageStripView.swift`)

- **Purpose:** Horizontal scroll of page thumbnails + "+" button at the bottom of `JournalView`. Lets the user flip between pages and add/delete them.
- **Key behaviour:**
  - Each page is rendered as a small numbered card (`pageThumbnailWidth × pageThumbnailHeight`); the current page is outlined in accent color with a small dot in the corner.
  - Tap → `store.switchToPage(at:)`. The strip auto‑scrolls the current page into view via `ScrollViewReader`.
  - Long‑press / context menu on any page shows a "Delete Page" action that presents a `confirmationDialog` before calling `store.removePage(at:)`.
  - Trailing "+" button calls `store.addPage()` and selects the new page.

### TextElementView + AutoGrowingTextView (`Features/Journal/Elements/`)

- **TextElementView** is a thin SwiftUI host.
- **AutoGrowingTextView** is a `UIViewRepresentable` around a non‑scrolling `UITextView`. Why: SwiftUI's `TextEditor` doesn't give a reliable intrinsic size that wraps text correctly inside a fixed‑width block.
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
| `Features/Journal/JournalView.swift` | Top screen; `VStack` of `FreeformCanvasView` + `PageStripView`; wires the toolbar (add text/image/audio, toggle Scribble), presents the audio sheet, handles `PhotosPicker` data → `store.addImage(data:)`. |
| `Features/Journal/Models/Page.swift` | One page: owns its own elements + scribble layer. |
| `Features/Journal/Models/CanvasStore.swift` | All state (pages + current page + UI state), all mutations, file I/O for images & audio. The "brain". |
| `Features/Journal/Models/CanvasElement.swift` | The data shape; defines that `position` is stored (not derived). |
| `Features/Journal/Canvas/FreeformCanvasView.swift` | Named coordinate space contract + board layout. |
| `Features/Journal/Canvas/ElementContainerView.swift` | All per‑block gestures (select, drag, resize, delete). Writes position back to the store on every drag tick. |
| `Features/Journal/Canvas/ScribbleCanvasView.swift` | PencilKit + system `PKToolPicker` integration; swaps drawing on page change with one‑shot delegate suppression. |
| `Features/Journal/Canvas/PageStripView.swift` | Horizontal page thumbnails + "+" button + delete (via context menu + confirmation dialog). |
| `Features/Journal/Elements/AutoGrowingTextView.swift` | Why text height matches content; opt‑in editing; the `sizeThatFits` override. |
| `Features/Journal/Elements/AudioRecorderSheet.swift` | Microphone permission flow + `AVAudioRecorder` setup. |
| `Features/Journal/Elements/AudioElementView.swift` | `AVAudioPlayer` + per‑view playback manager. |
| `Shared/DesignSystem.swift` | All sizing/padding tokens, including page‑strip sizing. |
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
              FreeformCanvasView re‑renders (ForEach picks up new element)
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

### Zoom / pan

```text
(Zoom / pan was removed; the board renders at a fixed 1:1 scale. Element
drag and width/height handles still read the `"canvas"` named coordinate
space directly — no transform in between.)
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

### Switching pages

```text
PageStripView thumbnail tap OR "+" tap
  ├─ thumbnail tap ─► store.switchToPage(at: index)
  │       ─► currentPageIndex = index
  │       ─► selectedElementID = nil, focusedTextID = nil, drawMode = false
  │             (UI‑only state can't follow across pages)
  └─ "+" tap       ─► store.addPage()      ─► pages.append(Page())
                                              ─► switchToPage(at: pages.count - 1)

ScribbleCanvasView.updateUIView on currentPageIndex change
  ─► boundPageID != current page ID
  ─► uiView.drawing = store.scribble    (swap the PencilKit drawing to the new page)
  ─► coordinator.suppressNextDrawingChange = true   (skip one echo back)
  ─► PageStripView auto‑scrolls the new thumbnail into center (ScrollViewReader)
```

Long‑press / context menu on a thumbnail:
  ─► store.removePage(at: index) confirmed via confirmationDialog
        ─► pages.remove(at: index); if pages empty → pages = [Page()]
        ─► if the deleted index was ≤ currentPageIndex, currentPageIndex -= 1
```

### Pencil / Scribble

```text
Toggle Scribble toolbar button
  ─► store.toggleDrawMode() ─► drawMode = true, selectedElementID = nil, focusedTextID = nil
        ─► ScribbleCanvasView.setDrawMode(true, on:)
              ─► toolPicker.addObserver / setVisible(true, forFirstResponder:)
              ─► PKCanvasView.becomeFirstResponder()      (system tool picker appears)
        ─► canvasViewDrawingDidChange ─► store.scribble = canvasView.drawing

Toggle off  ─► toolPicker hidden, PKCanvasView resigns first responder, interaction disabled,
               element layer becomes hit‑testable again.
```

## 9. Major Business Logic

1. **Position is the single source of truth for layout.** No derived positions, no reflow, no flow layout. `CanvasElement.position` is read for rendering, hit testing, and the drag gesture's write‑back. This is the explicit answer to the historical bug where moving a block affected other blocks.
2. **Drag writes on every tick, not on commit.** The drag's `onChanged` calls `store.moveElement` with the current `start + translation`, so model / visual / hit‑test rectangle are always in lockstep — no temporary visual offset to reconcile on `onEnded`.
3. **Cascading default placement for new blocks.** `nextDefaultPosition()` is a creation‑time convenience (`(inset + col*spacing, inset + row*spacing)`); once created, the element owns its position.
4. **The board renders at a fixed 1:1 scale.** There is no zoom or pan. Element drag, width/height handles, and PencilKit touches all read the `"canvas"` named coordinate space directly; nothing in between warps the frame.
5. **Draw mode is exclusive.** Selecting any element exits Draw mode; toggling Draw mode clears selection and text focus. Elements are non‑interactive while Draw mode is on.
6. **Text editing is opt‑in and isolated.** A text block is draggable when *not* focused, so caret/selection gestures always win during editing. Height is auto‑measured (`AutoGrowingTextView.sizeThatFits` + `recalculateHeight` → `store.setTextHeight`).
7. **Scribble strokes live in their own layer.** `store.scribble: PKDrawing` is independent of `elements`; PencilKit is the source of truth while Draw mode is on, and the store mirrors its state via the delegate.
8. **Block content lives in the Documents directory.** Image bytes are written directly into `Documents/Images/<UUID>.jpg`; audio is copied from a temp recording into `Documents/Audio/<UUID>.m4a`. The `CanvasElement` stores only the file name.
9. **Min/max constraints.** Elements are clamped to `minBlockWidth × minBlockHeight` and to the canvas content rectangle on resize and drag.
10. **Pages are independent sheets of state.** `pages[currentPageIndex]` is what every element + scribble mutation reads and writes; switching pages clears UI‑only state (selection, text focus, draw mode) because that state can't follow across. The board always has at least one page; deleting the only page inserts a fresh empty replacement. The `PKCanvasView`'s drawing is swapped in lock‑step with `currentPageIndex` change (with one‑shot delegate suppression so PencilKit doesn't echo the swap back into the store).
11. **UI‑state vs page‑state split.** Pages own their `elements` and `scribble`; selection, text focus, draw mode, and canvas size are global because they're tied to the user/UI, not the page.

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
| Add page               | `PageStripView` "+" → `store.addPage()`                              |
| Switch page            | `PageStripView` thumbnail tap → `store.switchToPage(at:)`            |
| Delete page            | thumbnail context menu → `confirmationDialog` → `store.removePage(at:)` |

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
| PencilKit (`PKCanvasView`, `PKToolPicker`, `PKDrawing`) | Free‑form drawing layer, system tool palette | `ScribbleCanvasView` | Wrapped in `UIViewRepresentable`; if PencilKit unavailable on the OS version this would crash — but iOS 17.6+ guarantees it. |
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
- `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`, `STRING_CATALOG_GENERATE_SYMBOLS = YES` — there is no `.xcstrings` file in the repo yet, so all visible strings ("Journal", "Add Text", "Type here…", "Ready to record", "Cancel", etc.) are hardcoded English literals inline.

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

1. **Store as the single source of truth.** Every state change goes through a `CanvasStore` method; views never mutate `CanvasElement` directly. (`ElementContainerView` writes only via `store.moveElement`, `store.setWidth`, etc.)
2. **Stored position, no derived layout.** New block kinds or layout strategies should keep position stored on the element. Resist any "reflow on neighbour change" temptation.
3. **Drag‑writes‑on‑every‑tick.** Gestures that change geometry should update the model on `onChanged`, not on `onEnded` (matches `ElementContainerView.moveGesture`). This keeps the visual frame, hit test, and model position identical at all times.
4. **DesignSystem is the only place for sizing tokens.** Don't hardcode `cornerRadius`, `minBlockWidth`, padding, etc. in views.
5. **UIViewRepresentable wrappers are the bridge, not the model.** `AutoGrowingTextView` and `ScribbleCanvasView` are intentionally thin; all state lives in `CanvasStore` and is mirrored via delegate callbacks.
6. **SwiftUI `GeometryReader` + named coordinate space contract.** Drag gestures inside `FreeformCanvasView` use `.coordinateSpace(.named("canvas"))`. Don't add a `scaleEffect` / `offset` modifier that wraps the board — element drag math is written against a 1:1 frame.
7. **Opt‑in editing for text blocks.** Anything that involves the caret / selection must check `isFocused` first so drag can take over otherwise.
8. **File‑backed content, name in the model.** Heavy media lives in `Documents/Images` / `Documents/Audio`; the `CanvasElement` only stores a filename. Future media kinds should follow the same pattern.
9. **Concurrency isolation.** Because `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, prefer keeping work on the main actor. The only off‑main work today is the `Task` around `PhotosPickerItem.loadTransferable`.
10. **No third‑party dependencies.** The project intentionally has none; don't add a SPM dependency for something SwiftUI/AVFoundation/PencilKit already covers.

## 18. Known Issues / Technical Debt

### Confirmed

- **No persistence of `CanvasStore.pages`.** `CanvasElement` is `Codable`, the store is `ObservableObject` with `@Published pages`, but no code reads or writes the page list to disk. On relaunch the canvas resets to a single empty page; the previously written image/audio files in `Documents/Images` and `Documents/Audio` are orphaned (no cleanup, no referencing record). `Page` itself isn't `Codable` yet either, so persisting it requires a tiny follow‑up.
- **No tests.** No test target, no `*Tests*` folders, no SPM `Testing` glue. (Verified by repo search and project inspection.)
- **Scribble strokes are not persisted.** `pages[i].scribble` is in‑memory only; closing/reopening the app loses every page's drawing. PencilKit itself could persist via `PKDrawing.dataRepresentation()` if desired.
- **Page thumbnails are pure placeholders.** `PageStripView` shows numbered cards, not actual page previews. Rendering each page's contents into a thumbnail was deliberately skipped to keep the strip cheap to draw; switching to live previews would mean snapshotting the canvas.
- **No image/audio cleanup on page delete.** `CanvasStore.removePage(at:)` removes the `Page` (and its `elements`) but does not delete the underlying files at `Documents/Images/<fileName>` or `Documents/Audio/<fileName>`. Same issue applies to `CanvasStore.remove(id:)` for individual element deletes.
- **No undo/redo.** Despite PencilKit offering it natively for scribble, the app provides no undo for element moves/resizes/deletes or text edits.
- **Logging is `print`-based** (`print("Failed to save image: …")`, `print("Recording error: …")`, `print("Playback error: …")`). No structured logging, no OSLog.
- **No localization infrastructure in place.** Strings are inline English literals; `STRING_CATALOG_GENERATE_SYMBOLS = YES` is set but no `.xcstrings` catalog is present yet.
- **`AudioPlaybackManager` per element.** Each `AudioElementView` creates its own `AudioPlaybackManager`. There's no shared audio session coordinator — playing two audio blocks simultaneously will both set the session to `.playback` and both play at once. The intent is unclear.

### Likely

- The `INFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleDefault` is set on both iOS SDKs but no custom status bar styling is actually used in code — likely a default Xcode template residue.
- The `XROS_DEPLOYMENT_TARGET = 26.5` and `MACOSX_DEPLOYMENT_TARGET = 26.5` are likely default Xcode values; nothing in the Swift source targets visionOS or macOS.

### Unknown

- The exact long‑term roadmap / target feature set. Git history shows earlier "pages" / 2‑page / 3D‑switch features were removed; the pivot to a single‑board freeform canvas appears deliberate, but no docs explain why.
- Whether `Document Picker` / `Files` integration or iCloud sync is intended. `REGISTER_APP_GROUPS = YES` is set in the build settings but no app group identifier is configured in code, suggesting it was enabled speculatively.
- How the app should handle low storage, full disk, or sandbox file restoration from iCloud / iTunes backup (no code addresses it).
- Whether multi‑board / multi‑page is a near‑term goal (would justify persisting `elements` per board).

## 19. Important Dependencies Between Modules

```text
MiroCloneApp
   └── JournalView
         ├── CanvasStore                    (created here, passed down)
         ├── VStack
         │     ├── FreeformCanvasView             ── reads/writes store.canvasSize, .elements (current page)
         │     │     ├── ScribbleCanvasView       ── reads/writes store.scribble (current page), store.drawMode; boundPageID tracks current page
         │     │     └── ElementContainerView × N ── reads/writes store.selectedElementID, store.moveElement, .setWidth, .setHeight, .remove
         │     │           ├── TextElementView    ── store.updateElementText, store.setTextHeight, store.focusText, store.clearTextFocus
         │     │           │     └── AutoGrowingTextView  (UIViewRepresentable)
         │     │           ├── ImageElementView   ── reads store.imagesURL
         │     │           └── AudioElementView   ── reads store.audioURL + own AudioPlaybackManager (AVFoundation)
         │     └── PageStripView            ── reads store.pages, store.currentPageIndex; calls store.switchToPage/addPage/removePage
         ├── PhotosPicker (PhotosUI)        ── on selection: store.addImage(data:)
         └── AudioRecorderSheet              ── on stop: store.addAudio(fileURL:duration:)
                  └── AudioRecorderManager    (AVFoundation, microphone permission)

CanvasStore ──► Page            (array of pages; elements + scribble live here)
CanvasStore ──► FileManager     (Documents/Images, Documents/Audio)
CanvasStore ──► DesignSystem    (Shared)
FreeformCanvasView ──► DesignSystem (cornerRadius)
ElementContainerView ──► DesignSystem (cornerRadius, minBlockWidth/Height, blockContentPadding)
PageStripView ──► DesignSystem (pageThumbnailWidth/Height/cornerRadius, pageStripSpacing/Padding)
```

Notable: there is **one** store, injected top‑down from `JournalView`. No singletons, no service locator, no DI container. All cross‑module references flow through `CanvasStore` (or, for media, through `store.imagesURL` / `store.audioURL` helpers that resolve to the Documents subdirectory). Page identity is opaque to views — they read `store.elements` / `store.scribble` and the store resolves to the current page behind a computed accessor.

## 20. Key Mental Model

Read `MiroCloneApp` → it launches a `JournalView`. `JournalView` creates a `CanvasStore` (the brain) and a `NavigationStack` containing a `VStack { FreeformCanvasView; PageStripView }` plus a toolbar. The toolbar is the only way new content enters the current page: an Add‑Text button, a `PhotosPicker`, a Mic button (which presents `AudioRecorderSheet`), and a Scribble toggle. The page strip at the bottom of the screen is how the user switches pages or adds a new one (tap a thumbnail, or tap the trailing "+" button; long‑press / context menu on a thumbnail deletes it after a confirmation).

The store holds a list of `Page`s and a `currentPageIndex`. Every `elements` / `scribble` read or write goes through the current page — views don't know which page is current, only the store does. UI‑only state (selection, text focus, draw mode, canvas size) is global because it follows the user, not the page; switching pages clears it. The board always has at least one page; deleting the only one inserts a fresh empty replacement.

Everything you can see or interact with on the current page is a `CanvasElement` — a struct with a position, a size, and an optional payload (text, image filename, or audio filename). The board is a `ZStack` of three layers: the background, a `PKCanvasView` for free‑form drawing, and one `ElementContainerView` per element. The board renders at a fixed 1:1 scale — there is no zoom or pan. Drag gestures inside the board use a named coordinate space to read SwiftUI's coordinate frame directly.

The store owns geometry. The `ElementContainerView`'s drag gesture does not maintain a "visual offset" — it computes the new top‑left point on every frame and writes it straight to `store.moveElement(_:to:)`, so the model is always the truth and there is nothing to reconcile. Resize handles work the same way. Text editing is opt‑in: a double‑tap focuses a block, a `UITextView` becomes the first responder, every change bubbles a measured height back so the block's frame matches the actual text.

When the user switches pages, `ScribbleCanvasView` swaps `uiView.drawing` to the new page's drawing and suppresses one delegate echo so PencilKit doesn't immediately bounce the new page's strokes back into the old page.

Media content is stored as files in the app sandbox — `Documents/Images/<UUID>.jpg` and `Documents/Audio/<UUID>.m4a` — with only the filename kept on the element. Audio playback is per‑element via `AVAudioPlayer`; audio capture is a modal sheet driven by `AVAudioRecorder`. Drawing is a `PKDrawing` mirrored between PencilKit and the store via a delegate, scoped to the current page.

There is one screen, one store, no network, no database, no third‑party dependencies. Everything is local, observable, and reactive.

## 21. Confidence & Unknowns

### Confirmed

- All Swift source files in `MiroCloneiPad/` were read end‑to‑end (18 files: the 16 originals + `Page.swift` and `PageStripView.swift` added for multi‑page support).
- All build settings were read from `project.pbxproj`.
- App entry point is `MiroCloneApp` (`@main`, `WindowGroup { JournalView() }`).
- `CanvasStore` is the single `ObservableObject` driving the entire UI; it holds `[Page]` plus UI‑only state (`selectedElementID`, `focusedTextID`, `drawMode`, `canvasSize`). Zoom state was removed.
- `elements` and `scribble` on the store are computed accessors into `pages[currentPageIndex]` — verified by reading `CanvasStore.swift`.
- Three element kinds: `.text`, `.image`, `.audio` (via `ElementKind` enum).
- Multi‑page behavior: app starts with one empty page, `addPage()` appends, `removePage(at:)` removes (with confirmation) and falls back to an empty page if the last one is deleted, `switchToPage(at:)` clears selection/focus/draw mode.
- Media persistence path: `Documents/Images/` and `Documents/Audio/` (`CanvasStore.imagesURL` / `audioURL`).
- The board has no zoom; the `"canvas"` named coordinate space is declared on `FreeformCanvasView` and read by element drag + width/height handles.
- `ScribbleCanvasView` swaps `PKCanvasView.drawing` when `currentPageIndex` changes, with a one‑shot delegate suppression to prevent the swap from echoing back into the store (verified by reading `ScribbleCanvasView.swift`).
- `CanvasElement` is `Codable` but `CanvasStore.pages` is **not currently persisted** across launches — verified by absence of any JSON/Plist/SwiftData call in the codebase.
- No test target, no third‑party dependencies (verified by repo file listing and `.pbxproj` inspection).
- Microphone and Photo Library usage descriptions are present in both Debug and Release Info.plist generation settings.
- Bundle identifier `habil.MiroCloneiPad`, marketing version `1.0`, team `275W6TG8C4`.

### Likely

- `INFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleDefault`, `XROS_DEPLOYMENT_TARGET = 26.5`, `MACOSX_DEPLOYMENT_TARGET = 26.5` are default Xcode template residues, not intentional platform expansion.
- The app groups entitlement is enabled (`REGISTER_APP_GROUPS = YES`) but no app group identifier is used in code; it's speculative.
- Each `AudioElementView` owning its own `AudioPlaybackManager` is an intentional per‑element decision rather than oversight, but the code does not document why.

### Unknown

- Whether persistence of `CanvasStore.elements` is planned for an imminent change.
- Whether the orphaned image/audio files are intended to be cleaned up or retained (e.g., for a future "media library" feature).
- Roadmap: multi‑board, undo/redo, share/export, iCloud sync, visionOS port — none of these appear in code.
- Whether `DocumentPicker` integration is on the table (the `ENABLE_USER_SELECTED_FILES = readonly` and `READ‑ONLY` entitlement suggest it might be, but no code uses `UIDocumentPickerViewController`).
- Localization strategy: `STRING_CATALOG_GENERATE_SYMBOLS = YES` is on but no `.xcstrings` is present, so the eventual plan is unclear.
- Real‑device behaviour of the iOS 17.6 PencilKit tool picker inside this exact layout was not exercised; only the source is verified.
