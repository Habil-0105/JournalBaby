import SwiftUI

/// The page. Its width always matches the screen (blocks get the full
/// available width by default); its height is `max(one screen, however
/// tall the content actually is)` — since text can grow and blocks can
/// be resized taller, content can now exceed one screen, at which point
/// `ContentView`'s ScrollView takes over. There's still exactly one
/// page, and it's never narrower than the screen or shorter than it.
struct PageView: View {
    @ObservedObject var store: CanvasStore
    var pageLayout: PageLayout
    var pageWidth: CGFloat
    var pageHeight: CGFloat
    var totalPages: Int

    var body: some View {
        let cardWidth = max(pageWidth - DesignSystem.pagePadding * 2, 100)
        let cardHeight = max(pageHeight - DesignSystem.pagePadding * 2, 100)

        let canonicalElementsMap = Dictionary(uniqueKeysWithValues: store.elements.map { ($0.id, $0) })
        let slicesMap: [UUID: [String]] = {
            var map: [UUID: [String]] = [:]
            for element in pageLayout.elements {
                if element.kind == .text {
                    map[element.canonicalID, default: []].append(element.textSubstring ?? "")
                }
            }
            return map
        }()

        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Page \(pageLayout.pageIndex + 1) of \(totalPages)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))

                Spacer()
            }
            .padding(.horizontal, DesignSystem.pagePadding)
            .frame(height: DesignSystem.pageHeaderHeight)

            // Content container bounded strictly within card
            ZStack(alignment: .topLeading) {
                ForEach(pageLayout.elements) { placed in
                    if let canonical = canonicalElementsMap[placed.canonicalID] {
                        ElementContainerView(
                            store: store,
                            placed: placed,
                            element: canonical,
                            slices: slicesMap[placed.canonicalID] ?? [placed.textSubstring ?? ""]
                        )
                        .offset(x: placed.frame.minX, y: placed.frame.minY)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, DesignSystem.pagePadding)
            .padding(.bottom, DesignSystem.pagePadding)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: DesignSystem.pageShadowRadius, x: 0, y: DesignSystem.pageShadowY)
        )
        .overlay(alignment: .bottomTrailing) {
            if pageLayout.pageIndex < totalPages - 1 {
                DogEarCornerView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .coordinateSpace(name: "page")
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedElementID = nil
        }
        .animation(.easeInOut(duration: 0.2), value: pageLayout)
    }
}

/// Visual dog-ear corner curl hint displayed on the bottom-right of a page.
struct DogEarCornerView: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: size, y: 0))
                path.addLine(to: CGPoint(x: size, y: size))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color.black.opacity(0.22), Color.black.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            Path { path in
                path.move(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: size, y: 0))
                path.addLine(to: CGPoint(x: size, y: size))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color(.systemGroupedBackground), Color(.secondarySystemBackground)],
                    startPoint: .bottomTrailing,
                    endPoint: .topLeading
                )
            )
            .overlay(
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size))
                    path.addLine(to: CGPoint(x: size, y: 0))
                }
                .stroke(Color.primary.opacity(0.2), lineWidth: 1.5)
            )
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}
