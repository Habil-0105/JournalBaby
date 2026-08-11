import SwiftUI
import PencilKit

/// Renders a single page: background, scribble layer, elements, and a
/// delete button at the top. The view owns the `"canvas"` coordinate space
/// so element gestures measure translation in the page's own (scaled)
/// coordinates. When `isCurrent` is true the scribble layer is an
/// interactive `PKCanvasView`; otherwise a static image.
struct PageContentView: View {
    @ObservedObject var store: CanvasStore
    let page: Page
    let pageIndex: Int
    let isCurrent: Bool
    let pageSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(Color(.systemBackground))

            scribbleLayer
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))

            ForEach(page.elements) { element in
                ElementContainerView(store: store, element: element)
                    .offset(x: element.position.x, y: element.position.y)
            }
            .allowsHitTesting(isCurrent && store.writingMode)

            if isCurrent && !store.writingMode {
                deleteButton
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .coordinateSpace(name: "canvas")
        .onTapGesture {
            if isCurrent && !store.drawMode {
                store.select(nil)
            }
        }
    }

    // MARK: - Scribble Layer

    @ViewBuilder
    private var scribbleLayer: some View {
        if isCurrent {
            ScribbleCanvasView(store: store)
        } else {
            staticScribbleImage
        }
    }

    private var staticScribbleImage: some View {
        Group {
            if let uiImage = staticScribbleUIImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
    }

    private var staticScribbleUIImage: UIImage? {
        let rect = CGRect(origin: .zero, size: pageSize)
        guard !page.scribble.dataRepresentation().isEmpty else { return nil }
        return page.scribble.image(from: rect, scale: UIScreen.main.scale)
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button {
            // Route through `requestDeletePage` so `PageCarouselView` can
            // play the exit + entry animation. The actual removal happens
            // once the carousel confirms the deletion.
            store.requestDeletePage(at: pageIndex)
        } label: {
            Text("Delete")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.85))
                .clipShape(Capsule())
        }
        .padding(12)
    }
}
