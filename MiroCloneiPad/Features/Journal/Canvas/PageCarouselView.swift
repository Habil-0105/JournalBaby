import SwiftUI

/// Horizontal page carousel. Pages are rendered at a reduced, paper-like
/// size (not full screen) so the current page is centered while parts of
/// the previous and next pages — or the add-page area on the last page —
/// stay visible around it. A dynamic page number sits below each page;
/// the current page's number is highlighted.
struct PageCarouselView: View {
    @ObservedObject var store: CanvasStore
    @State private var dragOffset: CGFloat = 0

    /// Fraction of the container width a single page occupies.
    private let pageWidthFraction: CGFloat = 0.45
    /// Height-to-width ratio of a page (tall sheet of paper).
    private let pageAspectRatio: CGFloat = 1.3
    /// Max fraction of the container height a page may occupy.
    private let maxPageHeightFraction: CGFloat = 0.7
    /// Gap between adjacent page centers, relative to page width. Keeps a
    /// neighbor visible at roughly half its width with a small gap.
    private let spacingFactor: CGFloat = 1.15
    /// Fraction of the spacing that must be dragged to switch pages.
    private let swipeThreshold: CGFloat = 0.25

    var body: some View {
        GeometryReader { geo in
            let pageSize = scaledPageSize(for: geo.size)
            let spacing = pageSize.width * spacingFactor

            ZStack {
                previousPage(pageSize: pageSize, spacing: spacing)
                currentPage(pageSize: pageSize, spacing: spacing)
                trailingContent(pageSize: pageSize, spacing: spacing)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(swipeGesture(spacing: spacing))
            .onAppear { store.updateCanvasSize(pageSize) }
            .onChange(of: pageSize) { _, newSize in
                store.updateCanvasSize(newSize)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Layout

    /// The zoomed-out page size: about half the container width, capped so
    /// the page (plus its page-number label) always fits the height.
    private func scaledPageSize(for container: CGSize) -> CGSize {
        let widthFromRatio = container.width * pageWidthFraction
        let widthFromHeight = container.height * maxPageHeightFraction / pageAspectRatio
        let width = min(widthFromRatio, widthFromHeight)
        return CGSize(width: width, height: width * pageAspectRatio)
    }

    /// Horizontal offset for a page at `index` relative to the current page.
    private func xOffset(for index: Int, spacing: CGFloat) -> CGFloat {
        CGFloat(index - store.currentPageIndex) * spacing + dragOffset
    }

    /// Vertical offset for the previous / next / add pages so they sit
    /// clearly lower than the centered current page. Scaled from the page
    /// height so it looks consistent across screen sizes.
    private func neighborVerticalOffset(pageSize: CGSize) -> CGFloat {
        pageSize.height * 0.08
    }

    // MARK: - Subviews

    @ViewBuilder
    private func previousPage(pageSize: CGSize, spacing: CGFloat) -> some View {
        if store.currentPageIndex > 0 {
            let prevIndex = store.currentPageIndex - 1
            pageStack(
                page: store.pages[prevIndex],
                pageIndex: prevIndex,
                isCurrent: false,
                pageSize: pageSize
            )
            .offset(
                x: xOffset(for: prevIndex, spacing: spacing),
                y: neighborVerticalOffset(pageSize: pageSize)
            )
        }
    }

    private func currentPage(pageSize: CGSize, spacing: CGFloat) -> some View {
        pageStack(
            page: store.pages[store.currentPageIndex],
            pageIndex: store.currentPageIndex,
            isCurrent: true,
            pageSize: pageSize
        )
        .offset(x: xOffset(for: store.currentPageIndex, spacing: spacing))
    }

    @ViewBuilder
    private func trailingContent(pageSize: CGSize, spacing: CGFloat) -> some View {
        if store.currentPageIndex < store.pages.count - 1 {
            let nextIndex = store.currentPageIndex + 1
            pageStack(
                page: store.pages[nextIndex],
                pageIndex: nextIndex,
                isCurrent: false,
                pageSize: pageSize
            )
            .offset(
                x: xOffset(for: nextIndex, spacing: spacing),
                y: neighborVerticalOffset(pageSize: pageSize)
            )
        } else {
            addPageArea(pageSize: pageSize)
                .offset(
                    x: xOffset(for: store.pages.count, spacing: spacing),
                    y: neighborVerticalOffset(pageSize: pageSize)
                )
        }
    }

    /// A page plus its dynamic page-number label underneath.
    private func pageStack(page: Page, pageIndex: Int, isCurrent: Bool, pageSize: CGSize) -> some View {
        VStack(spacing: 10) {
            PageContentView(
                store: store,
                page: page,
                pageIndex: pageIndex,
                isCurrent: isCurrent,
                pageSize: pageSize
            )
            pageNumberLabel(pageIndex: pageIndex, isCurrent: isCurrent)
        }
    }

    private func pageNumberLabel(pageIndex: Int, isCurrent: Bool) -> some View {
        Text("\(pageIndex + 1)")
            .font(.system(size: isCurrent ? 24 : 16, weight: isCurrent ? .semibold : .regular, design: .rounded))
            .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            .frame(minWidth: 28, minHeight: 28)
    }

    // MARK: - Add Page Area

    private func addPageArea(pageSize: CGSize) -> some View {
        Button {
            store.addPage()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .strokeBorder(
                        Color.black.opacity(0.15),
                        style: StrokeStyle(lineWidth: 1, dash: [6])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                            .fill(Color(.systemBackground))
                    )

                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 36, weight: .medium))
                    Text("Add Page")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.secondary)
            }
            .frame(width: pageSize.width, height: pageSize.height)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Page")
    }

    // MARK: - Gesture

    private func swipeGesture(spacing: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !store.drawMode else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard !store.drawMode else {
                    dragOffset = 0
                    return
                }

                let threshold = spacing * swipeThreshold

                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if value.translation.width < -threshold {
                        // Swipe left → next page
                        if store.currentPageIndex < store.pages.count - 1 {
                            store.switchToPage(at: store.currentPageIndex + 1)
                        } else {
                            // Swiped into add area → create page
                            store.addPage()
                        }
                    } else if value.translation.width > threshold {
                        // Swipe right → previous page
                        if store.currentPageIndex > 0 {
                            store.switchToPage(at: store.currentPageIndex - 1)
                        }
                    }
                    dragOffset = 0
                }
            }
    }
}
