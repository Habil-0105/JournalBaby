import SwiftUI

/// An element on the freeform canvas. It renders at `element.position`
/// (the parent applies that offset), and its own frame is `element.width ×
/// element.height`.
///
/// Interactions:
/// - **tap** selects the block (shows handles); **double-tap** (text) starts
///   editing.
/// - **drag anywhere** moves the block — the gesture writes straight to
///   `store.moveElement`, i.e. to `element.position`, so the visual
///   position, the model position, and the hit-test position are always the
///   same value. Text is draggable whenever it isn't actively being edited,
///   so grabbing a text block never fights its caret.
/// - a **width handle** (right edge, all kinds) — drag to resize width.
/// - a **height handle** (bottom edge, image/audio) — text height is
///   automatic (measured content height).
/// - a delete button (top-right).
struct ElementContainerView: View {
    @ObservedObject var store: CanvasStore
    var element: CanvasElement

    @State private var widthDelta: CGFloat = 0
    @State private var heightDelta: CGFloat = 0
    /// The canvas position captured when the current move-drag started, so
    /// the live position is always `start + translation`.
    @State private var dragStartPosition: CGPoint?

    private var isSelected: Bool {
        store.selectedElementID == element.id
    }
    private var isText: Bool {
        element.kind == .text
    }
    private var isFocused: Bool {
        store.focusedTextID == element.id
    }

    private var liveWidth: CGFloat {
        min(max(element.width + widthDelta, DesignSystem.minBlockWidth), max(store.canvasSize.width, DesignSystem.minBlockWidth))
    }
    private var liveHeight: CGFloat {
        isText ? element.height : max(element.height + heightDelta, DesignSystem.minBlockHeight)
    }

    /// All kinds are always draggable except a text block that is actively
    /// being edited — while editing, caret/selection gestures must win.
    private var moveEnabled: Bool {
        !isText || !isFocused
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(Color(.secondarySystemBackground))
            content
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        }
        .frame(width: liveWidth, height: liveHeight)
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .onTapGesture {
            store.select(element.id)
        }
        .onTapGesture(count: 2) {
            if isText {
                store.focusText(element.id)
            }
        }
        .gesture(moveGesture, including: moveEnabled ? .gesture : .none)
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
                width: liveWidth,
                isFocused: isFocused
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

    // MARK: - Gestures

    /// Moves the block by writing to its real `position` on every drag
    /// change (clamped to the board), so the model is always the truth —
    /// nothing to re-commit on `onEnded`, nothing visual to reconcile.
    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                if dragStartPosition == nil {
                    dragStartPosition = element.position
                    if !isText {
                        store.select(element.id)
                    }
                }
                store.moveElement(
                    element.id,
                    to: CGPoint(
                        x: (dragStartPosition?.x ?? element.position.x) + value.translation.width,
                        y: (dragStartPosition?.y ?? element.position.y) + value.translation.height
                    )
                )
            }
            .onEnded { _ in
                dragStartPosition = nil
            }
    }

    private var widthGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                widthDelta = value.translation.width
            }
            .onEnded { value in
                store.setWidth(element.id, to: element.width + value.translation.width)
                widthDelta = 0
            }
    }

    private var heightGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                heightDelta = value.translation.height
            }
            .onEnded { value in
                store.setHeight(element.id, to: element.height + value.translation.height)
                heightDelta = 0
            }
    }
}