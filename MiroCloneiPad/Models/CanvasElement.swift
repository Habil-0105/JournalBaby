import Foundation
import CoreGraphics

/// The kinds of element blocks that live on a journal page.
///
/// Note that hand-drawn strokes (the "Scribble" tool) are NOT an element
/// kind. Strokes belong to the page itself, not to a movable/resizable
/// block — see `CanvasStore.pageDrawings` for the page-level drawing
/// layer.
enum ElementKind: String, Codable {
    case text
    case image
    case audio
}

/// A single block. Position is **stored**, not derived — the free-canvas
/// model. `x`/`y` are the top-left in page coordinates (the coordinate
/// space the page's `coordinateSpace(name: "page")` exposes). `zIndex`
/// is the relative stacking order between blocks of the same page
/// (later-created elements default to a higher `zIndex`, so newer
/// blocks appear on top). Width/height remain user-resizable; size and
/// position are independent — moving one block does not move any other.
struct CanvasElement: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ElementKind

    /// Top-left X in page coordinates. 0 is the page's left edge after
    /// its outer padding.
    var x: CGFloat

    /// Top-left Y in page coordinates.
    var y: CGFloat

    /// Stacking order. Higher = drawn on top. The selected block is
    /// temporarily promoted at render time without mutating this value
    /// in the store.
    var zIndex: Int

    /// User-resizable width. Free-form canvas: only the `minBlockWidth`
    /// floor applies — there is no upper bound imposed by the container.
    var width: CGFloat

    /// User-resizable height for image/audio/drawing blocks. Ignored
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
        x: CGFloat = 0,
        y: CGFloat = 0,
        zIndex: Int = 0,
        width: CGFloat,
        height: CGFloat,
        text: String? = nil,
        imageFileName: String? = nil,
        audioFileName: String? = nil,
        audioDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.zIndex = zIndex
        self.width = width
        self.height = height
        self.text = text
        self.imageFileName = imageFileName
        self.audioFileName = audioFileName
        self.audioDuration = audioDuration
    }
}

/// Represents a block slice laid out on a specific page.
///
/// `frame` now reflects the element's **stored** position, not a
/// derived row-wrap position. The size is still driven by the canonical
/// `CanvasElement.width/height` for non-text blocks and by
/// `TextSplitter` for text slices (text-slicing across pages is the one
/// layout-y thing that survives; position does not).
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

