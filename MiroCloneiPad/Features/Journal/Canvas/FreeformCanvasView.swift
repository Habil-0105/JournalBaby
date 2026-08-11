import SwiftUI

/// The single freeform canvas. There is no paging, no flow layout, and no
/// derived positioning: each element is rendered at its own
/// `element.position`, hit-tested there, and moved directly by the drag
/// gesture writing back to that same `position`.
///
/// Layer order (bottom → top):
/// 1. the board surface
/// 2. committed scribble strokes (PencilKit, interactive only in Draw mode)
/// 3. the freeform elements
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

            ScribbleCanvasView(store: store)

            ForEach(store.elements) { element in
                ElementContainerView(store: store, element: element)
                    .offset(x: element.position.x, y: element.position.y)
            }
            .allowsHitTesting(!store.drawMode)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .onTapGesture {
            if !store.drawMode {
                store.select(nil)
            }
        }
    }
}
