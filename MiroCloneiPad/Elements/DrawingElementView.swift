import SwiftUI
import PencilKit

/// A drawing block. Unlike the old version, this is NOT a canvas the size
/// of the whole page — it's a `PKCanvasView` sized to exactly this
/// block's frame, so strokes can never leave the block, and the block
/// itself can be resized like any other.
///
/// The canvas only accepts touches when the block is selected
/// (`isActive`); this keeps a single tap-to-select behavior consistent
/// across every block kind, and avoids the move/resize handles fighting
/// with pencil input.
struct DrawingElementView: View {
    @ObservedObject var store: CanvasStore
    var element: CanvasElement
    var isActive: Bool

    private var drawingBinding: Binding<PKDrawing> {
        Binding(
            get: { store.drawings[element.id] ?? PKDrawing() },
            set: { store.drawings[element.id] = $0 }
        )
    }

    private var isEmpty: Bool {
        (store.drawings[element.id]?.strokes.isEmpty) ?? true
    }

    var body: some View {
        ZStack {
            Color.white
            ScribbleCanvasView(drawing: drawingBinding, isActive: isActive)
            if !isActive && isEmpty {
                Label("Tap, then draw", systemImage: "pencil.tip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
