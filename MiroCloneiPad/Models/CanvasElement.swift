import Foundation
import CoreGraphics

enum ElementKind: String, Codable {
    case text
    case image
    case audio
}

/// A single freeform canvas object. Unlike the old flow-layout version
/// there is no notion of "reflow" here: every element owns its own
/// `position` (top-left, in the canvas content coordinate space) and its
/// own size. The canvas renders it at `position`, hit-tests it at
/// `position`, and dragging writes back to `position` directly — one
/// source of truth, so an element never moves because a neighbor changed.
///
/// Position is deliberately a stored value: elements are independent
/// 2D objects (Miro/Figma style), not blocks of a document flow.
struct CanvasElement: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ElementKind

    /// Top-left of the element on the canvas. The single source of truth —
    /// rendering, hit testing, and the drag gesture all read and write it.
    var position: CGPoint

    /// User-adjustable width. For `.text` this is the wrap width; its
    /// height is measured from content via `CanvasStore.setTextHeight`.
    var width: CGFloat

    /// User-adjustable height for image/audio. For `.text` this is the
    /// measured content height, kept in sync by `AutoGrowingTextView`.
    var height: CGFloat

    var text: String?
    var imageFileName: String?
    var audioFileName: String?
    var audioDuration: TimeInterval?

    init(
        id: UUID = UUID(),
        kind: ElementKind,
        position: CGPoint = .zero,
        width: CGFloat,
        height: CGFloat,
        text: String? = nil,
        imageFileName: String? = nil,
        audioFileName: String? = nil,
        audioDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.position = position
        self.width = width
        self.height = height
        self.text = text
        self.imageFileName = imageFileName
        self.audioFileName = audioFileName
        self.audioDuration = audioDuration
    }

    /// The element's bounds on the canvas — used for rendering and hit tests.
    var frame: CGRect {
        CGRect(origin: position, size: CGSize(width: width, height: height))
    }
}