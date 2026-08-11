import CoreGraphics
import SwiftUI

/// The "existing design system" every element and the canvas itself pull
/// spacing/sizing from. Centralizing these is what keeps padding
/// consistent as the layout evolves — change a value here, it applies
/// everywhere at once.
enum DesignSystem {
    /// Spring used to animate the carousel ↔ writing mode switch.
    static let modeSwitchAnimation = Animation.spring(response: 0.35, dampingFraction: 0.82)

    /// Zoom level constraints for Writing Mode.
    /// 1.0 represents the resting paper size. Zooming out to or below 1.0 triggers auto-exit.
    static let minWritingCanvasScale: CGFloat = 1.0
    static let maxWritingCanvasScale: CGFloat = 3.0

    /// Gap between a block's edge and its own content.
    static let blockContentPadding: CGFloat = 16

    /// Page margins for the full-body text editor. Reserves room at the
    /// top for the date label, leaves a comfortable reading column, and
    /// keeps the bottom clear so the last line isn't flush against the
    /// paper edge.
    static let bodyTextHorizontalMargin: CGFloat = 32
    static let bodyTextTopMargin: CGFloat = 40
    static let bodyTextBottomMargin: CGFloat = 32

    static let cornerRadius: CGFloat = 16

    static let minBlockWidth: CGFloat = 160
    static let minBlockHeight: CGFloat = 90

    static let defaultTextWidth: CGFloat = 360
    static let defaultImageWidth: CGFloat = 320
    static let defaultAudioWidth: CGFloat = 280

    static let pageAspectRatio: CGFloat = 1.3

    static func writingCanvasSize(for container: CGSize) -> CGSize {
        let width = min(
            container.width * 0.85,
            container.height * 0.75 / pageAspectRatio
        )
        return CGSize(width: width, height: width * pageAspectRatio)
    }

    static func carouselSlotSize(for container: CGSize) -> CGSize {
        let width = min(
            container.width * 0.45,
            container.height * 0.7 / pageAspectRatio
        )
        return CGSize(width: width, height: width * pageAspectRatio)
    }
}
