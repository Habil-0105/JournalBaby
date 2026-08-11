import CoreGraphics
import SwiftUI

/// The "existing design system" every element and the canvas itself pull
/// spacing/sizing from. Centralizing these is what keeps padding
/// consistent as the layout evolves — change a value here, it applies
/// everywhere at once.
enum DesignSystem {
    /// Spring used to animate the carousel ↔ writing mode switch. The
    /// store flips `writingMode` inside `withAnimation` with this curve so
    /// the `JournalView` mode-swap transitions always run.
    static let modeSwitchAnimation = Animation.spring(response: 0.35, dampingFraction: 0.82)

    /// Gap between a block's edge and its own content (text, audio
    /// controls, etc). Images intentionally skip this and bleed
    /// edge-to-edge within their block.
    static let blockContentPadding: CGFloat = 16

    static let cornerRadius: CGFloat = 16

    static let minBlockWidth: CGFloat = 160
    static let minBlockHeight: CGFloat = 90

    /// Default widths new blocks start at. These are content-appropriate
    /// sizes, NOT the full canvas width — an element only gets wider when
    /// the user explicitly resizes it.
    static let defaultTextWidth: CGFloat = 360
    static let defaultImageWidth: CGFloat = 320
    static let defaultAudioWidth: CGFloat = 280

    /// Height-to-width ratio of a page (tall sheet of paper). Shared by
    /// every paper geometry so pages keep the same shape at any size.
    static let pageAspectRatio: CGFloat = 1.3

    /// The **canonical content coordinate space** of a page. This is the
    /// paper size used in writing mode — the largest, native-resolution
    /// rendering. The carousel renders the same content at this size and
    /// scales it down to each deck slot, so both modes show the identical
    /// region of the board. `CanvasStore.canvasSize` (used for element
    /// clamps) is always this value, never the carousel's smaller slot
    /// size — otherwise content authored against the bigger writing paper
    /// would fall outside the smaller carousel paper and get clipped.
    static func writingCanvasSize(for container: CGSize) -> CGSize {
        let width = min(
            container.width * 0.85,
            container.height * 0.75 / pageAspectRatio
        )
        return CGSize(width: width, height: width * pageAspectRatio)
    }

    /// The on-screen display size of a page in the carousel deck
    /// (smaller than the canonical canvas, which is why the carousel
    /// downscales the content to fit). Used for layout/spacing math only.
    static func carouselSlotSize(for container: CGSize) -> CGSize {
        let width = min(
            container.width * 0.45,
            container.height * 0.7 / pageAspectRatio
        )
        return CGSize(width: width, height: width * pageAspectRatio)
    }
}