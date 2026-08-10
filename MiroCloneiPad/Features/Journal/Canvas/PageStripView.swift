import SwiftUI

/// Horizontal strip of page thumbnails sitting under the canvas. Tapping
/// a page switches to it; the trailing "+" appends a new page; a long
/// press on a non-current page reveals a delete affordance.
///
/// Thumbnails are intentionally minimal — a numbered card with a faint
/// grid background — because rendering the actual contents of every page
/// here would be expensive and the user's eyes are on the canvas, not
/// the strip.
struct PageStripView: View {
    @ObservedObject var store: CanvasStore

    /// Index of the page whose delete button is currently shown after a
    /// long-press. `nil` means no destructive action is pending.
    @State private var pendingDeleteIndex: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.pageStripSpacing) {
                    ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                        pageThumbnail(index: index, page: page)
                            .id(page.id)
                    }

                    addPageButton
                }
                .padding(.horizontal, DesignSystem.pageStripHorizontalPadding)
                .padding(.vertical, DesignSystem.pageStripVerticalPadding)
            }
            .onChange(of: store.currentPageIndex) { _, newIndex in
                guard store.pages.indices.contains(newIndex) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(store.pages[newIndex].id, anchor: .center)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .confirmationDialog(
            "Delete this page?",
            isPresented: Binding(
                get: { pendingDeleteIndex != nil },
                set: { if !$0 { pendingDeleteIndex = nil } }
            ),
            presenting: pendingDeleteIndex
        ) { index in
            Button("Delete Page", role: .destructive) {
                store.removePage(at: index)
                pendingDeleteIndex = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteIndex = nil
            }
        } message: { _ in
            Text("This page and everything on it will be removed.")
        }
    }

    // MARK: - Subviews

    private func pageThumbnail(index: Int, page: Page) -> some View {
        let isCurrent = index == store.currentPageIndex
        return Button {
            store.switchToPage(at: index)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.pageThumbnailCornerRadius)
                    .fill(Color(.systemBackground))

                RoundedRectangle(cornerRadius: DesignSystem.pageThumbnailCornerRadius)
                    .strokeBorder(
                        isCurrent ? Color.accentColor : Color.black.opacity(0.12),
                        lineWidth: isCurrent ? 2 : 1
                    )

                Text("\(index + 1)")
                    .font(.system(size: 22, weight: isCurrent ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            }
            .frame(
                width: DesignSystem.pageThumbnailWidth,
                height: DesignSystem.pageThumbnailHeight
            )
            .overlay(alignment: .topTrailing) {
                if isCurrent {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .offset(x: -6, y: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if store.pages.count > 1 || !isCurrent {
                Button(role: .destructive) {
                    pendingDeleteIndex = index
                } label: {
                    Label("Delete Page", systemImage: "trash")
                }
            }
        }
    }

    private var addPageButton: some View {
        Button {
            store.addPage()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.pageThumbnailCornerRadius)
                    .strokeBorder(Color.black.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.pageThumbnailCornerRadius)
                            .fill(Color.clear)
                    )

                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(
                width: DesignSystem.pageThumbnailWidth,
                height: DesignSystem.pageThumbnailHeight
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Page")
    }
}
