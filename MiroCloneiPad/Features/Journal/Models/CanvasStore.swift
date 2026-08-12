import SwiftUI
import Combine
import UIKit
import PencilKit

/// Owns every page and the per-page canvas state. There is no layout
/// engine here — each element on a page carries its own `position`, and
/// this store is just the single source of truth that views read from
/// and mutate:
///
/// ```
/// store.currentPage.elements[i].position  ──►  canvas rendering
/// store.currentPage.elements[i].position  ──►  hit testing / taps
/// drag gesture                            ──►  store.moveElement  ──►  position
/// ```
///
/// `elements` and `scribble` are scoped to the current page so flipping
/// to a different page swaps the whole visible state. UI-only state
/// (selection, text focus, draw mode) stays global because those follow
/// the user, not the page.
final class CanvasStore: ObservableObject {
    @Published var pages: [Page] = [Page()]
    @Published var currentPageIndex: Int = 0

    /// The page currently shown. All element + scribble mutations read
    /// and write through here. Computed (not stored) so the store has
    /// exactly one place to update.
    var currentPage: Page {
        pages[currentPageIndex]
    }

    /// Convenience accessors. Views should keep reading these instead of
    /// reaching into `pages[currentPageIndex]` directly — that keeps the
    /// "current page" concept owned by the store.
    var elements: [CanvasElement] {
        currentPage.elements
    }
    var scribble: PKDrawing {
        get { currentPage.scribble }
        set {
            guard pages.indices.contains(currentPageIndex) else { return }
            pages[currentPageIndex].scribble = newValue
        }
    }
    /// The current page's full-page document body. Same single-source-of-truth
    /// rule as `scribble`: read-through getter, write through the store.
    var bodyText: String {
        get { currentPage.bodyText }
        set {
            guard pages.indices.contains(currentPageIndex) else { return }
            if pages[currentPageIndex].bodyText != newValue {
                pages[currentPageIndex].bodyText = newValue
            }
        }
    }

    /// The current page's layer order — the two whole-page layers (text
    /// editor, scribble) plus one slot per individual element, front-to-back.
    /// Read-through getter, same single-source-of-truth rule as `scribble` /
    /// `bodyText`. Deliberately read-only — writes go through
    /// `setLayerOrder(_:)` below, which validates the new value before it
    /// ever reaches `pages`.
    var layerOrder: [CanvasLayerRef] {
        currentPage.layerOrder
    }

    /// Sets the current page's layer order. Validates that `order` contains
    /// exactly the same set of refs the page already has — i.e. it's a
    /// reordering, not an insertion/deletion in disguise. `layerOrder` stays
    /// in sync with `elements` purely through `addText`/`addImage`/
    /// `addAudio`/`remove` (below), so this check is a cheap safety net
    /// against a malformed value ever reaching `pages`, not the mechanism
    /// that keeps elements and their layer slots aligned. No-ops if the
    /// value is unchanged.
    func setLayerOrder(_ order: [CanvasLayerRef]) {
        guard pages.indices.contains(currentPageIndex) else { return }
        let current = pages[currentPageIndex].layerOrder
        guard order.count == current.count, Set(order) == Set(current) else { return }
        guard current != order else { return }
        pages[currentPageIndex].layerOrder = order
    }

    /// Inserts a new element's layer ref at the front (topmost) of the
    /// given page's order — matches the app's original "newest element
    /// draws last, i.e. on top" default. Called once by each of
    /// `addText`/`addImage`/`addAudio`, right after the element itself is
    /// appended to `elements`.
    private func insertLayerRefOnTop(_ ref: CanvasLayerRef, onPageAt index: Int) {
        guard pages.indices.contains(index) else { return }
        pages[index].layerOrder.insert(ref, at: 0)
    }

    /// Removes an element's layer ref from the given page's order. Called
    /// by `remove(_:)` so a deleted element never leaves a stale, unreachable
    /// slot behind in `layerOrder`.
    private func removeLayerRef(_ ref: CanvasLayerRef, fromPageAt index: Int) {
        guard pages.indices.contains(index) else { return }
        pages[index].layerOrder.removeAll { $0 == ref }
    }

    @Published var selectedElementID: UUID?

    /// The text block currently being edited (first responder). Kept
    /// separate from `selectedElementID` so a text block can be selected
    /// AND dragged without fighting its text view.
    @Published var focusedTextID: UUID?

    /// True when the page's full-body text editor is the first responder.
    /// Lives alongside `focusedTextID` so `WritingCanvasView`'s keyboard
    /// avoidance can also lift the paper when the user is typing in the
    /// document body, not just in a floating text element.
    @Published var bodyFocused: Bool = false

    /// Caret frame in the page's coordinate space (top-left origin,
    /// unzoomed page). Updated by the body editor every time the caret
    /// moves, and consumed by `WritingCanvasView` to compute the
    /// caret-relative keyboard offset. `nil` while the body is not
    /// focused or before the first layout pass.
    @Published var bodyCaretRect: CGRect?

    /// When true, touches on the canvas draw scribble strokes directly on
    /// the board instead of interacting with elements. Selecting any
    /// element turns it off.
    @Published var drawMode: Bool = false

    /// When true, the app is in **writing mode**: the carousel layout is
    /// hidden and the current page is shown as a large centered writing
    /// canvas (no neighbouring pages, no page strip). Only in writing mode
    /// does the `PKCanvasView` accept touch input and present the
    /// PencilKit tool picker. Exiting writing mode returns to carousel
    /// mode; the current page and its scribble/elements are preserved.
    @Published var writingMode: Bool = false

    /// Size of the canvas content area (from the host GeometryReader).
    /// Used to clamp drags and default placement inside the board.
    @Published private(set) var canvasSize: CGSize = .zero

    /// The ONE shared audio playback manager. Every `AudioElementView`
    /// drives this instance, which is what enforces the "only one audio at
    /// a time" rule — starting any clip stops whatever was playing.
    let audioPlayer = AudioPlaybackManager()

    // MARK: - Global journal hint

    /// The journal's single hint, shared by every page. Lives at the store
    /// (journal) level — NOT on any `Page` — so switching pages shows the
    /// exact same hint and text, and the hint is never recreated per page.
    @Published var hintText: String = GlobalHint.initialQuestion(for: nil)
    @Published var hintPosition: CGPoint = GlobalHint.defaultPosition
    @Published var hintSize: CGSize = GlobalHint.defaultSize

    /// Temporary UI state — whether the hint overlay is currently shown in
    /// writing mode. Journal-level (never per-page) but deliberately *not*
    /// persistent: `enterWritingMode()` resets it to `true`, so the hint
    /// always reappears on each writing session regardless of how it was
    /// toggled before leaving. `refreshHint` / `moveHint` never touch it.
    @Published var hintVisible: Bool = true

    // MARK: - Global emotion (temporary in-memory)

    /// The journal's single global emotion. One per journal, shared by every
    /// page — switching pages never changes it. `nil` means no emotion
    /// selected. Deliberately in-memory for now (persistence comes later);
    /// the value type is already `Codable`-friendly.
    @Published var globalEmotion: Emotion? = nil

    /// Sets (or clears) the journal's global emotion and immediately points
    /// the global hint's text at the matching question. Position and size of
    /// the hint (and its visibility) are left untouched.
    func setEmotion(_ emotion: Emotion?) {
        globalEmotion = emotion
        hintText = GlobalHint.initialQuestion(for: emotion)
    }

    /// Moves the global hint, clamped to the paper bounds. The clamp uses
    /// the hint's current size and reserves the refresh button's overhang so
    /// the whole hint — card and button — stays inside the paper.
    func moveHint(to topLeft: CGPoint) {
        let rightLimit = max(
            canvasSize.width - hintSize.width - GlobalHint.buttonOverhang.width,
            0
        )
        let bottomLimit = max(canvasSize.height - hintSize.height, 0)
        hintPosition = CGPoint(
            x: min(max(topLeft.x, 0), rightLimit),
            y: min(max(topLeft.y, GlobalHint.buttonOverhang.height), bottomLimit)
        )
    }

    /// Resizes the global hint (clamped to `GlobalHint.minSize` /
    /// `GlobalHint.maxSize`), then re-clamps the position so the enlarged
    /// hint stays fully on the paper.
    func setHintSize(_ size: CGSize) {
        hintSize = CGSize(
            width: min(max(size.width, GlobalHint.minSize.width), GlobalHint.maxSize.width),
            height: min(max(size.height, GlobalHint.minSize.height), GlobalHint.maxSize.height)
        )
        moveHint(to: hintPosition)
    }

    /// Replaces the current hint with the next question from the current
    /// emotion's pool (or the general pool when no emotion is selected),
    /// keeping the hint in the same position and visibility. Applies
    /// journal-wide immediately.
    func refreshHint() {
        hintText = GlobalHint.nextPrompt(
            after: hintText,
            in: GlobalHint.questions(for: globalEmotion)
        )
    }

    func updateCanvasSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != canvasSize else { return }
        canvasSize = size
    }

    func select(_ id: UUID?) {
        if id != nil {
            drawMode = false
        }
        if focusedTextID != nil && focusedTextID != id {
            focusedTextID = nil
        }
        selectedElementID = id
        // Selecting an element (or deselecting on an empty-area tap)
        // always ends body editing: tapping anywhere outside the body
        // editor is "tap outside the TextEditor" and must dismiss the
        // keyboard.
        if bodyFocused {
            setBodyFocused(false)
        }
    }

    /// Starts editing a text block (double-tap / explicit edit action).
    /// Also selects it and exits Draw mode.
    func focusText(_ id: UUID) {
        selectedElementID = id
        focusedTextID = id
        drawMode = false
        // Focus moves to a floating text element — body editing ends.
        if bodyFocused {
            setBodyFocused(false)
        }
    }

    func clearTextFocus(_ id: UUID) {
        if focusedTextID == id {
            focusedTextID = nil
        }
    }

    /// Arms the Scribble / drawing surface inside writing mode: makes the
    /// `PKCanvasView` interactive and shows the system tool picker. Drawing
    /// is opt-in — entering writing mode alone does NOT arm it; the user
    /// must explicitly tap the Scribble tool.
    func enableDrawing() {
        guard writingMode, !drawMode else { return }
        withAnimation(DesignSystem.modeSwitchAnimation) {
            drawMode = true
            selectedElementID = nil
            focusedTextID = nil
            bodyFocused = false
            bodyCaretRect = nil
        }
    }

    /// Disarms the Scribble / drawing surface, returning to element editing.
    /// (`select` / `focusText` / `exitWritingMode` also clear `drawMode`.)
    func disableDrawing() {
        guard drawMode else { return }
        withAnimation(DesignSystem.modeSwitchAnimation) {
            drawMode = false
        }
    }

    // MARK: - Writing mode

    /// Switch from carousel mode to writing mode. The current page is
    /// promoted to a large centered writing canvas; the carousel and page
    /// strip are hidden; element interaction becomes active. `drawMode`
    /// stays `false` — drawing is never auto-engaged on entry; the toolbar
    /// Scribble tool must be tapped to arm it. Selecting elements / focusing
    /// text are cleared because they don't carry across the layout change.
    func enterWritingMode() {
        guard !writingMode else { return }
        withAnimation(DesignSystem.modeSwitchAnimation) {
            writingMode = true
            selectedElementID = nil
            focusedTextID = nil
            bodyFocused = false
            bodyCaretRect = nil
            drawMode = false
            // Each writing session shows the global hint again, no matter
            // how it was toggled before (temporary, never persisted).
            hintVisible = true
        }
    }

    /// Switch from writing mode back to carousel mode. Selection / focus
    /// are cleared (same reason as `switchToPage`). `drawMode` is also
    /// cleared so the carousel's swipe gesture is enabled again on
    /// return — without this, the carousel's drag guard
    /// (`!store.drawMode`) would silently suppress every swipe until
    /// something else (like `addPage` → `switchToPage`) reset it.
    func exitWritingMode() {
        guard writingMode else { return }
        withAnimation(DesignSystem.modeSwitchAnimation) {
            writingMode = false
            drawMode = false
            selectedElementID = nil
            focusedTextID = nil
            bodyFocused = false
            bodyCaretRect = nil
        }
    }

    // MARK: - Pages

    /// Appends a fresh empty page and switches to it.
    @discardableResult
    func addPage() -> Page {
        let page = Page()
        pages.append(page)
        switchToPage(at: pages.count - 1)
        return page
    }

    /// Switches to the page at `index`. UI‑only selection/focus/draw mode
    /// is cleared because it can't apply across pages.
    func switchToPage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        // The playing clip belongs to a page that may now be hidden — stop it.
        audioPlayer.stop()
        currentPageIndex = index
        selectedElementID = nil
        focusedTextID = nil
        bodyFocused = false
        bodyCaretRect = nil
        drawMode = false
    }

    /// Removes the page at `index`. If it was the current page, falls
    /// back to the neighbour (preferring the previous page); if it was
    /// the only page, an empty page replaces it so the board always has
    /// at least one page to draw on.
    func removePage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        audioPlayer.stop()
        pages.remove(at: index)
        if pages.isEmpty {
            pages = [Page()]
            currentPageIndex = 0
            return
        }
        if currentPageIndex >= pages.count {
            currentPageIndex = pages.count - 1
        } else if index < currentPageIndex {
            currentPageIndex -= 1
        }
        selectedElementID = nil
        focusedTextID = nil
        bodyFocused = false
        bodyCaretRect = nil
        drawMode = false
    }

    // MARK: - Animated delete

    /// Transient state for a delete operation the carousel is animating.
    /// Holds the page data (so the ghost can render it during the exit)
    /// and the index of the page that will become current once the
    /// removal is confirmed. The actual removal is performed by
    /// `confirmPendingDeletion()` after the carousel's exit animation
    /// completes; until then `pages` and `currentPageIndex` are
    /// untouched.
    struct PendingDeletion: Equatable {
        let page: Page
        let originalIndex: Int
        let replacementIndex: Int
    }

    @Published var pendingDeletion: PendingDeletion?

    /// Captures the page-to-delete and its replacement index for animated
    /// deletion. The carousel watches `pendingDeletion`, runs the exit
    /// + entry animation, then calls `confirmPendingDeletion()` to apply
    /// the actual removal using the existing `removePage(at:)` semantics.
    func requestDeletePage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        pendingDeletion = PendingDeletion(
            page: pages[index],
            originalIndex: index,
            replacementIndex: replacementIndexAfterRemove(at: index)
        )
    }

    /// Applies the actual removal (using `removePage(at:)`) and clears the
    /// pending state. Only call this after the carousel's exit animation
    /// has completed.
    func confirmPendingDeletion() {
        guard let pd = pendingDeletion else { return }
        pendingDeletion = nil
        removePage(at: pd.originalIndex)
    }

    /// Computes what `currentPageIndex` will be after `removePage(at:)` runs,
    /// using the same logic as the existing removal. Used by the carousel
    /// to know which page should rise into center during the entry half
    /// of the delete animation.
    private func replacementIndexAfterRemove(at index: Int) -> Int {
        if index == currentPageIndex {
            if pages.count == 1 {
                return 0
            }
            if currentPageIndex == pages.count - 1 {
                return currentPageIndex - 1
            }
            return currentPageIndex
        }
        if index < currentPageIndex {
            return currentPageIndex - 1
        }
        return currentPageIndex
    }

    // MARK: - On-disk storage for images / audio

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var imagesURL: URL {
        let url = documentsURL.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var audioURL: URL {
        let url = documentsURL.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Moving

    /// The single way an element moves. Writes the element's actual
    /// `position` (clamped to the canvas) on every drag change, so the
    /// model, the rendering, and hit testing all stay in lockstep — there
    /// is no temporary visual offset that later has to be committed.
    func moveElement(_ id: UUID, to topLeft: CGPoint) {
        guard pages.indices.contains(currentPageIndex),
              let idx = pages[currentPageIndex].elements.firstIndex(where: { $0.id == id }) else { return }
        let element = pages[currentPageIndex].elements[idx]
        let maxX = max(canvasSize.width - element.width, 0)
        let maxY = max(canvasSize.height - element.height, 0)
        pages[currentPageIndex].elements[idx].position = CGPoint(
            x: min(max(topLeft.x, 0), maxX),
            y: min(max(topLeft.y, 0), maxY)
        )
    }

    // MARK: - Adding blocks — each one starts at its own created position

    private var placementCount = 0

    /// A simple cascade for freshly created elements so they don't all land
    /// at (0, 0) on top of each other. This is a creation-time position
    /// only — afterwards the element owns it completely.
    private func nextDefaultPosition() -> CGPoint {
        defer { placementCount += 1 }
        let inset: CGFloat = 40
        let spacing: CGFloat = 130
        let column = placementCount % 3
        let row = placementCount / 3
        return CGPoint(
            x: inset + CGFloat(column) * spacing,
            y: inset + CGFloat(row) * spacing
        )
    }

    @discardableResult
    func addText() -> CanvasElement {
        let element = CanvasElement(
            kind: .text,
            position: nextDefaultPosition(),
            width: min(DesignSystem.defaultTextWidth, canvasWidth),
            height: DesignSystem.minBlockHeight,
            text: ""
        )
        pages[currentPageIndex].elements.append(element)
        insertLayerRefOnTop(.element(element.id), onPageAt: currentPageIndex)
        select(element.id)
        // Enter typing mode immediately: select + focus the new text block so
        // its `AutoGrowingTextView` becomes first responder and the keyboard
        // opens without an extra tap. Cursor lands at the start of the field.
        focusText(element.id)
        return element
    }

    @discardableResult
    func addImage(data: Data) -> CanvasElement? {
        let fileName = UUID().uuidString + ".jpg"
        let fileURL = imagesURL.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
        } catch {
            print("Failed to save image: \(error)")
            return nil
        }
        // Reasonable content-based default size (never full canvas width),
        // with height derived from the image's own aspect ratio.
        let sourceSize = UIImage(data: data)?.size ?? CGSize(width: 4, height: 3)
        let baseWidth = min(DesignSystem.defaultImageWidth, canvasWidth)
        let height: CGFloat = sourceSize.width > 0
            ? max(DesignSystem.minBlockHeight, baseWidth * sourceSize.height / sourceSize.width)
            : DesignSystem.minBlockHeight
        let element = CanvasElement(
            kind: .image,
            position: nextDefaultPosition(),
            width: baseWidth,
            height: height,
            imageFileName: fileName
        )
        pages[currentPageIndex].elements.append(element)
        insertLayerRefOnTop(.element(element.id), onPageAt: currentPageIndex)
        select(element.id)
        return element
    }

    @discardableResult
    func addAudio(fileURL sourceURL: URL, duration: TimeInterval) -> CanvasElement? {
        let fileName = UUID().uuidString + ".m4a"
        let destURL = audioURL.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            print("Failed to save audio: \(error)")
            return nil
        }
        let element = CanvasElement(
            kind: .audio,
            position: nextDefaultPosition(),
            width: min(DesignSystem.defaultAudioWidth, canvasWidth),
            height: 120,
            audioFileName: fileName,
            audioDuration: duration
        )
        pages[currentPageIndex].elements.append(element)
        insertLayerRefOnTop(.element(element.id), onPageAt: currentPageIndex)
        select(element.id)
        return element
    }

    private var canvasWidth: CGFloat {
        max(canvasSize.width, DesignSystem.minBlockWidth)
    }

    // MARK: - Resizing

    @discardableResult
    func setWidth(_ id: UUID, to width: CGFloat) -> CGFloat {
        guard let idx = pageAndElementIndex(for: id) else { return width }
        let clamped = min(max(width, DesignSystem.minBlockWidth), canvasWidth)
        pages[idx.page].elements[idx.element].width = clamped
        return clamped
    }

    /// No-op for `.text` — its height is never user-set, only measured.
    @discardableResult
    func setHeight(_ id: UUID, to height: CGFloat) -> CGFloat {
        guard let idx = pageAndElementIndex(for: id),
              pages[idx.page].elements[idx.element].kind != .text else { return height }
        let clamped = max(height, DesignSystem.minBlockHeight)
        pages[idx.page].elements[idx.element].height = clamped
        return clamped
    }

    /// Text height is measured by `AutoGrowingTextView` and fed straight
    /// into the element's stored height, so its frame always matches its
    /// content without any flow engine.
    func setTextHeight(_ id: UUID, height: CGFloat) {
        guard let idx = pageAndElementIndex(for: id),
              pages[idx.page].elements[idx.element].kind == .text else { return }
        let newHeight = max(height.rounded(), DesignSystem.minBlockHeight)
        if pages[idx.page].elements[idx.element].height != newHeight {
            pages[idx.page].elements[idx.element].height = newHeight
        }
    }

    func updateElementText(_ id: UUID, text: String) {
        guard let idx = pageAndElementIndex(for: id) else { return }
        pages[idx.page].elements[idx.element].text = text
    }

    /// Writes through to the current page's `bodyText`. Goes through the
    /// `bodyText` setter so equality is checked and the @Published
    /// `pages` only changes when the value actually changes (avoids
    /// unnecessary SwiftUI invalidations on every keystroke).
    func updateBodyText(_ text: String) {
        bodyText = text
    }

    func setBodyFocused(_ focused: Bool) {
        if bodyFocused != focused {
            bodyFocused = focused
            if !focused {
                // Clear the caret rect so the canvas doesn't keep an
                // offset around after the user dismisses the keyboard
                // or moves to a different surface.
                bodyCaretRect = nil
            }
        }
    }

    func setBodyCaretRect(_ rect: CGRect?) {
        // Bail on no-op writes — `bodyCaretRect` is observed by the
        // writing canvas, and `CGRect` equality alone is enough to
        // short-circuit the typical "caret blinks but the rect didn't
        // move" case.
        if bodyCaretRect != rect {
            bodyCaretRect = rect
        }
    }

    // MARK: - Removal

    func remove(_ id: UUID) {
        guard let idx = pageAndElementIndex(for: id) else { return }
        if audioPlayer.elementID == id { audioPlayer.stop() }
        pages[idx.page].elements.remove(at: idx.element)
        removeLayerRef(.element(id), fromPageAt: idx.page)
        if selectedElementID == id { selectedElementID = nil }
        if focusedTextID == id { focusedTextID = nil }
    }
    // MARK: - Helpers

    /// Locates an element across all pages. Returns `(pageIndex, elementIndex)`
    /// so callers can mutate the right element on the right page. Scoped to
    /// `currentPageIndex` today (selection only ever points at the visible
    /// page) but kept cross-page-safe for future "select from another page"
    /// flows.
    private func pageAndElementIndex(for id: UUID) -> (page: Int, element: Int)? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        if let element = pages[currentPageIndex].elements.firstIndex(where: { $0.id == id }) {
            return (currentPageIndex, element)
        }
        return nil
    }
}
