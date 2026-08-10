import CoreGraphics

/// The "existing design system" every block and the page itself pull
/// spacing/sizing from. Centralizing these is what keeps padding
/// consistent as the layout evolves — change a value here, it applies
/// everywhere at once.
enum DesignSystem {
    /// Gap between the page's own edge and the blocks inside it, AND
    /// between the screen edge and the page. Reusing one value for both
    /// is what gives the whole app one consistent margin rhythm instead
    /// of two different-feeling gaps.
    static let pagePadding: CGFloat = 20

    /// Gap between two blocks — used both across a row and between rows.
    static let blockSpacing: CGFloat = 16

    /// Gap between a block's edge and its own content (text, audio
    /// controls, etc). Images intentionally skip this and bleed
    /// edge-to-edge within their block.
    static let blockContentPadding: CGFloat = 16

    static let cornerRadius: CGFloat = 16

    static let minBlockWidth: CGFloat = 160
    static let minBlockHeight: CGFloat = 90

    /// Fixed vertical space allocated for page header inside physical page card.
    static let pageHeaderHeight: CGFloat = 36
    static let pageShadowRadius: CGFloat = 8
    static let pageShadowY: CGFloat = 4

    /// Width of the central physical book spine gutter on iPad 2-page spread.
    static let spineGutterWidth: CGFloat = 24
}
