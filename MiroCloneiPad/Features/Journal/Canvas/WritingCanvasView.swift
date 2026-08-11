import SwiftUI
import PencilKit
import UIKit

/// The writing-mode canvas: a single, large, centered rendering of the
/// current page. Carousel neighbours are completely hidden.
///
/// Supports canvas zooming via pinch gestures within [1.0x, 3.0x].
/// Zooming out to or below the minimum zoom level (1.0x) automatically
/// transitions the user back to Carousel Mode. The zoom gesture correctly
/// tracks the user's focal point, ensuring the canvas scales around their fingers.
struct WritingCanvasView: View {
    @ObservedObject var store: CanvasStore

    /// How far the paper is shifted up while the keyboard is visible.
    @State private var keyboardHeight: CGFloat = 0

    /// Persistent zoom and pan states for Writing Mode.
    @State private var scale: CGFloat = DesignSystem.minWritingCanvasScale
    @State private var lastScale: CGFloat = DesignSystem.minWritingCanvasScale
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    /// Minimum clearance kept between the focused text element's bottom
    /// and the top of the keyboard while the paper is panned.
    private let keyboardMargin: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let pageSize = DesignSystem.writingCanvasSize(for: geo.size)
            let viewportOffset = keyboardViewportOffset(
                container: geo.size,
                pageSize: pageSize
            )

            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if store.pages.indices.contains(store.currentPageIndex) {
                    PageContentView(
                        store: store,
                        page: store.pages[store.currentPageIndex],
                        pageIndex: store.currentPageIndex,
                        isCurrent: true,
                        pageSize: pageSize
                    )
                    .frame(width: pageSize.width, height: pageSize.height)
                    // Apply scale and spatial tracking for the pinch-to-zoom
                    .scaleEffect(scale)
                    .offset(offset)
                    // Apply standard keyboard avoidance independent of the zoom offset
                    .offset(y: -viewportOffset)
                    .animation(.easeOut(duration: 0.25), value: keyboardHeight)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                store.select(nil)
            }
            // Pass the screen geometry into the gesture to calculate the correct focal center
            .gesture(zoomGesture(in: geo.size))
            .onAppear { store.updateCanvasSize(pageSize) }
            .onChange(of: pageSize) { _, newSize in
                store.updateCanvasSize(newSize)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification
            )
        ) { note in
            guard
                let rect = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                    as? CGRect
            else { return }
            keyboardHeight = rect.height
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification
            )
        ) { _ in
            keyboardHeight = 0
        }
    }

    private func keyboardViewportOffset(container: CGSize, pageSize: CGSize) -> CGFloat {
        guard keyboardHeight > 0, let focusedID = store.focusedTextID,
              let element = store.elements.first(where: { $0.id == focusedID })
        else { return 0 }

        let canvasOriginY = (container.height - pageSize.height) / 2
        let elementBottom = canvasOriginY + element.position.y + element.height
        let keyboardTop = container.height - keyboardHeight
        let needed = elementBottom + keyboardMargin - keyboardTop
        return max(needed, 0)
    }

    /// Zoom gesture handling: allows pinching to zoom in/out with accurate finger tracking.
    /// Pinching out to or below minWritingCanvasScale auto-exits Writing Mode.
    private func zoomGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                let newScale = lastScale * value.magnification

                if newScale <= DesignSystem.minWritingCanvasScale {
                    // Reached minimum zoom level -> reset states and auto-exit
                    scale = DesignSystem.minWritingCanvasScale
                    offset = .zero
                    store.exitWritingMode()
                } else {
                    // Clamp scale within the defined threshold bounds
                    let clampedScale = min(newScale, DesignSystem.maxWritingCanvasScale)
                    
                    // Ratio of visual expansion in this specific gesture update
                    let scaleDelta = clampedScale / lastScale

                    // 1. Establish the view's center point
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    
                    // 2. Vector distance from the center of the view to the pinch location
                    let pinchOffsetFromCenter = CGSize(
                        width: value.startLocation.x - center.x,
                        height: value.startLocation.y - center.y
                    )

                    // 3. Shift the canvas opposite to the expansion to keep the location pinned
                    scale = clampedScale
                    offset = CGSize(
                        width: pinchOffsetFromCenter.width - (pinchOffsetFromCenter.width - lastOffset.width) * scaleDelta,
                        height: pinchOffsetFromCenter.height - (pinchOffsetFromCenter.height - lastOffset.height) * scaleDelta
                    )
                }
            }
            .onEnded { _ in
                // Persist the transformation states only if we remain in Writing Mode
                if scale > DesignSystem.minWritingCanvasScale {
                    lastScale = scale
                    lastOffset = offset
                } else {
                    lastScale = DesignSystem.minWritingCanvasScale
                    lastOffset = .zero
                }
            }
    }
}
