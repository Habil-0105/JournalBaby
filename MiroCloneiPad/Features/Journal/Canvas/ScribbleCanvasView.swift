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
        canvasView.delegate = context.coordinator
        context.coordinator.canvasView = canvasView
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // External changes to store.scribble (rare — e.g. programmatic
        // clear) get mirrored in; avoid reassigning if PencilKit itself
        // was the source of the change (would just be a no-op anyway).
        if uiView.drawing != store.scribble {
            uiView.drawing = store.scribble
        }

        context.coordinator.setDrawMode(store.drawMode, on: uiView)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let store: CanvasStore
        weak var canvasView: PKCanvasView?
        private let toolPicker = PKToolPicker()
        private var isShowingToolPicker = false

        init(store: CanvasStore) {
            self.store = store
        }

        func setDrawMode(_ isOn: Bool, on canvasView: PKCanvasView) {
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
            store.scribble = canvasView.drawing
        }
    }
}
