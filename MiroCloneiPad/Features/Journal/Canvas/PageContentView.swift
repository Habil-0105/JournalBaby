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

    /// Uniform scale applied to this content by its host (the carousel
    /// renders the canonical writing-sized content scaled down to a deck
    /// slot). Defaults to 1 (writing mode renders 1:1). The delete pill is
    /// counter-scaled by `1/contentScale` so it stays readable inside a
    /// downscaled paper.
    var contentScale: CGFloat = 1

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

            if isCurrent {
                deleteButton
                    .scaleEffect(1 / max(contentScale, 0.001))
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .coordinateSpace(name: "canvas")
        .onTapGesture {
            if !isCurrent {
                // Tapping a neighboring page paper navigates to it, the
                // same as tapping the Add Page card. Only applies in
                // carousel mode — writing mode never renders neighbors.
                store.switchToPage(at: pageIndex)
            } else if !store.drawMode {
                store.select(nil)
            }
        }
        .alert("Delete this page?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if store.writingMode {
                    // No carousel to play the exit + entry animation here, so
                    // remove directly, then leave writing mode: the deleted
                    // page's index is already fixed up by `removePage`, and
                    // `exitWritingMode` swaps back to the carousel and clears
                    // any lingering selection/focus/draw state.
                    store.removePage(at: pageIndex)
                    store.exitWritingMode()
                } else {
                    // Route through `requestDeletePage` so `PageCarouselView`
                    // can play the exit + entry animation. The actual removal
                    // happens once the carousel confirms the deletion.
                    store.requestDeletePage(at: pageIndex)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the current page and everything on it.")
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

    /// Whether the delete confirmation dialog is showing (writing mode only —
    /// the carousel deletes via its animated `requestDeletePage` flow instead).
    @State private var showDeleteConfirmation = false

    private var deleteButton: some View {
        Button {
            // Always confirm before deleting. In writing mode there's no
            // carousel to animate the exit, so the dialog is the only guard;
            // in carousel mode the dialog precedes the animated delete.
            showDeleteConfirmation = true
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
