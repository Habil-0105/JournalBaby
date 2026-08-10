import CoreGraphics

/// The "existing design system" every element and the canvas itself pull
/// spacing/sizing from. Centralizing these is what keeps padding
/// consistent as the layout evolves — change a value here, it applies
/// everywhere at once.
enum DesignSystem {
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

    // MARK: - Page strip

    /// Size of each thumbnail in the page strip. Tall enough to read as a
    /// card, small enough to fit several across an iPad screen.
    static let pageThumbnailWidth: CGFloat = 56
    static let pageThumbnailHeight: CGFloat = 80
    static let pageThumbnailCornerRadius: CGFloat = 10

    /// Horizontal gap between adjacent thumbnails and the inset from the
    /// screen edge to the first / last thumbnail.
    static let pageStripSpacing: CGFloat = 12
    static let pageStripHorizontalPadding: CGFloat = 16
    static let pageStripVerticalPadding: CGFloat = 10
}