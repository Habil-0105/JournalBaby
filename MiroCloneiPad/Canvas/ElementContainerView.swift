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
    var element: CanvasElement
    /// The frame `CanvasStore.layout()` assigned this block for the
    /// current render pass.
    var frame: CGRect

    @State private var widthDelta: CGFloat = 0
    @State private var heightDelta: CGFloat = 0

    private var isSelected: Bool {
        store.selectedElementID == element.id
    }
    private var isText: Bool {
        element.kind == .text
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
            TextElementView(store: store, element: element, width: liveWidth, isActive: isSelected)
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
}
