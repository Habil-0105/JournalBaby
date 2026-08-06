import UIKit
import CoreText

/// CoreText-backed text measurement and splitting utility.
/// Used by CanvasStore's multi-page layout engine to determine exact text
/// heights and slice character ranges across pages.
enum TextSplitter {
    static let defaultFont: UIFont = .preferredFont(forTextStyle: .body)

    /// Measures the vertical height needed to render `text` wrapped to `width`.
    static func measureHeight(for text: String, width: CGFloat, font: UIFont = defaultFont) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return DesignSystem.minBlockHeight }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
        let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let fitSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRangeMake(0, attrString.length),
            nil,
            targetSize,
            nil
        )
        return max(ceil(fitSize.height), 24)
    }

    /// Determines how many characters of `text` can fit within a rectangle of size `width` x `maxHeight`.
    static func fittingLength(for text: String, width: CGFloat, maxHeight: CGFloat, font: UIFont = defaultFont) -> Int {
        guard !text.isEmpty, width > 0, maxHeight > 0 else { return 0 }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: maxHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attrString.length), path, nil)
        let visibleRange = CTFrameGetVisibleStringRange(frame)
        return visibleRange.length
    }
}
