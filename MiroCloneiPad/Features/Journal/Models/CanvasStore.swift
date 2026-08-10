import SwiftUI
import Combine
import UIKit
import PencilKit

/// Owns every element and all the canvas state. There is no layout engine
/// here anymore — the old `layoutPages` flow layout is gone. Each element
/// carries its own `position`, and this store is just the single source of
/// truth that views read from and mutate:
///
/// ```
/// store.elements[i].position  ──►  canvas rendering
/// store.elements[i].position  ──►  hit testing / taps
/// drag gesture                ──►  store.moveElement  ──►  position
/// ```
///
/// Because position is stored (not derived), moving, adding, or deleting an
/// element never affects another element's position.
final class CanvasStore: ObservableObject {
    @Published var elements: [CanvasElement] = []
    @Published var selectedElementID: UUID?

    /// The text block currently being edited (first responder). Kept
    /// separate from `selectedElementID` so a text block can be selected
    /// AND dragged without fighting its text view.
    @Published var focusedTextID: UUID?

    /// When true, touches on the canvas draw scribble strokes directly on
    /// the board instead of interacting with elements. Selecting any
    /// element turns it off.
    @Published var drawMode: Bool = false

    /// Freehand strokes drawn directly on the board — a drawing layer under
    /// (and independent of) the elements, keyed to no element.
    @Published var scribble: PKDrawing = PKDrawing()

    /// Size of the canvas content area (from the host GeometryReader).
    /// Used to clamp drags and default placement inside the board.
    @Published private(set) var canvasSize: CGSize = .zero

    func updateCanvasSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != canvasSize else { return }
        canvasSize = size
    }

    // MARK: - Selection, text focus, draw mode

    /// Selects an element (or clears the selection with `nil`). Selecting
    /// any element automatically exits Draw mode and drops text focus, so
    /// the normal select → edit / drag / resize flow always wins.
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

    func toggleDrawMode() {
        drawMode.toggle()
        if drawMode {
            selectedElementID = nil
            focusedTextID = nil
        }
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
        guard let idx = elements.firstIndex(where: { $0.id == id }) else { return }
        let maxX = max(canvasSize.width - elements[idx].width, 0)
        let maxY = max(canvasSize.height - elements[idx].height, 0)
        elements[idx].position = CGPoint(
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
        elements.append(element)
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
        elements.append(element)
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
        elements.append(element)
        select(element.id)
        return element
    }

    private var canvasWidth: CGFloat {
        max(canvasSize.width, DesignSystem.minBlockWidth)
    }

    // MARK: - Resizing

    @discardableResult
    func setWidth(_ id: UUID, to width: CGFloat) -> CGFloat {
        guard let idx = elements.firstIndex(where: { $0.id == id }) else { return width }
        let clamped = min(max(width, DesignSystem.minBlockWidth), canvasWidth)
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

    /// Text height is measured by `AutoGrowingTextView` and fed straight
    /// into the element's stored height, so its frame always matches its
    /// content without any flow engine.
    func setTextHeight(_ id: UUID, height: CGFloat) {
        guard let idx = elements.firstIndex(where: { $0.id == id }), elements[idx].kind == .text else { return }
        let newHeight = max(height.rounded(), DesignSystem.minBlockHeight)
        if elements[idx].height != newHeight {
            elements[idx].height = newHeight
        }
    }

    func updateElementText(_ id: UUID, text: String) {
        guard let idx = elements.firstIndex(where: { $0.id == id }) else { return }
        elements[idx].text = text
    }

    // MARK: - Scribble

    /// Commits a finished freehand stroke to the board's drawing layer.
    func appendStroke(_ stroke: PKStroke) {
        scribble = PKDrawing(strokes: scribble.strokes + [stroke])
    }

    // MARK: - Removal

    func remove(_ id: UUID) {
        elements.removeAll { $0.id == id }
        if selectedElementID == id { selectedElementID = nil }
        if focusedTextID == id { focusedTextID = nil }
    }
}