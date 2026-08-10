import SwiftUI
import UIKit
import PencilKit
internal import Combine

/// Owns every block on every page, plus the per-page drawing layer.
///
/// Each journal page contains two things:
/// - a list of element blocks (`elements`), which are Text / Image /
///   Audio blocks at stored `(x, y)` page coordinates;
/// - a drawing layer (`pageDrawings`), which is a `PKDrawing` that
///   records strokes directly onto the page in the page's coordinate
///   system.
///
/// Strokes are NOT elements: they don't have a frame, can't be
/// selected, dragged, or resized. They belong to the page the user
/// drew them on, in that page's natural coordinate space.
final class CanvasStore: ObservableObject {
    @Published var elements: [CanvasElement] = []
    @Published var selectedElementID: UUID?

    /// Page-level drawing layer: a `PKDrawing` per page index. Strokes
    /// are stored in the same coordinate system the live
    /// `PKCanvasView` exposes — i.e., canvas-local points. Because the
    /// canvas is sized to the page's drawable rect, those points ARE
    /// the page's drawing coordinates.
    @Published var pageDrawings: [Int: PKDrawing] = [:]

    /// Measured intrinsic height per text block, fed back from
    /// `AutoGrowingTextView` as the user types or its width changes.
    /// This is what makes "no fixed height for text" real: text's row
    /// height in the layout comes from here, not from `element.height`.
    @Published var textHeights: [UUID: CGFloat] = [:]

    /// Width available for laying out blocks — screen width minus page
    /// padding on both sides. Set once per layout pass by `ContentView`.
    @Published private(set) var containerWidth: CGFloat = 800

    @Published var currentPageIndex: Int = 0

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

    /// Monotonically-increasing counter used to assign default `zIndex`
    /// values so newly-added blocks land above existing ones.
    private var nextZIndex: Int = 0

    // MARK: - Layout

    func updateContainerWidth(_ width: CGFloat) {
        guard width > 0, width != containerWidth else { return }
        containerWidth = width
    }

    /// Vertical gap between consecutive text slices on stacked pages.
    /// Only used to keep slices from overlapping each other when a
    /// single text block overflows the page; not used to position any
    /// other block.
    private let textSliceVerticalGap: CGFloat = 24

    /// Multi-page layout engine for **free-positioned** elements.
    ///
    /// Position is now stored on each `CanvasElement` (`x`, `y`). The
    /// layout engine's only remaining responsibilities are:
    ///
    /// 1. Decide which slices (one text block may produce several) need
    ///    more vertical room than a single page offers, and assign each
    ///    slice the next available page.
    /// 2. Build a `PlacedElement.frame` whose origin is the canonical
    ///    element's stored `(x, y)` — NOT something recomputed from
    ///    array order.
    ///
    /// It never moves an element to make room for another. Adding,
    /// removing, resizing, or moving one block leaves every other
    /// block's position untouched.
    func layoutPages(pageWidth: CGFloat, pageHeight: CGFloat) -> [PageLayout] {
        let effectiveWidth = max(pageWidth - DesignSystem.pagePadding * 2, 100)
        let effectiveContentHeight = max(pageHeight - DesignSystem.pagePadding * 2 - DesignSystem.pageHeaderHeight, 100)
        updateContainerWidth(effectiveWidth)

        var pages: [PageLayout] = []
        var currentPageElements: [PlacedElement] = []
        var pageIndex = 0

        for element in elements {
            let width = max(element.width, DesignSystem.minBlockWidth)

            if element.kind == .text {
                var remainingText = element.text ?? ""
                var sliceIndex = 0

                if remainingText.isEmpty {
                    // Empty text: one slice on the element's own page
                    // using the stored position.
                    currentPageElements.append(makeTextSlice(
                        element: element,
                        sliceIndex: 0,
                        text: "",
                        height: DesignSystem.minBlockHeight,
                        pageOffset: 0
                    ))
                } else {
                    while !remainingText.isEmpty {
                        let availableY = effectiveContentHeight
                        let textContentWidth = max(width - DesignSystem.blockContentPadding * 2, 1)
                        let textMaxHeight = max(availableY - DesignSystem.blockContentPadding * 2, 1)
                        let fitLen = TextSplitter.fittingLength(for: remainingText, width: textContentWidth, maxHeight: textMaxHeight)

                        if fitLen >= remainingText.count {
                            let measured = TextSplitter.measureHeight(for: remainingText, width: textContentWidth) + DesignSystem.blockContentPadding * 2
                            let height = max(measured, DesignSystem.minBlockHeight)
                            currentPageElements.append(makeTextSlice(
                                element: element,
                                sliceIndex: sliceIndex,
                                text: remainingText,
                                height: height,
                                pageOffset: 0
                            ))
                            sliceIndex += 1
                            remainingText = ""
                        } else if fitLen > 0 {
                            let fittingIndex = remainingText.index(remainingText.startIndex, offsetBy: fitLen)
                            let fittingText = String(remainingText[..<fittingIndex])
                            remainingText = String(remainingText[fittingIndex...])

                            let measured = TextSplitter.measureHeight(for: fittingText, width: textContentWidth) + DesignSystem.blockContentPadding * 2
                            let height = max(measured, DesignSystem.minBlockHeight)
                            currentPageElements.append(makeTextSlice(
                                element: element,
                                sliceIndex: sliceIndex,
                                text: fittingText,
                                height: height,
                                pageOffset: 0
                            ))
                            sliceIndex += 1
                        } else {
                            break
                        }

                        if !remainingText.isEmpty {
                            // Overflow: roll to a new page, keep the
                            // element's stored (x, y) — the layout
                            // engine never INVENTS a position, it only
                            // chooses which page this slice belongs to.
                            pages.append(PageLayout(id: pageIndex, pageIndex: pageIndex, elements: currentPageElements))
                            pageIndex += 1
                            currentPageElements = []
                        }
                    }
                }
            } else {
                // Non-text blocks (image, audio): one slice, placed at
                // the canonical element's stored (x, y). The page it
                // belongs to is always the current one — the caller
                // (PageView / BookPageCurlView) decides whether the
                // slice is visible given the displayed page.
                let height = max(element.height, DesignSystem.minBlockHeight)
                let frame = CGRect(x: element.x, y: element.y, width: width, height: height)
                currentPageElements.append(
                    PlacedElement(
                        id: "\(element.id.uuidString)_slice_0",
                        canonicalID: element.id,
                        kind: element.kind,
                        frame: frame,
                        textSubstring: nil,
                        isSplitText: false,
                        sliceIndex: 0
                    )
                )
            }
        }

        if !currentPageElements.isEmpty || pages.isEmpty {
            pages.append(PageLayout(id: pageIndex, pageIndex: pageIndex, elements: currentPageElements))
        }

        return pages
    }

    /// Builds a `PlacedElement` for a text slice whose origin is the
    /// canonical element's stored `(x, y)`. `pageOffset` is non-zero
    /// when the slice has spilled onto a later page so the visual
    /// offset still keeps the slice directly below its predecessor.
    private func makeTextSlice(
        element: CanvasElement,
        sliceIndex: Int,
        text: String,
        height: CGFloat,
        pageOffset: CGFloat
    ) -> PlacedElement {
        let width = max(element.width, DesignSystem.minBlockWidth)
        let yOffset = element.y + CGFloat(sliceIndex) * textSliceVerticalGap
        let frame = CGRect(x: element.x, y: yOffset + pageOffset, width: width, height: height)
        return PlacedElement(
            id: "\(element.id.uuidString)_slice_\(sliceIndex)",
            canonicalID: element.id,
            kind: .text,
            frame: frame,
            textSubstring: text,
            isSplitText: sliceIndex > 0,
            sliceIndex: sliceIndex
        )
    }

    /// Computes spreads for either single-page mode (iPhone) or two-page book spread mode (iPad).
    func layoutSpreads(pageWidth: CGFloat, pageHeight: CGFloat) -> [BookSpread] {
        let singlePageWidth: CGFloat
        singlePageWidth = pageWidth

        let pages = layoutPages(pageWidth: singlePageWidth, pageHeight: pageHeight)

        return pages.map { page in
            BookSpread(id: page.pageIndex, spreadIndex: page.pageIndex, leftPage: page, rightPage: nil)
        }
    }

    func updateTextSlice(canonicalID: UUID, sliceIndex: Int, newText: String, slices: [String]) {
        guard let idx = elements.firstIndex(where: { $0.id == canonicalID }) else { return }
        var updatedSlices = slices
        if sliceIndex < updatedSlices.count {
            updatedSlices[sliceIndex] = newText
        } else {
            updatedSlices.append(newText)
        }
        let fullText = updatedSlices.joined()
        if elements[idx].text != fullText {
            elements[idx].text = fullText
        }
    }

    func setTextHeight(_ id: UUID, height: CGFloat) {
        let rounded = height.rounded()
        guard textHeights[id] != rounded else { return }
        textHeights[id] = rounded
    }

    // MARK: - Adding blocks — each new block gets a per-kind intrinsic
    // default size, NOT the full canvas width. The user has to
    // explicitly resize a block to make it wider. Existing resized
    // sizes are preserved: `setWidth` / `setHeight` only enforce a
    // floor, and that path is independent of this default-size path.

    /// Per-kind default sizes for new blocks when there's no intrinsic
    /// source dimension to read from. Picked so each block starts at a
    /// reasonable intrinsic dimension rather than the full canvas width:
    /// - **Text**: a comfortable single-line width.
    /// - **Image**: 320×213 (3:2) placeholder, used only as the fallback
    ///   if `UIImage(data:)` can't decode the source bytes. The actual
    ///   `addImage(data:)` path preserves the source aspect ratio.
    /// - **Audio**: a horizontal audio player bar.
    private func defaultSize(for kind: ElementKind) -> CGSize {
        switch kind {
        case .text:
            return CGSize(width: 280, height: DesignSystem.minBlockHeight)
        case .image:
            return CGSize(width: 320, height: 213)
        case .audio:
            return CGSize(width: 320, height: 120)
        }
    }

    @discardableResult
    func addText() -> CanvasElement {
        let next = nextPlacementForNewBlock()
        let size = defaultSize(for: .text)
        let element = CanvasElement(
            kind: .text,
            x: next.x,
            y: next.y,
            zIndex: nextZIndex,
            width: size.width,
            height: size.height,
            text: ""
        )
        consumeNextZIndex()
        elements.append(element)
        selectedElementID = element.id
        focusLastPage()
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
        let next = nextPlacementForNewBlock()
        // Read the source image's pixel size so the new block can
        // preserve its aspect ratio. If reading fails, fall back to
        // the generic placeholder.
        let intrinsic = UIImage(data: data)?.size ?? defaultSize(for: .image)
        let maxWidth: CGFloat = 320
        let aspect = intrinsic.height > 0 ? intrinsic.height / intrinsic.width : 0.66
        let width = min(intrinsic.width, maxWidth)
        let height = max(width * aspect, 80)

        let element = CanvasElement(
            kind: .image,
            x: next.x,
            y: next.y,
            zIndex: nextZIndex,
            width: width,
            height: height,
            imageFileName: fileName
        )
        consumeNextZIndex()
        elements.append(element)
        selectedElementID = element.id
        focusLastPage()
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
        let next = nextPlacementForNewBlock()
        let size = defaultSize(for: .audio)
        let element = CanvasElement(
            kind: .audio,
            x: next.x,
            y: next.y,
            zIndex: nextZIndex,
            width: size.width,
            height: size.height,
            audioFileName: fileName,
            audioDuration: duration
        )
        consumeNextZIndex()
        elements.append(element)
        selectedElementID = element.id
        focusLastPage()
        return element
    }

    /// Picks an initial (x, y) for a newly-added block: stacks below
    /// existing blocks with a small diagonal offset so multiple new
    /// blocks don't all land at exactly (0, 0) and obscure each other.
    private func nextPlacementForNewBlock() -> CGPoint {
        let inset: CGFloat = DesignSystem.pagePadding
        let cascade: CGFloat = 32
        if let last = elements.last {
            return CGPoint(x: last.x + cascade, y: last.y + cascade)
        }
        return CGPoint(x: inset, y: inset)
    }

    private func consumeNextZIndex() {
        nextZIndex += 1
    }

    private func focusLastPage() {
        let pages = layoutPages(pageWidth: containerWidth + DesignSystem.pagePadding * 2, pageHeight: 800)
        if let lastPage = pages.last {
            currentPageIndex = lastPage.pageIndex
        }
    }

    // MARK: - Page-level drawing layer

    /// Returns the drawing stored for `pageIndex`, or an empty drawing
    /// if the page has no strokes yet. Strokes recorded in this drawing
    /// are in the page's coordinate system — i.e., the same coordinate
    /// space the live `PKCanvasView` in `PageDrawingView` exposes.
    func drawing(forPage pageIndex: Int) -> PKDrawing {
        pageDrawings[pageIndex] ?? PKDrawing()
    }

    /// Writes the latest drawing for `pageIndex`. Called by the live
    /// canvas's `canvasViewDrawingDidChange` delegate.
    func setDrawing(_ drawing: PKDrawing, forPage pageIndex: Int) {
        // Skip the publish when nothing actually changed — PencilKit
        // fires its delegate on every stroke tweak, including trivial
        // mid-stroke updates, and a redundant publish forces a full
        // page re-render.
        if pageDrawings[pageIndex] == drawing { return }
        pageDrawings[pageIndex] = drawing
    }

    /// Clears the strokes on a single page.
    func clearDrawing(forPage pageIndex: Int) {
        pageDrawings[pageIndex] = nil
    }

    // MARK: - Resizing — free-form canvas: only the floor clamps
    // remain, not the page / container ceiling.

    /// Returns the width actually applied (post-clamp) — callers can
    /// read it back if they need to know what the post-clamp width was.
    @discardableResult
    func setWidth(_ id: UUID, to width: CGFloat) -> CGFloat {
        guard let idx = elements.firstIndex(where: { $0.id == id }) else { return width }
        let clamped = max(width, DesignSystem.minBlockWidth)
        elements[idx].width = clamped
        return clamped
    }

    /// No-op for `.text` — its height is never user-set, only measured.
    @discardableResult
    func setHeight(_ id: UUID, to height: CGFloat) -> CGFloat {
        guard let idx = elements.firstIndex(where: { $0.id == id }), elements[idx].kind != .text else { return height }
        let clamped = max(height, DesignSystem.minBlockHeight)
        elements[idx].height = clamped
        return clamped
    }

    /// Writes back a new top-left position for a block. No clamps:
    /// elements are allowed to leave the visible page region (the
    /// caller can pan / scroll, or simply move on). This is the only
    /// mutator the drag gesture calls.
    func setPosition(_ id: UUID, x: CGFloat, y: CGFloat) {
        guard let idx = elements.firstIndex(where: { $0.id == id }) else { return }
        elements[idx].x = x
        elements[idx].y = y
    }

    /// Promotes a block to the top of the current z-order so further
    /// interactions on overlapping stacks target it.
    func bringToFront(_ id: UUID) {
        guard let idx = elements.firstIndex(where: { $0.id == id }) else { return }
        consumeNextZIndex()
        elements[idx].zIndex = nextZIndex
    }

    func update(_ element: CanvasElement) {
        guard let idx = elements.firstIndex(where: { $0.id == element.id }) else { return }
        elements[idx] = element
    }

    func remove(_ id: UUID) {
        elements.removeAll { $0.id == id }
        textHeights[id] = nil
        if selectedElementID == id { selectedElementID = nil }
    }
}
