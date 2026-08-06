import SwiftUI

/// Wraps a block at the frame `PageView` computed for it via
/// `CanvasStore.layout()`. There's no move handle anymore — position is
/// always derived from order + size, never chosen by dragging. What's
/// left:
///
/// - tap-to-select (shows the handles below and, for text/drawing,
///   switches that block into its interactive editing state)
/// - a **width handle** (right edge, all kinds) — drag to resize width;
///   this is what triggers reflow of every block after it.
/// - a **height handle** (bottom edge, all kinds except text) — text has
///   no height handle because its height is automatic.
/// - a delete button (top-right).
struct ElementContainerView: View {
    @ObservedObject var store: CanvasStore
    var placed: PlacedElement
    var element: CanvasElement
    var slices: [String]

    @State private var widthDelta: CGFloat = 0
    @State private var heightDelta: CGFloat = 0

    private var frame: CGRect {
        placed.frame
    }
    private var isSelected: Bool {
        store.selectedElementID == element.id
    }
    private var isText: Bool {
        element.kind == .text
    }
    private var isDrawing: Bool {
        element.kind == .drawing
    }

    private var liveWidth: CGFloat {
        min(max(frame.width + widthDelta, DesignSystem.minBlockWidth), store.containerWidth)
    }
    private var liveHeight: CGFloat {
        isText ? frame.height : max(frame.height + heightDelta, DesignSystem.minBlockHeight)
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
            store.selectedElementID = element.id
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                deleteButton.offset(x: 10, y: -10)
            }
        }
        .overlay(alignment: .trailing) {
            if isSelected && !isDrawing {
                widthHandle.offset(x: 4)
            }
        }
        .overlay(alignment: .bottom) {
            if isSelected && !isText && !isDrawing {
                heightHandle.offset(y: 4)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isSelected && isDrawing {
                cornerScaleHandle.offset(x: 4, y: 4)
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
                isActive: isSelected,
                slices: slices
            )
        case .image:
            ImageElementView(store: store, element: element)
        case .audio:
            AudioElementView(store: store, element: element)
        case .drawing:
            DrawingElementView(store: store, element: element, isActive: isSelected)
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

    private var cornerScaleHandle: some View {
        ZStack {
            Color.clear.frame(width: 44, height: 44) // generous hit target
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(7)
                .background(Circle().fill(Color.accentColor))
                .overlay(Circle().stroke(.white, lineWidth: 1))
        }
        .contentShape(Rectangle())
        .gesture(cornerScaleGesture)
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

    /// Drives width and height together from a single drag (horizontal
    /// distance sets the scale factor, applied to both dimensions), so
    /// the block's aspect ratio never changes. Reuses the same
    /// `widthDelta`/`heightDelta` state the edge handles use — only how
    /// they're computed differs — so `liveWidth`/`liveHeight` need no
    /// special-casing for the live preview.
    private var cornerScaleGesture: some Gesture {
        DragGesture(coordinateSpace: .named("page"))
            .onChanged { value in
                let scale = scaleFactor(for: value.translation.width)
                widthDelta = frame.width * (scale - 1)
                heightDelta = frame.height * (scale - 1)
            }
            .onEnded { value in
                let scale = scaleFactor(for: value.translation.width)
                let targetSize = CGSize(width: frame.width * scale, height: frame.height * scale)

                // setWidth/setHeight clamp to min/max bounds — read back
                // the ACTUAL applied size before scaling the drawing's
                // strokes, so its content size tracking never drifts
                // from what's really stored.
                let finalWidth = store.setWidth(element.id, to: targetSize.width)
                let finalHeight = store.setHeight(element.id, to: targetSize.height)
                store.scaleDrawing(element.id, to: CGSize(width: finalWidth, height: finalHeight))

                widthDelta = 0
                heightDelta = 0
            }
    }

    private func scaleFactor(for horizontalTranslation: CGFloat) -> CGFloat {
        guard frame.width > 0 else { return 1 }
        let minScale = DesignSystem.minBlockWidth / frame.width
        return max((frame.width + horizontalTranslation) / frame.width, minScale)
    }
}
