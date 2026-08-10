import SwiftUI
import PencilKit
import UIKit

/// The touch surface shown while Draw mode is active. It covers the whole
/// board and converts finger/pencil input straight into strokes at the
/// exact canvas coordinates — there's no element, frame, or handle involved.
///
/// A drag becomes a stroke; a tap (no meaningful movement) is treated as a
/// selection tap: if it lands on an element, that element is selected and
/// Draw mode exits automatically.
struct DrawInputLayer: View {
    @ObservedObject var store: CanvasStore
    /// Current frames of all elements in canvas coordinates.
    var elementFrames: [(id: UUID, frame: CGRect)]

    @State private var points: [CGPoint] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            if points.count >= 2 {
                Path { path in
                    path.move(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    Color(uiColor: .label),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(drawGesture)
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                points.append(value.location)
                if points.count > 3000 {
                    points.removeFirst(points.count - 3000)
                }
            }
            .onEnded { value in
                defer { points = [] }
                guard let first = points.first else { return }

                // A tap: if it lands on an element, select it (which also
                // turns Draw mode off); otherwise do nothing — no dot.
                let isTap = points.count <= 2
                    || hypot(value.location.x - first.x, value.location.y - first.y) < 10

                if isTap {
                    if let hit = elementFrames.first(where: { $0.frame.contains(value.location) }) {
                        store.select(hit.id)
                    }
                    return
                }

                if let stroke = PKDrawing.penStroke(from: points) {
                    store.appendStroke(stroke)
                }
            }
    }
}

extension PKDrawing {
    /// Builds a pen stroke from raw canvas-space points. Points must be in
    /// the board's coordinate space — the stroke is committed at exactly
    /// those coordinates.
    static func penStroke(from points: [CGPoint], width: CGFloat = 4) -> PKStroke? {
        guard points.count >= 2 else { return nil }
        let ink = PKInk(.pen, color: .label)
        let strokePoints = points.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: Double(index) * 0.01,
                size: CGSize(width: width, height: width),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: 0
            )
        }
        let path = PKStrokePath(controlPoints: strokePoints, creationDate: Date())
        return PKStroke(ink: ink, path: path, transform: .identity, mask: nil)
    }
}