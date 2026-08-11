import SwiftUI
import PencilKit
import UIKit

/// The writing-mode canvas: a single, large, centered rendering of the
/// current page. Carousel neighbours are completely hidden (no PageStripView
/// in this mode). The page is sized to ~85% of the container's width and
/// ~75% of its height at the paper aspect ratio, leaving generous margins
/// on all sides so the page reads as a *writing surface*, not a full-screen
/// takeover.
///
/// The view also installs a `MagnifyGesture` for pinch-out to exit
/// writing mode (returning to the carousel). Pinching fingers together
/// (zoom out) is the only path back from writing mode in this iteration.
///
/// When the keyboard appears the paper does **not** shrink: the surface
/// ignores the keyboard safe area, so the paper keeps its original size
/// and the content coordinates never change. Instead the paper is panned
/// up by just enough to keep the actively-edited text element visible
/// above the keyboard.
struct WritingCanvasView: View {
    @ObservedObject var store: CanvasStore

    /// How far the paper is shifted up while the keyboard is visible, in
    /// container points. 0 when no keyboard (paper is centered normally).
    @State private var keyboardHeight: CGFloat = 0

    /// Pinch magnification that flips the user back to carousel mode. A
    /// value **below** 1 means fingers are pinching together — the natural
    /// "zoom out" gesture that pulls the user out of the writing canvas
    /// and back to the carousel preview. Tuned conservatively so casual
    /// touch jitter doesn't accidentally exit.
    private let exitPinchThreshold: CGFloat = 0.7

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
                    .offset(y: -viewportOffset)
                    .animation(.easeOut(duration: 0.25), value: keyboardHeight)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            // Tapping any empty space around the paper dismisses an active
            // text edit (and deselection). Taps that land on the paper /
            // elements are handled by their own gestures and take precedence,
            // so this only fires for the surrounding canvas background.
            .onTapGesture {
                store.select(nil)
            }
            .gesture(pinchOutToExit)
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

    /// Vertical shift (paper moves up by this much) needed to keep the
    /// focused text element above the keyboard. Zero when the keyboard is
    /// hidden or the focused element is already clear of it.
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

    private var pinchOutToExit: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                guard value.magnification < exitPinchThreshold else { return }
                // Only exit on a definitive pinch (fingers closing together);
                // bouncing back inside the threshold shouldn't cancel an
                // exit mid-gesture.
                store.exitWritingMode()
            }
    }
}
