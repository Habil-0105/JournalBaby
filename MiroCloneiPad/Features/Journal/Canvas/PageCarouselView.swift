import SwiftUI

/// Horizontal page carousel. Pages are rendered at a reduced, paper-like
/// size (not full screen) so the current page is centered while the top
/// portion of the previous and next pages — or the add-page area on the
/// last page — peeks up from below the bottom edge of the viewport.
///
/// Transitions use a `visualPageIndex` that can sit between integers; during
/// a swipe it tracks the drag, and on commit it springs to the next page.
/// That single value drives both the horizontal position and the Y offset
/// of every page, so side pages visibly rise from their lower resting
/// position toward the center as the swipe progresses, and fall back to
/// it when the new page becomes current.
struct PageCarouselView: View {
    @ObservedObject var store: CanvasStore

    /// Fractional page index that drives rendering. When at rest it equals
    /// `CGFloat(store.currentPageIndex)`. While swiping it tracks the
    /// drag; on commit it springs to the new integer (with overshoot).
    @State private var visualPageIndex: CGFloat = 0

    /// Snapshot of the page currently animating out during a delete.
    /// `nil` when no delete is in flight. The page data is held here so
    /// the ghost can render even after the page is removed from
    /// `store.pages`.
    @State private var exitGhost: CanvasStore.PendingDeletion?

    /// 0 → 1, animates while a delete ghost is on screen. Drives the
    /// ghost's outward drop, outward slide, fade, and slight shrink.
    @State private var exitProgress: CGFloat = 0

    /// Slots whose regular `PageContentView` should be hidden (because a
    /// ghost is animating in their place). Cleared when the delete
    /// animation completes.
    @State private var hiddenSlotIndices: Set<Int> = []

    /// Direction the ghost should exit toward. -1 = left, +1 = right.
    /// 0 = straight down (no horizontal drift). Cached at delete-start
    /// time so it doesn't drift if `visualPageIndex` keeps moving.
    @State private var exitDirection: CGFloat = 0

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

    /// Fraction of the page's own height that should remain visible above
    /// the container's bottom edge for previous / next / add pages.
    private let neighborVisibleFraction: CGFloat = 0.2

    /// How much side pages shrink relative to the current one. At a
    /// |delta| of 1 the side page is `1 - this` of the current page's
    /// size. Subtle — gives the deck a hint of perspective without
    /// looking like a perspective transform.
    private let sidePageScale: CGFloat = 0.05

    /// Spring tuning for the page-snap animation. Low response + moderate
    /// damping = fast + slightly elastic, with a small overshoot that
    /// settles quickly.
    private let transitionResponse: Double = 0.32
    private let transitionDamping: Double = 0.62

    var body: some View {
        GeometryReader { geo in
            let pageSize = scaledPageSize(for: geo.size)
            let spacing = pageSize.width * spacingFactor

            ZStack {
                ForEach(visibleSlots, id: \.self) { slotIndex in
                    slotView(
                        slotIndex: slotIndex,
                        pageSize: pageSize,
                        spacing: spacing,
                        containerHeight: geo.size.height
                    )
                }

                if let ghost = exitGhost {
                    risingReplacementView(
                        ghost: ghost,
                        pageSize: pageSize,
                        spacing: spacing,
                        containerHeight: geo.size.height
                    )
                    exitGhostView(
                        ghost: ghost,
                        pageSize: pageSize,
                        spacing: spacing,
                        containerHeight: geo.size.height
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(swipeGesture(spacing: spacing))
            .onAppear {
                visualPageIndex = CGFloat(store.currentPageIndex)
                store.updateCanvasSize(pageSize)
            }
            .onChange(of: pageSize) { _, newSize in
                store.updateCanvasSize(newSize)
            }
            .onChange(of: store.currentPageIndex) { oldValue, newValue in
                // Snap if the change is large (e.g. addPage after delete);
                // animate if it's the natural ±1 from a drag commit.
                let delta = CGFloat(newValue - oldValue)
                if abs(delta) <= 1.5 {
                    withAnimation(.spring(
                        response: transitionResponse,
                        dampingFraction: transitionDamping
                    )) {
                        visualPageIndex = CGFloat(newValue)
                    }
                } else {
                    visualPageIndex = CGFloat(newValue)
                }
            }
            .onChange(of: store.pendingDeletion) { oldValue, newValue in
                handlePendingDeletionChange(oldValue: oldValue, newValue: newValue)
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

    /// Vertical offset for a page with the given |delta| from the visual
    /// current. Side pages sit at `neighborVerticalOffset`; the current
    /// page sits at 0. Pages with |delta| > 1 are clamped to the same deep
    /// position as a side page.
    private func neighborVerticalOffset(containerHeight: CGFloat, pageSize: CGSize) -> CGFloat {
        let visibleStrip = pageSize.height * neighborVisibleFraction
        return containerHeight / 2 + pageSize.height / 2 - visibleStrip
    }

    /// Integer slot indices that are currently within the visible window
    /// (|delta| ≤ 1.5). We render one view per slot, then let each view
    /// decide whether to show a real page or the Add Page area.
    private var visibleSlots: [Int] {
        let lower = Int(floor(visualPageIndex - 0.5))
        let upper = Int(ceil(visualPageIndex + 0.5))
        return Array(lower...upper)
    }

    // MARK: - Slot rendering

    @ViewBuilder
    private func slotView(
        slotIndex: Int,
        pageSize: CGSize,
        spacing: CGFloat,
        containerHeight: CGFloat
    ) -> some View {
        let delta = CGFloat(slotIndex) - visualPageIndex
        let absDelta = min(abs(delta), 1.0)

        slotContent(slotIndex: slotIndex, pageSize: pageSize, delta: delta)
            .offset(
                x: delta * spacing,
                y: absDelta * neighborVerticalOffset(
                    containerHeight: containerHeight,
                    pageSize: pageSize
                )
            )
            .scaleEffect(1 - sidePageScale * absDelta)
    }

    /// Picks what to render in a given slot — a real page, the Add Page
    /// area, or nothing. Slots in `hiddenSlotIndices` (those that are
    /// currently being animated as part of a delete) render nothing so
    /// the ghost / rising replacement overlays don't double up with the
    /// regular slot rendering.
    @ViewBuilder
    private func slotContent(slotIndex: Int, pageSize: CGSize, delta: CGFloat) -> some View {
        if hiddenSlotIndices.contains(slotIndex) {
            EmptyView()
        } else if slotIndex >= 0 && slotIndex < store.pages.count {
            let isCurrent = abs(delta) < 0.5
            pageStack(
                page: store.pages[slotIndex],
                pageIndex: slotIndex,
                isCurrent: isCurrent,
                pageSize: pageSize
            )
        } else if slotIndex == store.pages.count {
            addPageArea(pageSize: pageSize)
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
            // Add the page; onChange(of: store.currentPageIndex) will animate
            // visualPageIndex forward to match.
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
                // Drive visualPageIndex directly from drag translation so the
                // incoming page visibly rises (y offset scales with |delta|)
                // while the user is still dragging. Set without withAnimation
                // so the drag tracks the finger 1:1 with no spring lag.
                visualPageIndex = CGFloat(store.currentPageIndex)
                    + (-value.translation.width / spacing)
            }
            .onEnded { value in
                guard !store.drawMode else {
                    // Draw mode was toggled mid-drag — spring back to current.
                    springVisualToCurrent()
                    return
                }

                let threshold = spacing * swipeThreshold
                let direction: CGFloat = value.translation.width < 0 ? +1 : -1
                let shouldCommit = abs(value.translation.width) > threshold

                guard shouldCommit else {
                    // Didn't cross threshold — spring back to current page.
                    springVisualToCurrent()
                    return
                }

                let proposedIndex = store.currentPageIndex + Int(direction)
                if proposedIndex >= 0 && proposedIndex < store.pages.count {
                    // Normal page change. Updating `store.currentPageIndex`
                    // triggers onChange which animates visualPageIndex from
                    // its current drag position to the new index with a
                    // spring (including the overshoot).
                    store.currentPageIndex = proposedIndex
                } else if proposedIndex == store.pages.count {
                    // Swiped into the Add Page slot on the right — create
                    // the page; onChange of currentPageIndex animates the
                    // visual to the new index.
                    store.addPage()
                } else {
                    // Swiped right past the first page — spring back.
                    springVisualToCurrent()
                }
            }
    }

    /// Animates visualPageIndex back to the store's current page index with
    /// the same spring used by onChange. Used when a swipe doesn't commit
    /// (draw-mode cancel, under-threshold release, out-of-bounds swipe).
    private func springVisualToCurrent() {
        withAnimation(.spring(
            response: transitionResponse,
            dampingFraction: transitionDamping
        )) {
            visualPageIndex = CGFloat(store.currentPageIndex)
        }
    }

    // MARK: - Delete animation

    /// How long the delete animation runs before we confirm the deletion.
    /// Tuned to roughly match the spring settle time (`response 0.32`,
    /// `damping 0.62`) plus a small margin for the overshoot.
    private let deleteAnimationDuration: TimeInterval = 0.5

    /// Extra horizontal drift the ghost travels as it exits, expressed in
    /// fractions of the page's own width.
    private let exitHorizontalDistanceFraction: CGFloat = 0.35

    /// Extra vertical drop the ghost travels as it exits, expressed in
    /// fractions of the page's own height.
    private let exitVerticalDropFraction: CGFloat = 0.45

    /// Extra shrink the ghost gets as it exits.
    private let exitShrinkAmount: CGFloat = 0.1

    /// Reacts to `store.pendingDeletion` becoming non-nil (a delete was
    /// requested) or nil (the carousel has confirmed it and the page is
    /// gone). Hides the regular slot during the exit, animates the ghost
    /// outward + down, and springs `visualPageIndex` to the replacement
    /// index so the replacement page visibly rises into center.
    private func handlePendingDeletionChange(
        oldValue: CanvasStore.PendingDeletion?,
        newValue: CanvasStore.PendingDeletion?
    ) {
        if let new = newValue, oldValue == nil {
            // A new delete just started.
            beginDeleteAnimation(for: new)
        } else if newValue == nil, exitGhost != nil {
            // The carousel previously started a delete; the page has now
            // been removed from `pages`. Clear local ghost state.
            exitGhost = nil
            exitProgress = 0
            hiddenSlotIndices.removeAll()
        }
    }

    /// Begins the delete animation: hide the regular slot at the
    /// deleted page's index AND the slot where the replacement was
    /// rendered pre-delete (so the rising replacement overlay doesn't
    /// double up with the regular slot rendering), freeze an exit
    /// direction based on which side the replacement page is coming
    /// from, capture the page data as a ghost, and run the spring
    /// that animates both the ghost exit and the entry of the
    /// replacement page.
    private func beginDeleteAnimation(for pd: CanvasStore.PendingDeletion) {
        // Exit toward the side OPPOSITE the replacement, so the replacement
        // can rise unobstructed. If the replacement is on the left
        // (replacementIndex < originalIndex), the deleted page drifts to the
        // right (exitDirection = +1). If the replacement is on the right
        // or stays put, the deleted page drifts to the left
        // (exitDirection = -1). For the case where original == replacement
        // (deleting a side page that doesn't change currentPageIndex) fall
        // back to whichever side the page was on.
        let direction: CGFloat
        if pd.replacementIndex < pd.originalIndex {
            direction = +1
        } else if pd.replacementIndex > pd.originalIndex {
            direction = -1
        } else {
            direction = pd.originalIndex > Int(visualPageIndex.rounded()) ? +1 : -1
        }
        exitDirection = direction

        // Hide the deleted slot and the pre-delete slot of the replacement
        // so the overlays render them without doubling up.
        var hidden: Set<Int> = [pd.originalIndex]
        if let preSlot = risingReplacementPreSlot(for: pd) {
            hidden.insert(preSlot)
        }
        hiddenSlotIndices = hidden

        exitGhost = pd

        let cleanupDelay = deleteAnimationDuration
        withAnimation(.spring(
            response: transitionResponse,
            dampingFraction: transitionDamping
        )) {
            // Animate to the replacement index so the post-delete layout
            // (where the deleted page is gone and the replacement is at
            // center) is what we settle into.
            visualPageIndex = CGFloat(pd.replacementIndex)
            // Animate the ghost outward + downward, and (via the rising
            // replacement overlay) the replacement into center.
            exitProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + cleanupDelay) {
            // Confirm the deletion — this calls removePage(at:) under the
            // hood and clears pendingDeletion, which triggers the second
            // branch of handlePendingDeletionChange to clean up local state.
            store.confirmPendingDeletion()
        }
    }

    /// Slot index where the replacement page was rendered pre-delete, or
    /// nil if there is no replacement to show (single-page delete).
    private func risingReplacementPreSlot(
        for pd: CanvasStore.PendingDeletion
    ) -> Int? {
        let n = store.pages.count
        guard n > 1 else { return nil }
        // The page that becomes current after removal was rendered at
        // `originalIndex + 1` — unless the deleted page was the last,
        // in which case the replacement was at `originalIndex - 1`
        // (the previous page becomes current per the existing rule).
        if pd.originalIndex == n - 1 {
            return pd.originalIndex - 1
        }
        return pd.originalIndex + 1
    }

    /// Renders the ghost of the page being deleted. Positioned at its
    /// original slot, with `exitProgress` driving the outward drop,
    /// sideways drift, fade, and slight shrink.
    private func exitGhostView(
        ghost: CanvasStore.PendingDeletion,
        pageSize: CGSize,
        spacing: CGFloat,
        containerHeight: CGFloat
    ) -> some View {
        let delta = CGFloat(ghost.originalIndex) - visualPageIndex
        let absDelta = min(abs(delta), 1.0)

        let baseX = delta * spacing
        let baseY = absDelta * neighborVerticalOffset(
            containerHeight: containerHeight,
            pageSize: pageSize
        )
        let baseScale = 1 - sidePageScale * absDelta

        let exitX = baseX + exitDirection * pageSize.width * exitHorizontalDistanceFraction * exitProgress
        let exitY = baseY + pageSize.height * exitVerticalDropFraction * exitProgress
        let exitScale = baseScale - exitShrinkAmount * exitProgress
        let exitOpacity = 1 - exitProgress

        return pageStack(
            page: ghost.page,
            pageIndex: ghost.originalIndex,
            isCurrent: false,
            pageSize: pageSize
        )
        .offset(x: exitX, y: exitY)
        .scaleEffect(max(exitScale, 0.01))
        .opacity(max(exitOpacity, 0))
        .allowsHitTesting(false)
    }

    /// Renders the replacement page (the page that will become current
    /// after the delete) as a separate overlay that rises from its
    /// pre-delete lower/side position to center. Driven by
    /// `exitProgress`: 0 = pre-delete (at the side), 1 = post-delete
    /// (at center, ready to take over as current).
    @ViewBuilder
    private func risingReplacementView(
        ghost: CanvasStore.PendingDeletion,
        pageSize: CGSize,
        spacing: CGFloat,
        containerHeight: CGFloat
    ) -> some View {
        if let preSlot = risingReplacementPreSlot(for: ghost),
           store.pages.indices.contains(preSlot) {
            let page = store.pages[preSlot]

            // The visual delta at the start of the animation is
            // (preSlot - originalIndex) since visualPageIndex begins at
            // originalIndex. As the animation progresses, exitProgress
            // interpolates the delta toward 0 (center, post-delete).
            let preDelta = CGFloat(preSlot - ghost.originalIndex)
            let overlayDelta = preDelta * (1 - exitProgress)
            let absDelta = abs(overlayDelta)

            let x = overlayDelta * spacing
            let y = absDelta * neighborVerticalOffset(
                containerHeight: containerHeight,
                pageSize: pageSize
            )
            let scale = max(1 - sidePageScale * absDelta, 0.01)

            PageContentView(
                store: store,
                page: page,
                pageIndex: ghost.replacementIndex,
                isCurrent: false,
                pageSize: pageSize
            )
            .offset(x: x, y: y)
            .scaleEffect(scale)
            .allowsHitTesting(false)
        }
        // Single-page delete (no replacement in `pages`): no rising
        // overlay — confirmPendingDeletion will snap to the new empty
        // page after the ghost finishes exiting.
    }
}
