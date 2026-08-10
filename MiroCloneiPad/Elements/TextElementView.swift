import SwiftUI

struct TextElementView: View {
    @ObservedObject var store: CanvasStore
    var element: CanvasElement
    var placed: PlacedElement
    var width: CGFloat
    var slices: [String]
    /// Called when the underlying `UITextView` becomes first responder
    /// (`focused = true`) or resigns first responder (`focused = false`).
    /// The element container uses this to keep the selection ring in
    /// sync with the user's actual focus, without attaching a body tap
    /// that would compete with the text view's first-responder chain.
    var onFocusChange: (Bool) -> Void

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
            isEditable: true,
            width: contentWidth,
            onFocusChange: onFocusChange,
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
