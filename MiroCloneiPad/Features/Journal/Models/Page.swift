import Foundation
import PencilKit

/// One page on the freeform canvas. Each page owns its own elements and
/// its own scribble layer — switching pages swaps the whole visible
/// state, the way flipping between sheets of paper does, not the way
/// scrolling one long page does.
struct Page: Identifiable, Equatable {
    let id: UUID
    var elements: [CanvasElement]
    var scribble: PKDrawing

    /// When this page was created — printed on top of the paper in
    /// "dd MMMM yyyy" format. Stored per page so each sheet shows its
    /// own date (not a single shared "today").
    var createdAt: Date

    init(
        id: UUID = UUID(),
        elements: [CanvasElement] = [],
        scribble: PKDrawing = PKDrawing(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.elements = elements
        self.scribble = scribble
        self.createdAt = createdAt
    }
}
