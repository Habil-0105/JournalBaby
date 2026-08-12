import Foundation
import PencilKit

/// A single slot in a page's z-order. Unlike a simple "3 types" enum, this
/// points at either a whole-page layer (`.textEditor`, `.scribble`) or one
/// **specific element instance** (`.element(id)`) — so two text blocks, or
/// two images, can each sit at a different depth instead of being locked
/// together as a single "elements" bucket. `Page.layerOrder` lists these
/// **front-to-back** (index 0 = topmost, drawn last). Because SwiftUI
/// hit-tests a ZStack from the topmost view down, this list doubles as the
/// tie-break order when two layers' interactive regions overlap — no
/// separate hit-testing logic is needed beyond rendering in this order.
///
/// The full inventory of what can appear on a page: the whole-page body
/// text editor, the whole-page scribble layer, and N individual elements —
/// which are `.text`, `.image`, **and `.audio`** (all three `ElementKind`
/// cases get their own slot; none of them are grouped).
///
/// `dateLabel`, the hint overlay, the overflow flash, and the delete pill
/// are NOT part of this list — they stay pinned at fixed positions in
/// `PageContentView`'s ZStack regardless of how these layers are ordered.
///
/// `CanvasStore` is responsible for keeping this list in sync with
/// `Page.elements`: every `addText` / `addImage` / `addAudio` inserts a new
/// `.element(id)` at the front (index 0 — matches the old "newest element
/// draws last / sits on top" behavior), and `remove(_:)` deletes the
/// matching `.element(id)` entry. Nothing else mutates `elements`, so this
/// invariant — `Set(layerOrder) == {.textEditor, .scribble} ∪
/// elements.map { .element($0.id) }` — always holds.
enum CanvasLayerRef: Hashable, Codable {
    case textEditor
    case scribble
    case element(UUID)
}

/// One page on the freeform canvas. Each page owns its own elements,
/// its own scribble layer, and its own document body — switching pages
/// swaps the whole visible state, the way flipping between sheets of
/// paper does, not the way scrolling one long page does.
struct Page: Identifiable, Equatable {
    let id: UUID
    var elements: [CanvasElement]
    var scribble: PKDrawing

    /// The full-page text body. Rendered as a `TextEditor` covering the
    /// paper underneath the floating elements, so each page can act as
    /// a document while still hosting positioned elements and
    /// PencilKit drawings on top.
    var bodyText: String

    /// When this page was created — printed on top of the paper in
    /// "dd MMMM yyyy" format. Stored per page so each sheet shows its
    /// own date (not a single shared "today").
    var createdAt: Date

    /// Front-to-back z-order of this page's reorderable layers: the two
    /// whole-page layers (text editor, scribble) plus one slot per
    /// individual element. Defaults to `[.textEditor, .scribble]` — a
    /// fresh page has no elements yet, and each element added afterwards
    /// is inserted on top by `CanvasStore`, reproducing the app's original
    /// "elements always draw above the page layers, newest on top" default
    /// without needing to special-case it here. Per-page (not global), so
    /// carousel neighbours and the current page never share or leak an
    /// order.
    var layerOrder: [CanvasLayerRef]

    init(
        id: UUID = UUID(),
        elements: [CanvasElement] = [],
        scribble: PKDrawing = PKDrawing(),
        bodyText: String = "",
        createdAt: Date = Date(),
        layerOrder: [CanvasLayerRef]? = nil
    ) {
        self.id = id
        self.elements = elements
        self.scribble = scribble
        self.bodyText = bodyText
        self.createdAt = createdAt
        // Default: any passed-in elements go on top (newest/last-passed
        // highest), then the two page layers — same convention CanvasStore
        // uses when adding elements one at a time. Callers that construct a
        // page with pre-existing elements (there are none in this codebase
        // today — pages are always built empty and grown via
        // CanvasStore.addText/addImage/addAudio) still get a valid,
        // in-sync order for free instead of a crash-prone mismatch.
        self.layerOrder = layerOrder ?? (elements.map { .element($0.id) } + [.textEditor, .scribble])
    }
}
