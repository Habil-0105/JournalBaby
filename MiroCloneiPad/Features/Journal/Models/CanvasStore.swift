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

    @Published var selectedElementID: UUID?

    /// The text block currently being edited (first responder). Kept
    /// separate from `selectedElementID` so a text block can be selected
    /// AND dragged without fighting its text view.
    @Published var focusedTextID: UUID?

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
    }

    /// Starts editing a text block (double-tap / explicit edit action).
    /// Also selects it and exits Draw mode.
    func focusText(_ id: UUID) {
        selectedElementID = id
        focusedTextID = id
        drawMode = false
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
            drawMode = false
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
        currentPageIndex = index
        selectedElementID = nil
        focusedTextID = nil
        drawMode = false
    }

    /// Removes the page at `index`. If it was the current page, falls
    /// back to the neighbour (preferring the previous page); if it was
    /// the only page, an empty page replaces it so the board always has
    /// at least one page to draw on.
    func removePage(at index: Int) {
        guard pages.indices.contains(index) else { return }
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
        select(element.id)
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

    // MARK: - Removal

    func remove(_ id: UUID) {
        guard let idx = pageAndElementIndex(for: id) else { return }
        pages[idx.page].elements.remove(at: idx.element)
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
