import SwiftUI

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

            // Sits below the elements. Non-interactive while Draw mode is
            // off (elements handle their own taps/drags on top of it);
            // becomes the sole touch target once Draw mode turns on,
            // because the elements layer below stops hit-testing.
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
