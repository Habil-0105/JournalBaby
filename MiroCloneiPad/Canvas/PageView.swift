import SwiftUI

/// The page. Its width always matches the screen (blocks get the full
/// available width by default); its height is `max(one screen, however
/// tall the content actually is)` — since text can grow and blocks can
/// be resized taller, content can now exceed one screen, at which point
/// `ContentView`'s ScrollView takes over. There's still exactly one
/// page, and it's never narrower than the screen or shorter than it.
struct PageView: View {
    @ObservedObject var store: CanvasStore
    /// Full screen width, including the outer page padding.
    var pageWidth: CGFloat
    /// Full screen height — the page's minimum height even when empty.
    var minHeight: CGFloat

    var body: some View {
        let (frames, contentHeight) = store.layout()
        let pageHeight = max(contentHeight + DesignSystem.pagePadding * 2, minHeight)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(Color(.systemBackground))

            ForEach(store.elements) { element in
                if let frame = frames[element.id] {
                    ElementContainerView(store: store, element: element, frame: frame)
                        .offset(
                            x: frame.minX + DesignSystem.pagePadding,
                            y: frame.minY + DesignSystem.pagePadding
                        )
                }
            }
        }
        .frame(width: pageWidth, height: pageHeight, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.2), value: store.elements)
        .coordinateSpace(name: "page")
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedElementID = nil
        }
    }
}
