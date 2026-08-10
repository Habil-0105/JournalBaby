import Foundation
import CoreGraphics

enum ElementKind: String, Codable {
    case text
    case image
    case audio
    case drawing
}

/// A single block. Notice there's no `frame` or `position` here anymore —
/// only `width`/`height`. On-screen position is always *derived* by
/// `CanvasStore`'s flow-layout engine from a block's order in `elements`
/// plus its size, never stored. That's what makes "resizing one block
/// reflows the rest" automatic: change a size, the whole layout
/// recomputes, and overlap is structurally impossible.
struct CanvasElement: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ElementKind

    /// User-adjustable target width, clamped against the container width
    /// at layout time (so it stays valid even if the screen resizes).
    var width: CGFloat

    /// User-adjustable height for image/audio/drawing blocks. Ignored
    /// for `.text` — its height is measured from its content instead
    /// (see `CanvasStore.textHeights`), so there is no fixed height to
    /// store for it.
    var height: CGFloat

    var text: String?
    var imageFileName: String?
    var audioFileName: String?
    var audioDuration: TimeInterval?

    init(
        id: UUID = UUID(),
        kind: ElementKind,
        width: CGFloat,
        height: CGFloat,
        text: String? = nil,
        imageFileName: String? = nil,
        audioFileName: String? = nil,
        audioDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.width = width
        self.height = height
        self.text = text
        self.imageFileName = imageFileName
        self.audioFileName = audioFileName
        self.audioDuration = audioDuration
    }
}

/// Represents a block slice laid out on a specific page.
struct PlacedElement: Identifiable, Equatable {
    let id: String
    let canonicalID: UUID
    let kind: ElementKind
    let frame: CGRect
    let textSubstring: String?
    let isSplitText: Bool
    let sliceIndex: Int
}

/// Represents a single book page layout containing placed block slices.
struct PageLayout: Identifiable, Equatable {
    let id: Int
    let pageIndex: Int
    let elements: [PlacedElement]
}

/// Represents an open physical book spread containing 1 page (iPhone) or 2 pages (iPad).
struct BookSpread: Identifiable, Equatable {
    let id: Int
    let spreadIndex: Int
    let leftPage: PageLayout?
    let rightPage: PageLayout?
}

