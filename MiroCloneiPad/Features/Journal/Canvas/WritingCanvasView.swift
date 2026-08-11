import SwiftUI
import PencilKit

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
struct WritingCanvasView: View {
    @ObservedObject var store: CanvasStore

    /// Fraction of container width the writing page aims for.
    private let pageWidthFraction: CGFloat = 0.85
    /// Fraction of container height the writing page aims for.
    private let maxPageHeightFraction: CGFloat = 0.75
    /// Height-to-width ratio of a page (tall sheet of paper). Kept in
    /// sync with the carousel's `pageAspectRatio` so pages have the same
    /// shape at both sizes.
    private let pageAspectRatio: CGFloat = 1.3

    /// Pinch magnification that flips the user back to carousel mode. A
    /// value **below** 1 means fingers are pinching together — the natural
    /// "zoom out" gesture that pulls the user out of the writing canvas
    /// and back to the carousel preview. Tuned conservatively so casual
    /// touch jitter doesn't accidentally exit.
    private let exitPinchThreshold: CGFloat = 0.7

    var body: some View {
        GeometryReader { geo in
            let pageSize = writingPageSize(for: geo.size)

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
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(pinchOutToExit)
            .onAppear { store.updateCanvasSize(pageSize) }
            .onChange(of: pageSize) { _, newSize in
                store.updateCanvasSize(newSize)
            }
        }
    }

    /// The writing-mode page size: significantly larger than the carousel
    /// size (which uses `0.45 × W`), still with margins on every side so
    /// the page doesn't fill the screen edge-to-edge.
    private func writingPageSize(for container: CGSize) -> CGSize {
        let widthFromRatio = container.width * pageWidthFraction
        let widthFromHeight = container.height * maxPageHeightFraction / pageAspectRatio
        let width = min(widthFromRatio, widthFromHeight)
        return CGSize(width: width, height: width * pageAspectRatio)
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
