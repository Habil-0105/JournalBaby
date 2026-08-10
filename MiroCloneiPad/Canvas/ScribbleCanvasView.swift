import SwiftUI
import PencilKit

/// The page-level PencilKit canvas. Sized to the page's drawable rect
/// by `PageView`, so its internal coordinate system IS the page's
/// drawing coordinate space — strokes recorded here are in
/// "page coordinates", independent of any element block.
///
/// `isActive` controls whether the canvas intercepts touches:
/// - **Scribble mode on** (`isActive == true`): the canvas is
///   interactive and PencilKit captures touches, producing strokes.
///   During drawing, no element gestures compete for the touch.
/// - **Scribble mode off** (`isActive == false`): the canvas is a
///   non-interactive overlay. Touches fall straight through to the
///   page / blocks below, preserving the existing Text / Image / Audio
///   interactions.
///
/// Strokes bind through to `CanvasStore.pageDrawings[pageIndex]` via
/// the `drawing` binding. The delegate's
/// `canvasViewDrawingDidChange` callback is the only path that writes
/// back into the store.
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
