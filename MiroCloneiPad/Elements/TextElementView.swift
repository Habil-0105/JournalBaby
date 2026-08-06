import SwiftUI

struct TextElementView: View {
    @ObservedObject var store: CanvasStore
    var element: CanvasElement
    /// Current width this block has been laid out at — needed to
    /// measure wrapped text height correctly.
    var width: CGFloat
    var isActive: Bool

    private var textBinding: Binding<String> {
        Binding(
            get: { element.text ?? "" },
            set: { newValue in
                var updated = element
                updated.text = newValue
                store.update(updated)
            }
        )
    }

    var body: some View {
        AutoGrowingTextView(
            text: textBinding,
            isEditable: isActive,
            width: max(width - DesignSystem.blockContentPadding * 2, 1),
            onHeightChange: { measured in
                store.setTextHeight(element.id, height: measured)
            }
        )
        .padding(DesignSystem.blockContentPadding)
        .overlay(alignment: .topLeading) {
            if (element.text ?? "").isEmpty {
                Text("Type here…")
                    .foregroundStyle(.secondary)
                    .padding(DesignSystem.blockContentPadding)
                    .allowsHitTesting(false)
            }
        }
    }
}
