import SwiftUI
import PencilKit

/// The board's drawing surface. Unlike the old inert version, this
/// `PKCanvasView` becomes fully interactive when Draw mode is on: it takes
/// first responder, shows the system `PKToolPicker` (same UI Notes/Freeform
/// use), and lets PencilKit own touch handling completely — pen, marker,
/// pencil, eraser, ruler, undo/redo, all native, all free.
///
/// When Draw mode is off, the canvas view is non-interactive and sits
/// underneath the elements layer, which is exactly how it behaved before.
///
/// Drawing is scoped to the current page: when the page changes, the
/// `PKCanvasView`'s drawing is swapped. PencilKit echoes that swap back
/// via `canvasViewDrawingDidChange`; the coordinator recognises the echo
/// (the new `canvasView.drawing` is byte-equal to the drawing it just
/// assigned) and ignores it, so it doesn't bounce the previous page's
/// strokes into the new one. Real user strokes are never echoes, so they
/// always reach the store.
struct ScribbleCanvasView: UIViewRepresentable {
    @ObservedObject var store: CanvasStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = store.scribble
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput // finger + Pencil, like Notes
        // PKCanvasView is a UIScrollView subclass and ships with its own
        // built-in `UIPinchGestureRecognizer`. In writing mode that
        // recognizer is fully active and competes with the SwiftUI
        // `MagnifyGesture` in `WritingCanvasView`, making pinch-out to
        // exit unreliable (and pinch-in sluggish). Clamp the scroll
        // view's own zoom range to 1× so its pinch is a no-op and the
        // SwiftUI gesture gets the pinch cleanly.
        canvasView.minimumZoomScale = 1.0
        canvasView.maximumZoomScale = 1.0
        canvasView.bouncesZoom = false
        // Carousel mode keeps the PKCanvasView non-interactive so touches
        // on the small preview page don't leave stray strokes; writing
        // mode (zoomed in) turns interaction on.
        canvasView.isUserInteractionEnabled = store.writingMode
        canvasView.delegate = context.coordinator
        context.coordinator.canvasView = canvasView
        context.coordinator.boundPageID = store.pages.indices.contains(store.currentPageIndex)
            ? store.pages[store.currentPageIndex].id
            : nil
        // Seed the echo-skip memory so PencilKit's first delegate callback
        // after the programmatic `drawing` assignment doesn't bounce back
        // and trigger a redundant `@Published` mutation.
        context.coordinator.lastAssignedDrawingData = store.scribble.dataRepresentation()
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        let currentPageID = store.pages.indices.contains(store.currentPageIndex)
            ? store.pages[store.currentPageIndex].id
            : nil

        // Page switched: swap the drawing and arm the coordinator to
        // ignore PencilKit's echo of this exact assignment.
        if context.coordinator.boundPageID != currentPageID {
            context.coordinator.lastAssignedDrawingData = store.scribble.dataRepresentation()
            uiView.drawing = store.scribble
            context.coordinator.boundPageID = currentPageID
            return
        }

        // External changes to store.scribble (rare — e.g. programmatic
        // clear) get mirrored in; avoid reassigning if PencilKit itself
        // was the source of the change (would just be a no-op anyway).
        if uiView.drawing != store.scribble {
            context.coordinator.lastAssignedDrawingData = store.scribble.dataRepresentation()
            uiView.drawing = store.scribble
        }

        context.coordinator.setWritingMode(store.writingMode, on: uiView)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let store: CanvasStore
        weak var canvasView: PKCanvasView?
        private let toolPicker = PKToolPicker()
        private var isShowingToolPicker = false

        /// Page whose drawing is currently shown in the `PKCanvasView`.
        /// Used to detect a page switch and swap drawings safely.
        var boundPageID: UUID?

        /// Data of the drawing we last programmatically assigned to the
        /// `PKCanvasView`. Used to recognise PencilKit's echo of that
        /// assignment (which always reports an equal drawing back through
        /// `canvasViewDrawingDidChange`) and skip it without dropping real
        /// user strokes — which are never byte-equal to the last assignment.
        var lastAssignedDrawingData: Data?

        init(store: CanvasStore) {
            self.store = store
        }

        func setWritingMode(_ isOn: Bool, on canvasView: PKCanvasView) {
            guard isOn != isShowingToolPicker else { return }
            isShowingToolPicker = isOn

            if isOn {
                canvasView.isUserInteractionEnabled = true
                toolPicker.addObserver(canvasView)
                toolPicker.setVisible(true, forFirstResponder: canvasView)
                canvasView.becomeFirstResponder()
            } else {
                toolPicker.setVisible(false, forFirstResponder: canvasView)
                toolPicker.removeObserver(canvasView)
                canvasView.resignFirstResponder()
                canvasView.isUserInteractionEnabled = false
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Skip PencilKit's echo of our last programmatic assignment.
            // Real user strokes always produce a different drawing, so
            // they fall through to the store.
            if let lastData = lastAssignedDrawingData,
               canvasView.drawing.dataRepresentation() == lastData {
                lastAssignedDrawingData = nil
                return
            }
            store.scribble = canvasView.drawing
        }
    }
}
