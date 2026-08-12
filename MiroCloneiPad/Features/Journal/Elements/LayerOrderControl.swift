import SwiftUI

/// Toolbar entry point for reordering the current page's layers. Only
/// meaningful — and only shown — in writing mode, since that's the only
/// place a page's layering is visible or interactive at all (carousel
/// neighbours are non-interactive previews).
///
/// Disabled (not just hidden) while the body editor or a floating text
/// element is focused: reordering mid-edit would yank the keyboard's
/// surface out from under an active edit, so the button requires the
/// user to back out of text editing first. This mirrors how `select(nil)`
/// already ends body/text focus elsewhere in the app — dismissing focus
/// first is the existing pattern, not a new one.
struct LayerOrderToolbarButton: View {
    @ObservedObject var store: CanvasStore
    @State private var isPresented = false

    private var isEditingText: Bool {
        store.bodyFocused || store.focusedTextID != nil
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Layer Order", systemImage: "square.3.layers.3d")
        }
        .disabled(isEditingText)
        .popover(isPresented: $isPresented) {
            LayerOrderPopoverView(store: store)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// The popover body: every layer on the current page, listed top-to-bottom
/// (topmost first, matching `Page.layerOrder`'s front-to-back convention),
/// draggable via `List`'s native reorder handles. Drag-to-reorder rather
/// than up/down buttons because the row count is now dynamic — a page can
/// have many text/image/audio elements, and up/down taps don't scale the
/// way a drag handle does once there are more than a handful of rows.
/// The popover already owns the touch surface, so there's no gesture
/// conflict with the canvas underneath (the concern that ruled out drag
/// for the old fixed-3-row design doesn't apply here).
private struct LayerOrderPopoverView: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Layer Order")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 2)
            Text("Drag to reorder. Top of the list draws — and receives touches — first.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            List {
                ForEach(store.layerOrder, id: \.self) { ref in
                    LayerOrderRow(title: title(for: ref), icon: icon(for: ref))
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 12))
                }
                .onMove { indices, newOffset in
                    var order = store.layerOrder
                    order.move(fromOffsets: indices, toOffset: newOffset)
                    store.setLayerOrder(order)
                }
            }
            .listStyle(.plain)
            // Forces reorder handles to show without a separate "Edit"
            // step — this popover exists for exactly one purpose, so
            // there's no reason to make the user find an Edit button
            // first. No `.onDelete` is attached, so only the drag handle
            // appears, not a delete affordance.
            .environment(\.editMode, .constant(.active))
            .frame(height: rowAreaHeight)
        }
        .frame(width: 280)
    }

    /// Caps the list's height so a page with many elements scrolls inside
    /// the popover instead of the popover growing past the screen.
    private var rowAreaHeight: CGFloat {
        min(CGFloat(store.layerOrder.count) * 44, 320)
    }

    private func title(for ref: CanvasLayerRef) -> String {
        switch ref {
        case .textEditor:
            return "Page Text"
        case .scribble:
            return "Scribble"
        case .element(let id):
            guard let element = store.elements.first(where: { $0.id == id }) else {
                return "Element"
            }
            return elementTitle(element)
        }
    }

    private func icon(for ref: CanvasLayerRef) -> String {
        switch ref {
        case .textEditor:
            return "doc.text"
        case .scribble:
            return "scribble"
        case .element(let id):
            guard let element = store.elements.first(where: { $0.id == id }) else {
                return "questionmark.square"
            }
            switch element.kind {
            case .text: return "text.alignleft"
            case .image: return "photo"
            case .audio: return "waveform"
            }
        }
    }

    /// Disambiguates same-kind elements the way the user actually needs
    /// to tell them apart: text blocks show a content preview (so "which
    /// text is this" is obvious at a glance); image/audio blocks — which
    /// have no readable content to preview — are numbered by creation
    /// order ("Image 1", "Image 2", ...) so a page with several images
    /// can still be reordered by first/second/third rather than by guessing.
    private func elementTitle(_ element: CanvasElement) -> String {
        switch element.kind {
        case .text:
            let trimmed = (element.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Text \(ordinal(of: element))"
            }
            return String(trimmed.prefix(24))
        case .image:
            return "Image \(ordinal(of: element))"
        case .audio:
            return "Audio \(ordinal(of: element))"
        }
    }

    /// 1-based position of `element` among same-kind elements, in creation
    /// order (i.e. `page.elements` order, which is append-order).
    private func ordinal(of element: CanvasElement) -> Int {
        let sameKind = store.elements.filter { $0.kind == element.kind }
        return (sameKind.firstIndex(where: { $0.id == element.id }) ?? 0) + 1
    }
}

private struct LayerOrderRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            Text(title)
                .font(.body)
                .lineLimit(1)

            Spacer()
        }
    }
}
