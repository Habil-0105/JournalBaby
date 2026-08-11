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

            dateLabel

            if isCurrent {
                bodyTextLayer
            }

            ForEach(page.elements) { element in
                ElementContainerView(store: store, element: element)
                    .offset(x: element.position.x, y: element.position.y)
            }
            // Elements are interactive only in writing mode with drawing
            // OFF. While Scribble is armed the layer above the PKCanvasView
            // must be inert, otherwise touches over an element would drag /
            // resize it instead of painting a stroke over it.
            .allowsHitTesting(isCurrent && store.writingMode && !store.drawMode)

            // One-shot visual feedback when the body editor rejects an
            // edit because it would overflow the paper. Sits on top of
            // the body and elements, but under the delete button so the
            // delete affordance stays tappable.
            Rectangle()
                .fill(Color.red.opacity(0.22))
                .opacity(bodyOverflowFlashOpacity)
                .allowsHitTesting(false)

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

    // MARK: - Date label

    /// The page's creation date printed at the top-center of the paper,
    /// "dd MMMM yyyy" (e.g. "11 August 2026"). Rendered on every paper —
    /// current page and carousel neighbors — and scales with the page
    /// content. Non-hit-testable so it never intercepts touches.
    private var dateLabel: some View {
        Text(page.createdAt.formatted(.dateTime.day(.twoDigits).month(.wide).year()))
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .allowsHitTesting(false)
    }

    // MARK: - Body text editor

    /// The page's full-body text editor. Sits between the scribble layer
    /// (below) and the floating elements (above), so:
    /// - element drag/resize wins over the body (elements are on top)
    /// - PencilKit draws on top of the text (the PKCanvasView paints after
    ///   this layer but is below the elements)
    /// Same `allowsHitTesting` rule as the elements layer: in carousel
    /// mode the body is non-interactive; in writing mode with Draw off,
    /// the body is editable; in writing mode with Draw on, touches fall
    /// through to the PKCanvasView underneath.
    private var bodyTextLayer: some View {
        let inset = DesignSystem.bodyTextHorizontalMargin
        let top = DesignSystem.bodyTextTopMargin
        let bottom = DesignSystem.bodyTextBottomMargin
        let width = max(pageSize.width - inset * 2, 1)
        let height = max(pageSize.height - top - bottom, 1)
        let isEditing = isCurrent && store.writingMode && !store.drawMode

        let binding = Binding<String>(
            get: { store.bodyText },
            set: { store.updateBodyText($0) }
        )

        return AutoGrowingTextView(
            text: binding,
            isEditable: isEditing,
            width: width,
            // Don't grab the keyboard when writing mode opens — the user
            // should only enter the body editor by tapping it. (Floating
            // text elements keep their default of `true` so a freshly
            // added text block still focuses immediately.)
            becomesFirstResponderOnEdit: false,
            onHeightChange: { _ in
                // The body view fills its frame unconditionally — we don't
                // currently grow the page. The callback is here so the
                // same primitive used by floating text elements drives
                // the body, keeping behavior consistent if/when we add
                // page-growth or auto-scroll.
            },
            onFocusDidBegin: { store.setBodyFocused(true) },
            onFocusDidEnd: { store.setBodyFocused(false) },
            onCaretRectChange: { localRect in
                // The callback is in the text view's own coordinate
                // space; translate by the top/left padding applied
                // above so the canvas can place it in page space.
                let pageRect = localRect.offsetBy(dx: inset, dy: top)
                store.setBodyCaretRect(pageRect)
            },
            // Hard cap: the writable area of the page. Once the
            // measured text height would exceed this, the wrapper
            // rejects new edits (with a haptic) so the content
            // stays inside the paper instead of overflowing and
            // being clipped.
            maxHeight: height,
            onOverflowReject: {
                bodyOverflowFlashToken &+= 1
                bodyOverflowFlashOpacity = 0.55
                withAnimation(.easeOut(duration: 0.22)) {
                    bodyOverflowFlashOpacity = 0
                }
            }
        )
        .frame(width: width, height: height, alignment: .topLeading)
        .padding(.horizontal, inset)
        .padding(.top, top)
        .padding(.bottom, bottom)
        .overlay(alignment: .topLeading) {
            if page.bodyText.isEmpty {
                Text("Start writing…")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, inset)
                    .padding(.top, top)
                    .allowsHitTesting(false)
            }
        }
        // Same gate as the elements layer. The body is the "main writing
        // surface"; elements and PencilKit are the same kind of first-class
        // citizens as before, this just adds a third interactive layer
        // that obeys the same rule.
        .allowsHitTesting(isEditing)
    }

    // MARK: - Delete Button

    /// Whether the delete confirmation dialog is showing (writing mode only —
    /// the carousel deletes via its animated `requestDeletePage` flow instead).
    @State private var showDeleteConfirmation = false

    /// Bumped every time the body editor rejects a text edit because it
    /// would overflow the paper. Drives the one-shot red flash overlay
    /// below so the user gets clear feedback that "this keystroke didn't
    /// take" instead of silently failing.
    @State private var bodyOverflowFlashToken: Int = 0
    @State private var bodyOverflowFlashOpacity: Double = 0

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
