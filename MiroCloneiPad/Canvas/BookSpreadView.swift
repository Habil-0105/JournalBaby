import SwiftUI

/// Renders a single physical open book spread.
/// On iPhone: renders 1 page.
/// On iPad: renders Left Page and Right Page side-by-side separated by a central book spine gutter.
struct BookSpreadView: View {
    @ObservedObject var store: CanvasStore
    var spread: BookSpread
    var pageWidth: CGFloat
    var pageHeight: CGFloat
    var totalPages: Int
    /// Forwarded so `PageView` can light up its page-level drawing
    /// canvas when the Scribble tool is active.
    var scribbleMode: Bool

    var body: some View {
        if let page = spread.leftPage {
            PageView(
                store: store,
                pageLayout: page,
                pageWidth: pageWidth,
                pageHeight: pageHeight,
                totalPages: totalPages,
                scribbleMode: scribbleMode
            )
        }
    }
}

/// Central vertical spine element separating left and right pages on iPad 2-page spreads.
struct SpineGutterView: View {
    var height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0.01), Color.black.opacity(0.18)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: DesignSystem.spineGutterWidth / 2 - 0.75)

            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1.5)

            LinearGradient(
                colors: [Color.black.opacity(0.18), Color.black.opacity(0.01)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: DesignSystem.spineGutterWidth / 2 - 0.75)
        }
        .frame(height: height)
    }
}
