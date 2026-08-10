import SwiftUI

/// The single freeform canvas. There is no paging, no flow layout, and no
/// derived positioning: each element is rendered at its own
/// `element.position`, hit-tested there, and moved directly by the drag
/// gesture writing back to that same `position`.
///
/// Zoom is a pure rendering-level transform (`scaleEffect` + `offset`)
/// applied to `board`, one level *inside* the "canvas" named coordinate
/// space declared below. Because of that, every gesture inside `board`
/// that reads `.coordinateSpace(.named("canvas"))` — element drag, width/
/// height handles, PencilKit touch input — automatically receives
/// already-descaled, already-depanned coordinates from SwiftUI. Nothing
/// downstream needs to know zoom exists.
///
/// Layer order (bottom → top):
/// 1. the board surface
/// 2. committed scribble strokes (PencilKit, interactive only in Draw mode)
/// 3. the freeform elements
struct FreeformCanvasView: View {
    @ObservedObject var store: CanvasStore
    var size: CGSize

    /// Captured once per pinch gesture (nil between gestures) so every
    /// `onChanged` frame computes the new scale/offset relative to a
    /// stable starting point rather than compounding frame-over-frame.
    @State private var pinchStartScale: CGFloat?
    @State private var pinchStartOffset: CGSize?
    @State private var pinchAnchor: CGPoint?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.systemGroupedBackground)
            board
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: "canvas")
        // Pinch is attached OUTSIDE the scaled content, so `value.startLocation`
        // is reported in the stable, unscaled frame that `zoomOffset` also
        // operates in — not warped by the very transform it's driving.
        .simultaneousGesture(pinchGesture)
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
        // Anchor .topLeading keeps this consistent with the offset math below
        // (both treat the board's top-left as the coordinate origin).
        .scaleEffect(store.zoomScale, anchor: .topLeading)
        .offset(x: store.zoomOffset.width, y: store.zoomOffset.height)
    }

    // MARK: - Pinch to zoom

    /// Classic focal-point-preserving pinch math: given the point under the
    /// fingers (`anchor`) and how scale changes relative to gesture start,
    /// solve for the offset that keeps `anchor` visually fixed.
    ///
    /// displayedPoint = contentPoint * scale + offset
    /// ⇒ contentPoint = (anchor - startOffset) / startScale
    /// ⇒ newOffset    = anchor - contentPoint * newScale
    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                if pinchStartScale == nil {
                    pinchStartScale = store.zoomScale
                    pinchStartOffset = store.zoomOffset
                    pinchAnchor = value.startLocation
                }
                guard let startScale = pinchStartScale,
                      let startOffset = pinchStartOffset,
                      let anchor = pinchAnchor else { return }

                let newScale = CanvasStore.clampZoom(startScale * value.magnification)
                let contentPoint = CGPoint(
                    x: (anchor.x - startOffset.width) / startScale,
                    y: (anchor.y - startOffset.height) / startScale
                )
                store.zoomScale = newScale
                store.zoomOffset = CGSize(
                    width: anchor.x - contentPoint.x * newScale,
                    height: anchor.y - contentPoint.y * newScale
                )
            }
            .onEnded { _ in
                pinchStartScale = nil
                pinchStartOffset = nil
                pinchAnchor = nil
            }
    }
}
