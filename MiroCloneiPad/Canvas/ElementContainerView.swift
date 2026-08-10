import SwiftUI

/// Wraps a block at its stored `(x, y)` page coordinate and routes the
/// gestures it owns.
///
/// Gesture model per kind:
///
/// - **Text** — `AutoGrowingTextView`'s internal `UITextView` is the
///   text-input surface. Taps and typing land in it directly through
///   UIKit's first-responder chain. The element has NO body tap
///   gesture of its own — instead, when the text view gains or loses
///   first-responder status, the delegate reports it back to the
///   store, so the selection ring follows the active text block
///   automatically. A drag with movement above the tap threshold
///   moves the block.
///
/// - **Image** — taps and drags on the image both work. A tap
///   selects; a drag moves. The image itself has no internal gestures
///   to fight with.
///
/// - **Audio** — taps on the play/pause button toggle playback. Taps
///   anywhere else on the block select it. A drag from anywhere on
///   the block (including from the button area when the drag starts
///   moving) moves the element. SwiftUI's hit-test routes the tap to
///   the inner `Button` because the button is a deeper view; once a
///   finger starts moving, the parent's drag wins.
///
/// (Drawing / scribble is NOT an element. Strokes belong to the page
/// itself and are handled by `PageView` + `ScribbleCanvasView` —
/// nothing on this view is aware of the Scribble tool.)
///
/// Resize handles (`widthHandle`, `heightHandle`) keep their own
/// `.gesture(...)` and never start a move.
struct ElementContainerView: View {
    @ObservedObject var store: CanvasStore
    var placed: PlacedElement
    var element: CanvasElement

    @State private var widthDelta: CGFloat = 0
    @State private var heightDelta: CGFloat = 0
    /// Live drag preview. Commits to `store.setPosition` on `.onEnded`.
    @State private var dragOffsetX: CGFloat = 0
    @State private var dragOffsetY: CGFloat = 0
    /// True while the block is being lifted (mid-drag).
    @State private var isLifted: Bool = false

    private var frame: CGRect {
        placed.frame
    }
    private var isSelected: Bool {
        store.selectedElementID == element.id
    }
    private var isText: Bool {
        element.kind == .text
    }

    private var liveWidth: CGFloat {
        max(frame.width + widthDelta, DesignSystem.minBlockWidth)
    }
    private var liveHeight: CGFloat {
        isText ? frame.height : max(frame.height + heightDelta, DesignSystem.minBlockHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(Color(.secondarySystemBackground))
            content
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        }
        .frame(width: liveWidth, height: liveHeight)
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .offset(x: dragOffsetX, y: dragOffsetY)
        .scaleEffect(isLifted ? 1.03 : 1.0)
        .shadow(color: isLifted ? Color.black.opacity(0.20) : .clear, radius: isLifted ? 12 : 0, y: isLifted ? 8 : 0)
        .animation(.easeInOut(duration: 0.15), value: isLifted)
        .modifier(BodyInteractionModifier(
            isText: isText,
            isLifted: $isLifted,
            dragOffsetX: $dragOffsetX,
            dragOffsetY: $dragOffsetY,
            onSelect: {
                if !isSelected { store.selectedElementID = element.id }
                store.bringToFront(element.id)
            },
            liveDragCommit: { dx, dy in
                store.setPosition(
                    element.id,
                    x: element.x + dx,
                    y: element.y + dy
                )
            }
        ))
        .overlay(alignment: .topTrailing) {
            if isSelected {
                deleteButton.offset(x: 10, y: -10)
            }
        }
        .overlay(alignment: .trailing) {
            if isSelected {
                widthHandle.offset(x: 4)
            }
        }
        .overlay(alignment: .bottom) {
            if isSelected && !isText {
                heightHandle.offset(y: 4)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch element.kind {
        case .text:
            TextElementView(
                store: store,
                element: element,
                placed: placed,
                width: liveWidth,
                slices: [placed.textSubstring ?? ""],
                onFocusChange: { focused in
                    // The text view itself is the source of truth for
                    // "is this element selected" — when it becomes
                    // first responder (user tapped into it) the
                    // element is the active one. When focus leaves,
                    // the user moved on.
                    if focused {
                        if !isSelected { store.selectedElementID = element.id }
                        store.bringToFront(element.id)
                    } else if store.selectedElementID == element.id {
                        // Don't clobber the user's selection if they
                        // moved focus to another text element in the
                        // same pass; the new first responder will set
                        // its own selection. We only clear when focus
                        // genuinely left (e.g., user tapped the page).
                        // The page-level tap-to-deselect handles that.
                    }
                }
            )
        case .image:
            ImageElementView(store: store, element: element)
        case .audio:
            AudioElementView(store: store, element: element)
        }
    }

    // MARK: - Handles

    private var widthHandle: some View {
        ZStack {
            Color.clear.frame(width: 32, height: 60) // generous hit target
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 6, height: 36)
                .overlay(Capsule().stroke(.white, lineWidth: 1))
        }
        .contentShape(Rectangle())
        .gesture(widthGesture)
    }

    private var heightHandle: some View {
        ZStack {
            Color.clear.frame(width: 60, height: 32) // generous hit target
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 36, height: 6)
                .overlay(Capsule().stroke(.white, lineWidth: 1))
        }
        .contentShape(Rectangle())
        .gesture(heightGesture)
    }

    private var deleteButton: some View {
        Button {
            store.remove(element.id)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
                .font(.title3)
        }
    }

    // MARK: - Gestures (resize)

    private var widthGesture: some Gesture {
        DragGesture(coordinateSpace: .named("page"))
            .onChanged { value in
                widthDelta = value.translation.width
            }
            .onEnded { value in
                store.setWidth(element.id, to: frame.width + value.translation.width)
                widthDelta = 0
            }
    }

    private var heightGesture: some Gesture {
        DragGesture(coordinateSpace: .named("page"))
            .onChanged { value in
                heightDelta = value.translation.height
            }
            .onEnded { value in
                store.setHeight(element.id, to: frame.height + value.translation.height)
                heightDelta = 0
            }
    }
}

// MARK: - Body interaction modifier

/// Composes the per-kind body gesture stack for Text / Image / Audio.
///
/// **No long-press.** Every element is draggable by a normal drag
/// gesture. A small `minimumDistance: 4` lets a pure tap (no movement)
/// fall through to the inner UIKit views (the text view, the audio
/// button) before the drag wins — that's how tapping the text view
/// focuses it and tapping the audio button plays/pauses without
/// accidentally moving the block.
///
/// - **Text**: only the drag is attached. Taps reach the underlying
///   `UITextView` directly via UIKit (it becomes first responder on
///   tap). The text view reports its focus state to the parent so the
///   selection ring tracks it.
/// - **Image / Audio**: a body tap selects; a drag moves. The audio
///   play button is a SwiftUI `Button` deeper in the tree, so taps
///   routed to its hit area reach the button (play/pause); taps
///   anywhere else on the block fire the body's select.
private struct BodyInteractionModifier: ViewModifier {
    let isText: Bool
    @Binding var isLifted: Bool
    @Binding var dragOffsetX: CGFloat
    @Binding var dragOffsetY: CGFloat
    let onSelect: () -> Void
    let liveDragCommit: (_ dx: CGFloat, _ dy: CGFloat) -> Void

    func body(content: Content) -> some View {
        if isText {
            // Text: no body tap — the inner `UITextView` handles taps
            // via UIKit and reports focus back to the parent. Only
            // the drag is attached, and only as a high-priority
            // gesture so once motion exceeds `minimumDistance: 4`
            // the text view's internal selection / cursor panning
            // gestures yield to element movement.
            return AnyView(content.highPriorityGesture(moveDragGesture))
        }
        // Image / Audio: tap selects; drag moves. The tap uses
        // `.gesture` (not simultaneous) so the page's tap-to-deselect
        // doesn't fire on element taps. Inner interactive controls
        // (the audio play button) still get their own taps because
        // SwiftUI hit-test routes to deeper views first.
        return AnyView(
            content
                .gesture(selectOnTapGesture)
                .highPriorityGesture(moveDragGesture)
        )
    }

    /// Drag with a small motion threshold. Below 4 points of movement
    /// the gesture never starts and the touch falls through to the
    /// inner UIKit view — that's how Text/Image/Audio taps still work
    /// without the parent intercepting them.
    private var moveDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("page"))
            .onChanged { value in
                if !isLifted { onSelect() }
                isLifted = true
                dragOffsetX = value.translation.width
                dragOffsetY = value.translation.height
            }
            .onEnded { value in
                liveDragCommit(value.translation.width, value.translation.height)
                dragOffsetX = 0
                dragOffsetY = 0
                isLifted = false
            }
    }

    /// Tap-only gesture for Image / Audio. Attached as `.gesture` so
    /// the page-level tap-to-deselect doesn't fire on element taps.
    private var selectOnTapGesture: some Gesture {
        TapGesture(count: 1)
            .onEnded {
                onSelect()
            }
    }
}
