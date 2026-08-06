import SwiftUI
import PencilKit
internal import Combine

/// Owns every block and the layout engine that positions them.
///
/// The big change from the free-placement version: blocks no longer
/// store an (x, y) position at all. `layout()` computes every block's
/// on-screen frame on demand — a simple flow layout (like CSS
/// flex-wrap) over each block's `width`/`height` and its order in
/// `elements`. Because position is always *derived*, changing a size
/// automatically reflows everything after it: there's no separate "now
/// go update the neighbors" step to get wrong, and overlap is
/// structurally impossible rather than something we check for.
final class CanvasStore: ObservableObject {
    @Published var elements: [CanvasElement] = []
    @Published var drawings: [UUID: PKDrawing] = [:]
    @Published var selectedElementID: UUID?

    /// Measured intrinsic height per text block, fed back from
    /// `AutoGrowingTextView` as the user types or its width changes.
    /// This is what makes "no fixed height for text" real: text's row
    /// height in the layout comes from here, not from `element.height`.
    @Published var textHeights: [UUID: CGFloat] = [:]

    /// The frame size each drawing block's `PKDrawing` strokes are
    /// CURRENTLY expressed in. `PKDrawing` stores strokes in absolute
    /// coordinates — resizing the view alone does nothing to them, so
    /// this is what lets `scaleDrawing` compute "how much did this
    /// block grow/shrink" and transform the strokes to match.
    @Published var drawingContentSizes: [UUID: CGSize] = [:]

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

    // MARK: - Layout

    func updateContainerWidth(_ width: CGFloat) {
        guard width > 0, width != containerWidth else { return }
        containerWidth = width
    }

    /// Multi-page layout engine. Given full physical page width and height, computes
    /// bounded page layouts containing block slices. Text automatically splits across pages
    /// at line boundaries, and non-text blocks reflow to subsequent pages when space is insufficient.
    func layoutPages(pageWidth: CGFloat, pageHeight: CGFloat) -> [PageLayout] {
        let effectiveWidth = max(pageWidth - DesignSystem.pagePadding * 2, 100)
        let effectiveContentHeight = max(pageHeight - DesignSystem.pagePadding * 2 - DesignSystem.pageHeaderHeight, 100)
        updateContainerWidth(effectiveWidth)

        var pages: [PageLayout] = []
        var currentPageElements: [PlacedElement] = []
        var pageIndex = 0
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0

        func finishCurrentPage() {
            pages.append(PageLayout(id: pageIndex, pageIndex: pageIndex, elements: currentPageElements))
            pageIndex += 1
            currentPageElements = []
            cursorX = 0
            cursorY = 0
            rowHeight = 0
        }

        for element in elements {
            let width = min(max(element.width, DesignSystem.minBlockWidth), effectiveWidth)

            if element.kind == .text {
                if cursorX > 0 {
                    cursorX = 0
                    cursorY += rowHeight + DesignSystem.blockSpacing
                    rowHeight = 0
                }

                var remainingText = element.text ?? ""
                var sliceIndex = 0

                if remainingText.isEmpty {
                    let availableY = effectiveContentHeight - cursorY
                    if availableY < 40 {
                        finishCurrentPage()
                    }
                    let height = DesignSystem.minBlockHeight
                    let sliceID = "\(element.id.uuidString)_slice_\(sliceIndex)"
                    let frame = CGRect(x: 0, y: cursorY, width: width, height: height)
                    currentPageElements.append(
                        PlacedElement(
                            id: sliceID,
                            canonicalID: element.id,
                            kind: .text,
                            frame: frame,
                            textSubstring: "",
                            isSplitText: false,
                            sliceIndex: 0
                        )
                    )
                    cursorY += height + DesignSystem.blockSpacing
                    cursorX = 0
                    rowHeight = 0
                } else {
                    while !remainingText.isEmpty {
                        var availableY = effectiveContentHeight - cursorY
                        if availableY < 24 {
                            finishCurrentPage()
                            availableY = effectiveContentHeight
                        }

                        let textContentWidth = max(width - DesignSystem.blockContentPadding * 2, 1)
                        let textMaxHeight = max(availableY - DesignSystem.blockContentPadding * 2, 1)
                        let fitLen = TextSplitter.fittingLength(for: remainingText, width: textContentWidth, maxHeight: textMaxHeight)

                        if fitLen >= remainingText.count {
                            let measured = TextSplitter.measureHeight(for: remainingText, width: textContentWidth) + DesignSystem.blockContentPadding * 2
                            let height = max(measured, DesignSystem.minBlockHeight)
                            let sliceID = "\(element.id.uuidString)_slice_\(sliceIndex)"
                            let frame = CGRect(x: 0, y: cursorY, width: width, height: height)
                            let isSplit = (sliceIndex > 0)
                            currentPageElements.append(
                                PlacedElement(
                                    id: sliceID,
                                    canonicalID: element.id,
                                    kind: .text,
                                    frame: frame,
                                    textSubstring: remainingText,
                                    isSplitText: isSplit,
                                    sliceIndex: sliceIndex
                                )
                            )
                            cursorY += height + DesignSystem.blockSpacing
                            cursorX = 0
                            rowHeight = 0
                            remainingText = ""
                        } else if fitLen > 0 {
                            let fittingIndex = remainingText.index(remainingText.startIndex, offsetBy: fitLen)
                            let fittingText = String(remainingText[..<fittingIndex])
                            remainingText = String(remainingText[fittingIndex...])

                            let measured = TextSplitter.measureHeight(for: fittingText, width: textContentWidth) + DesignSystem.blockContentPadding * 2
                            let height = max(measured, DesignSystem.minBlockHeight)
                            let sliceID = "\(element.id.uuidString)_slice_\(sliceIndex)"
                            let frame = CGRect(x: 0, y: cursorY, width: width, height: height)
                            currentPageElements.append(
                                PlacedElement(
                                    id: sliceID,
                                    canonicalID: element.id,
                                    kind: .text,
                                    frame: frame,
                                    textSubstring: fittingText,
                                    isSplitText: true,
                                    sliceIndex: sliceIndex
                                )
                            )
                            sliceIndex += 1
                            finishCurrentPage()
                        } else {
                            finishCurrentPage()
                        }
                    }
                }
            } else {
                var height = max(element.height, DesignSystem.minBlockHeight)
                if height > effectiveContentHeight {
                    height = effectiveContentHeight
                }

                if cursorX > 0 && cursorX + width > effectiveWidth + 0.5 {
                    cursorX = 0
                    cursorY += rowHeight + DesignSystem.blockSpacing
                    rowHeight = 0
                }

                if cursorY + height > effectiveContentHeight && cursorY > 0 {
                    finishCurrentPage()
                }

                let sliceID = "\(element.id.uuidString)_slice_0"
                let frame = CGRect(x: cursorX, y: cursorY, width: width, height: height)
                currentPageElements.append(
                    PlacedElement(
                        id: sliceID,
                        canonicalID: element.id,
                        kind: element.kind,
                        frame: frame,
                        textSubstring: nil,
                        isSplitText: false,
                        sliceIndex: 0
                    )
                )
                cursorX += width + DesignSystem.blockSpacing
                rowHeight = max(rowHeight, height)
            }
        }

        if !currentPageElements.isEmpty || pages.isEmpty {
            pages.append(PageLayout(id: pageIndex, pageIndex: pageIndex, elements: currentPageElements))
        }

        return pages
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

    // MARK: - Adding blocks — default width matches container width

    @discardableResult
    func addText() -> CanvasElement {
        let element = CanvasElement(kind: .text, width: containerWidth, height: DesignSystem.minBlockHeight, text: "")
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
        let element = CanvasElement(kind: .image, width: containerWidth, height: 260, imageFileName: fileName)
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
        let element = CanvasElement(
            kind: .audio, width: containerWidth, height: 120,
            audioFileName: fileName, audioDuration: duration
        )
        elements.append(element)
        selectedElementID = element.id
        focusLastPage()
        return element
    }

    @discardableResult
    func addDrawing() -> CanvasElement {
        let size = CGSize(width: containerWidth, height: 260)
        let element = CanvasElement(kind: .drawing, width: size.width, height: size.height)
        elements.append(element)
        drawings[element.id] = PKDrawing()
        drawingContentSizes[element.id] = size
        selectedElementID = element.id
        focusLastPage()
        return element
    }

    private func focusLastPage() {
        let pages = layoutPages(pageWidth: containerWidth + DesignSystem.pagePadding * 2, pageHeight: 800)
        if let lastPage = pages.last {
            currentPageIndex = lastPage.pageIndex
        }
    }

    // MARK: - Resizing — the only way a block's size ever changes

    /// Returns the width actually applied (post-clamp) — callers that
    /// need to know the real final size, like `scaleDrawing`, use this
    /// instead of assuming their requested value stuck.
    @discardableResult
    func setWidth(_ id: UUID, to width: CGFloat) -> CGFloat {
        guard let idx = elements.firstIndex(where: { $0.id == id }) else { return width }
        let clamped = min(max(width, DesignSystem.minBlockWidth), containerWidth)
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

    /// Scales a drawing block's stored strokes to fill a new size,
    /// keeping the drawing itself in lockstep with its frame instead of
    /// staying pinned at whatever size it was originally drawn at.
    /// Called once, after both dimensions of a resize are committed,
    /// with the block's real final (post-clamp) size.
    func scaleDrawing(_ id: UUID, to newSize: CGSize) {
        defer { drawingContentSizes[id] = newSize }

        guard let oldSize = drawingContentSizes[id],
              oldSize.width > 0, oldSize.height > 0,
              let current = drawings[id], !current.strokes.isEmpty else {
            return
        }
        let scaleX = newSize.width / oldSize.width
        let scaleY = newSize.height / oldSize.height
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0 else { return }

        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        drawings[id] = current.transformed(using: transform)
    }

    func update(_ element: CanvasElement) {
        guard let idx = elements.firstIndex(where: { $0.id == element.id }) else { return }
        elements[idx] = element
    }

    func remove(_ id: UUID) {
        elements.removeAll { $0.id == id }
        drawings[id] = nil
        textHeights[id] = nil
        drawingContentSizes[id] = nil
        if selectedElementID == id { selectedElementID = nil }
    }
}
