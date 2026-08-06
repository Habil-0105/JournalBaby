import SwiftUI
import PencilKit

/// A PencilKit canvas that fills whatever frame it's given and clips its
/// contents. Used by `DrawingElementView`, sized to that block's frame —
/// because the view itself never extends beyond its parent's bounds, it's
/// physically impossible to scribble outside the block.
struct ScribbleCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var isActive: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput // allow finger + Apple Pencil
        canvasView.tool = PKInkingTool(.pen, color: UIColor.label, width: 4)
        canvasView.delegate = context.coordinator
        canvasView.isUserInteractionEnabled = isActive
        canvasView.clipsToBounds = true
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.isUserInteractionEnabled = isActive
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: ScribbleCanvasView
        init(_ parent: ScribbleCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
