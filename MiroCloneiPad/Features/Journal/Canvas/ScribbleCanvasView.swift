import SwiftUI
import PencilKit

/// Display-only PencilKit canvas that paints the board's committed
/// scribble strokes. Scribble *input* is handled by `DrawInputLayer`;
/// this view just renders the resulting `PKDrawing`, so it never needs
/// interaction or a delegate.
struct ScribbleCanvasView: UIViewRepresentable {
    var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isUserInteractionEnabled = false
        canvasView.clipsToBounds = true
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }
}