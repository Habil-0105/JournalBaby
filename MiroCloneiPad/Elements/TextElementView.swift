import SwiftUI

struct TextElementView: View {
    @ObservedObject var store: CanvasStore
    var element: CanvasElement
    var placed: PlacedElement
    var width: CGFloat
    var isActive: Bool
    var slices: [String]

    private var textBinding: Binding<String> {
        Binding(
            get: { placed.textSubstring ?? element.text ?? "" },
            set: { newValue in
                store.updateTextSlice(
                    canonicalID: element.id,
                    sliceIndex: placed.sliceIndex,
                    newText: newValue,
                    slices: slices
                )
            }
        )
    }

    var body: some View {
        let contentWidth = max(width - DesignSystem.blockContentPadding * 2, 1)
        let textValue = textBinding.wrappedValue

        AutoGrowingTextView(
            text: textBinding,
            isEditable: isActive,
            width: contentWidth,
            onHeightChange: { measured in
                store.setTextHeight(element.id, height: measured)
            }
        )
        .frame(width: contentWidth, alignment: .topLeading)
        .padding(DesignSystem.blockContentPadding)
        .overlay(alignment: .topLeading) {
            if textValue.isEmpty && placed.sliceIndex == 0 {
                Text("Type here…")
                    .foregroundStyle(.secondary)
                    .padding(DesignSystem.blockContentPadding)
                    .allowsHitTesting(false)
            }
        }
    }
}
