import SwiftUI
import PencilKit

/// The page. Renders three layers, in z-order from bottom to top:
///
/// 1. **Page card** — the rounded-rect background, the page header
///    ("Page N of M"), and the dog-ear corner.
/// 2. **Page drawing layer** — strokes from the `Scribble` tool. When
///    `scribbleMode == true` this layer is an interactive
///    `PKCanvasView` that captures touches; otherwise it's an empty
///    space with no touch capture. Strokes are in page coordinates
///    because the canvas is sized to the page's drawable rect.
/// 3. **Element blocks** — Text / Image / Audio blocks at their stored
///    `(x, y)`, sorted by `zIndex`. These render ABOVE the strokes, so
///    a block placed on top of a scribbled area "covers" the strokes
///    visually. (Strokes are still part of the page underneath the
///    block; the block being on top doesn't delete them.)
///
/// The page-level tap (`.onTapGesture { selectedElementID = nil }`)
/// sits on the OUTER card. When the drawing canvas is interactive it
/// captures touches first, so this tap never fires while scribbling.
struct PageView: View {
    @ObservedObject var store: CanvasStore
    var pageLayout: PageLayout
    var pageWidth: CGFloat
    var pageHeight: CGFloat
    var totalPages: Int
    /// When true, the page-level PencilKit canvas is interactive and
    /// captures touches for drawing. When false, the canvas is a
    /// non-tap-through overlay and normal element gestures work.
    var scribbleMode: Bool

    /// Returns a `Binding<PKDrawing>` for the drawing on this page.
    /// Reads from `store.pageDrawings[pageIndex]` (default empty);
    /// writes propagate straight back to the store.
    private var drawingBinding: Binding<PKDrawing> {
        Binding(
            get: { store.drawing(forPage: pageLayout.pageIndex) },
            set: { store.setDrawing($0, forPage: pageLayout.pageIndex) }
        )
    }

    var body: some View {
        let cardWidth = max(pageWidth - DesignSystem.pagePadding * 2, 100)
        let cardHeight = max(pageHeight - DesignSystem.pagePadding * 2, 100)
        let drawableWidth = cardWidth - DesignSystem.pagePadding * 2
        let drawableHeight = cardHeight - DesignSystem.pageHeaderHeight - DesignSystem.pagePadding

        let canonicalElementsMap = Dictionary(uniqueKeysWithValues: store.elements.map { ($0.id, $0) })

        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Page \(pageLayout.pageIndex + 1) of \(totalPages)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))

                Spacer()
            }
            .padding(.horizontal, DesignSystem.pagePadding)
            .frame(height: DesignSystem.pageHeaderHeight)

            // Drawing surface area (everything below the header and
            // inside the page padding). The PencilKit canvas lives
            // here, in the page's coordinate system. The canvas is
            // sized to the SAME area that block `.offset` positions
            // land in — i.e., the ZStack's content area after its
            // padding is applied. That makes "page coordinates" for
            // strokes match the element `(x, y)` frame values: a
            // block at `(x=20, y=20)` and a stroke drawn at
            // canvas-local `(20, 20)` line up.
            ZStack(alignment: .topLeading) {
                // Layer 2: element blocks. When scribble mode is on
                // we disable hit-testing on them so the canvas above
                // captures every touch on the page — strokes land
                // freely over the elements, and dragging never
                // accidentally moves a block. When scribble mode is
                // off elements take all touches.
                let selectedID = store.selectedElementID
                let sorted = pageLayout.elements.sorted { lhs, rhs in
                    let lz = canonicalElementsMap[lhs.canonicalID]?.zIndex ?? 0
                    let rz = canonicalElementsMap[rhs.canonicalID]?.zIndex ?? 0
                    if lz != rz { return lz < rz }
                    return lhs.canonicalID.uuidString < rhs.canonicalID.uuidString
                }
                ForEach(sorted) { placed in
                    if let canonical = canonicalElementsMap[placed.canonicalID] {
                        ElementContainerView(
                            store: store,
                            placed: placed,
                            element: canonical
                        )
                        .offset(x: placed.frame.minX, y: placed.frame.minY)
                        .zIndex(canonical.id == selectedID ? .greatestFiniteMagnitude : Double(canonical.zIndex))
                        .allowsHitTesting(!scribbleMode)
                    }
                }

                // Layer 3: page drawing layer. Rendered LAST so it
                // sits on top of the elements whenever it's
                // mounted. While `scribbleMode == true` the canvas
                // is interactive and captures touches (drawing).
                // While off, its `isUserInteractionEnabled` is
                // false so it's transparent to gestures and the
                // elements below receive touches normally.
                pageDrawingCanvas
                    .frame(width: drawableWidth, height: drawableHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, DesignSystem.pagePadding)
            .padding(.bottom, DesignSystem.pagePadding)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: DesignSystem.pageShadowRadius, x: 0, y: DesignSystem.pageShadowY)
        )
        .overlay(alignment: .bottomTrailing) {
            if pageLayout.pageIndex < totalPages - 1 {
                DogEarCornerView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .coordinateSpace(name: "page")
        .contentShape(Rectangle())
        // Deselect by tapping the page's empty area. While scribble
        // mode is on the PencilKit canvas above absorbs the touch and
        // this never fires; while off it's how the user clears the
        // selection ring.
        .onTapGesture {
            if !scribbleMode {
                store.selectedElementID = nil
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pageLayout)
    }

    /// The page-level drawing canvas. Always mounted (so it can show
    /// existing strokes); only interactive when scribble mode is on.
    /// Strokes drawn here live in the canvas's local coordinate
    /// system, which equals the page's coordinate system because the
    /// canvas is positioned at the page's top-left and sized to its
    /// drawable rect.
    private var pageDrawingCanvas: some View {
        ScribbleCanvasView(
            drawing: drawingBinding,
            isActive: scribbleMode
        )
    }
}

/// Visual dog-ear corner curl hint displayed on the bottom-right of a page.
struct DogEarCornerView: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: size, y: 0))
                path.addLine(to: CGPoint(x: size, y: size))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color.black.opacity(0.22), Color.black.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            Path { path in
                path.move(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: size, y: 0))
                path.addLine(to: CGPoint(x: size, y: size))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color(.systemGroupedBackground), Color(.secondarySystemBackground)],
                    startPoint: .bottomTrailing,
                    endPoint: .topLeading
                )
            )
            .overlay(
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size))
                    path.addLine(to: CGPoint(x: size, y: 0))
                }
                .stroke(Color.primary.opacity(0.2), lineWidth: 1.5)
            )
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}
