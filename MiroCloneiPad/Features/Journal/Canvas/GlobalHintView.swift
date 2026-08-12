import SwiftUI

/// The journal's global hint overlay. This is a journal-level note, not a
/// per-page canvas element: it renders inside the current page's
/// `PageContentView` but reads and writes store-level (`CanvasStore`) state,
/// so every page shows the same hint at the same position.
///
/// Interaction rules mirror the existing element gate:
/// - Writing mode + drawing OFF → the hint is draggable and its refresh
///   button is tappable.
/// - Carousel mode, or writing mode with drawing armed → the hint renders
///   but is inert, so it never steals a carousel swipe, a pinch, or a
///   PencilKit stroke.
/// - Tapping the hint never starts text editing; it only dismisses the
///   current selection / body focus (same "tap outside" semantics as the
///   empty paper).
struct GlobalHintView: View {
    @ObservedObject var store: CanvasStore

    /// Canvas position captured when the current move-drag started, so the
    /// live position is always `start + translation` (same pattern as
    /// `ElementContainerView.moveGesture`).
    @State private var dragStartPosition: CGPoint?

    /// Live preview offsets for the resize handles. The size is previewed
    /// against these local deltas and committed once on `onEnded` (the same
    /// deliberate exception as `ElementContainerView`'s width/height
    /// handles).
    @State private var widthDelta: CGFloat = 0
    @State private var heightDelta: CGFloat = 0

    /// Whether the hint is interactive. Mirrors the elements gate
    /// (`isCurrent && store.writingMode && !store.drawMode`); this view is
    /// only ever mounted for the current page, so `isCurrent` is implied.
    private var interactive: Bool {
        store.writingMode && !store.drawMode
    }

    /// The card's on-screen size during a resize: the stored size plus the
    /// live handle delta, clamped to `GlobalHint`'s min/max.
    private var liveSize: CGSize {
        CGSize(
            width: min(max(store.hintSize.width + widthDelta, GlobalHint.minSize.width), GlobalHint.maxSize.width),
            height: min(max(store.hintSize.height + heightDelta, GlobalHint.minSize.height), GlobalHint.maxSize.height)
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            noteCard
            refreshButton
                .offset(
                    x: GlobalHint.buttonOverhang.width,
                    y: -GlobalHint.buttonOverhang.height
                )
        }
        .frame(width: liveSize.width, height: liveSize.height)
        .rotationEffect(.degrees(-1.5))
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        // Consume taps so a tap on the note never reaches the paper's tap
        // gesture (which would start the body editor). Deselect like a tap
        // on empty paper.
        .onTapGesture {
            store.select(nil)
        }
        .gesture(moveGesture, including: interactive ? .gesture : .none)
        .overlay(alignment: .trailing) {
            if interactive {
                widthHandle.offset(x: 4)
            }
        }
        .overlay(alignment: .bottom) {
            if interactive {
                heightHandle.offset(y: 4)
            }
        }
        .allowsHitTesting(interactive)
    }

    // MARK: - Note card

    private var noteCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(Color(red: 1.0, green: 0.97, blue: 0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                        .stroke(Color(red: 0.62, green: 0.48, blue: 0.22).opacity(0.3), lineWidth: 1)
                )

            Text(store.hintText)
                .font(.system(size: 15, weight: .medium, design: .serif).italic())
                .foregroundStyle(Color(red: 0.35, green: 0.28, blue: 0.15))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 3)
    }

    // MARK: - Refresh button

    /// A plain tappable (not a SwiftUI `Button`). Buttons use a UIKit-backed
    /// tap recognizer that doesn't participate in SwiftUI's exclusive
    /// gesture precedence, so a tap on a `Button` also fell through to the
    /// paper's `.onTapGesture` — which in writing mode starts the body
    /// editor. A child `.onTapGesture` wins exclusively over the ancestors',
    /// so the refresh tap never reaches the paper (same pattern as
    /// `ElementContainerView`).
    private var refreshButton: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 30, height: 30)
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .contentShape(Circle())
        .onTapGesture {
            store.refreshHint()
        }
        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
        .accessibilityLabel("New hint")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Resize handles

    /// Right-edge handle — drag to resize the card's width. Same styling
    /// and generous hit target as `ElementContainerView`'s width handle.
    private var widthHandle: some View {
        ZStack {
            Color.clear.frame(width: 32, height: 60)
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 6, height: 36)
                .overlay(Capsule().stroke(.white, lineWidth: 1))
        }
        .contentShape(Rectangle())
        .gesture(widthGesture)
    }

    /// Bottom-edge handle — drag to resize the card's height.
    private var heightHandle: some View {
        ZStack {
            Color.clear.frame(width: 60, height: 32)
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 36, height: 6)
                .overlay(Capsule().stroke(.white, lineWidth: 1))
        }
        .contentShape(Rectangle())
        .gesture(heightGesture)
    }

    /// Resizes the hint's width. Preview against a local delta (so the card
    /// grows while dragging), then commit the stored size once on `onEnded` —
    /// the existing element resize-handle pattern.
    private var widthGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                widthDelta = value.translation.width
            }
            .onEnded { value in
                store.setHintSize(CGSize(
                    width: store.hintSize.width + value.translation.width,
                    height: store.hintSize.height + heightDelta
                ))
                widthDelta = 0
                heightDelta = 0
            }
    }

    private var heightGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                heightDelta = value.translation.height
            }
            .onEnded { value in
                store.setHintSize(CGSize(
                    width: store.hintSize.width + widthDelta,
                    height: store.hintSize.height + value.translation.height
                ))
                widthDelta = 0
                heightDelta = 0
            }
    }

    // MARK: - Drag

    /// Moves the hint by writing to the store's global `hintPosition` on
    /// every drag change (clamped to the paper by `CanvasStore.moveHint`),
    /// so the model is always the truth — nothing to re-commit on `onEnded`.
    /// Reads translation in the page's `"canvas"` coordinate space, the same
    /// normalization elements use, so zoom levels never drift the position.
    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                if dragStartPosition == nil {
                    dragStartPosition = store.hintPosition
                }
                store.moveHint(
                    to: CGPoint(
                        x: (dragStartPosition?.x ?? store.hintPosition.x) + value.translation.width,
                        y: (dragStartPosition?.y ?? store.hintPosition.y) + value.translation.height
                    )
                )
            }
            .onEnded { _ in
                dragStartPosition = nil
            }
    }
}