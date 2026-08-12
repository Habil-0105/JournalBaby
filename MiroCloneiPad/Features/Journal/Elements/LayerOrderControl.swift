import SwiftUI
import PencilKit

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
/// each with a real preview thumbnail, draggable via `List`'s native
/// reorder handles.
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
                    LayerOrderRow(ref: ref, title: title(for: ref), store: store)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
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
        .frame(width: 300)
    }

    /// Caps the list's height so a page with many elements scrolls inside
    /// the popover instead of the popover growing past the screen.
    private var rowAreaHeight: CGFloat {
        min(CGFloat(store.layerOrder.count) * 56, 360)
    }

    /// Short category + ordinal label, e.g. "Image 2". The thumbnail next
    /// to it (not this string) is what actually disambiguates same-kind
    /// elements now — the ordinal just makes "which one am I dragging"
    /// unambiguous even before the eye lands on the thumbnail.
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
            switch element.kind {
            case .text: return "Text \(ordinal(of: element))"
            case .image: return "Image \(ordinal(of: element))"
            case .audio: return "Audio \(ordinal(of: element))"
            }
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
    let ref: CanvasLayerRef
    let title: String
    @ObservedObject var store: CanvasStore

    var body: some View {
        HStack(spacing: 12) {
            LayerThumbnailView(ref: ref, store: store)
            Text(title)
                .font(.body)
                .lineLimit(1)
            Spacer()
        }
    }
}

// MARK: - Thumbnails

/// Routes to the right kind of preview for a given layer ref. A fixed
/// 40×40 frame keeps every row the same height regardless of which
/// preview type it renders.
private struct LayerThumbnailView: View {
    let ref: CanvasLayerRef
    @ObservedObject var store: CanvasStore

    var body: some View {
        Group {
            switch ref {
            case .scribble:
                ScribbleThumbnail(drawing: store.currentPage.scribble, canvasSize: store.canvasSize)
            case .textEditor:
                TextSnippetThumbnail(text: store.currentPage.bodyText)
            case .element(let id):
                if let element = store.elements.first(where: { $0.id == id }) {
                    switch element.kind {
                    case .text:
                        TextSnippetThumbnail(text: element.text ?? "")
                    case .image:
                        ImageThumbnail(fileName: element.imageFileName, imagesURL: store.imagesURL)
                    case .audio:
                        AudioDurationThumbnail(duration: element.audioDuration)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill))
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.08)))
    }
}

/// Rasterizes the page's `PKDrawing` the same way `PageContentView`
/// already does for carousel-neighbour previews
/// (`PKDrawing.image(from:scale:)`), just at thumbnail scale. Rendered off
/// the main actor since it's pure offscreen rasterization with no UIKit
/// view-hierarchy involvement, so opening the popover doesn't stutter.
/// `.task(id: drawing)` re-renders only if the drawing itself changes
/// (PKDrawing is `Equatable`) — reordering rows during a drag doesn't
/// re-trigger this, since each row's identity (and thus its `@State`)
/// stays pinned to its `CanvasLayerRef`.
private struct ScribbleThumbnail: View {
    let drawing: PKDrawing
    let canvasSize: CGSize
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.systemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if drawing.dataRepresentation().isEmpty {
                Image(systemName: "scribble")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: drawing) {
            await render()
        }
    }

    private func render() async {
        guard !drawing.dataRepresentation().isEmpty else {
            image = nil
            return
        }
        let size = canvasSize.width > 0 && canvasSize.height > 0
            ? canvasSize
            : CGSize(width: 400, height: 400 * DesignSystem.pageAspectRatio)
        let rendered = await Task.detached(priority: .userInitiated) {
            drawing.image(from: CGRect(origin: .zero, size: size), scale: 0.12)
        }.value
        image = rendered
    }
}

/// A miniature rendering of the actual text content — not just a name —
/// so multiple text blocks (or the page body vs. a floating text element)
/// are told apart by what they actually say, the way the image thumbnail
/// tells images apart by what they actually show.
private struct TextSnippetThumbnail: View {
    let text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.systemBackground)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Image(systemName: "text.alignleft")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(trimmed)
                    .font(.system(size: 6, weight: .regular))
                    .lineLimit(6)
                    .foregroundStyle(.primary)
                    .padding(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// Loads the same file `ImageElementView` loads (`store.imagesURL` +
/// `UIImage(contentsOfFile:)`), just off the main actor so decoding a
/// full-resolution photo doesn't hitch the popover when it opens on a
/// page with several images.
private struct ImageThumbnail: View {
    let fileName: String?
    let imagesURL: URL
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if didFail || fileName == nil {
                Image(systemName: "photo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .clipped()
        .task(id: fileName) {
            await load()
        }
    }

    private func load() async {
        guard let fileName else {
            didFail = true
            return
        }
        let url = imagesURL.appendingPathComponent(fileName)
        let loaded = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
        if let loaded {
            image = loaded
        } else {
            didFail = true
        }
    }
}

/// Audio has no waveform stored anywhere in `CanvasElement` — only
/// `audioFileName` and `audioDuration` — so a fabricated waveform image
/// would be decorative fiction, not a real preview. The honest preview is
/// the duration, formatted the same way `AudioElementView` already
/// formats it.
private struct AudioDurationThumbnail: View {
    let duration: TimeInterval?

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            VStack(spacing: 2) {
                Image(systemName: "waveform")
                    .font(.caption2)
                if let duration {
                    Text(formatted(duration))
                        .font(.system(size: 8, weight: .medium))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func formatted(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
