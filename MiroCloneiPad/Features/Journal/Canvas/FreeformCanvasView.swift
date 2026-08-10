import SwiftUI

/// The single freeform canvas. There is no paging, no flow layout, and no
/// derived positioning: each element is rendered at its own
/// `element.position`, hit-tested there, and moved directly by the drag
/// gesture writing back to that same `position`.
///
/// Layer order (bottom → top):
/// 1. the board surface
/// 2. committed scribble strokes (a drawing layer, not an element)
/// 3. the freeform elements
/// 4. the Draw-mode input surface (only while Draw mode is active)
struct FreeformCanvasView: View {
    @ObservedObject var store: CanvasStore
    var size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.systemGroupedBackground)
            board
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: "canvas")
        .onAppear { store.updateCanvasSize(size) }
        .onChange(of: size) { _, newSize in
            store.updateCanvasSize(newSize)
        }
    }

    private var board: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(Color(.systemBackground))

            ScribbleCanvasView(drawing: store.scribble)

            ForEach(store.elements) { element in
                ElementContainerView(store: store, element: element)
                    .offset(x: element.position.x, y: element.position.y)
            }

            if store.drawMode {
                DrawInputLayer(store: store, elementFrames: hitTargets)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .onTapGesture {
            store.select(nil)
        }
    }

    /// Current frames of all elements in canvas coordinates — what Draw
    /// mode's input surface hit-tests against. Driven purely by
    /// `element.position`, so it always matches what's on screen.
    private var hitTargets: [(id: UUID, frame: CGRect)] {
        store.elements.map { ($0.id, $0.frame) }
    }
}