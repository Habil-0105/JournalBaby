import SwiftUI

/// Renders a whole text element (one element — no page slicing anymore).
/// Its height is measured by `AutoGrowingTextView` and stored back into
/// `element.height`, and tapping into the text / double-tapping the block
/// focuses it for editing.
struct TextElementView: View {
    @ObservedObject var store: CanvasStore
    var element: CanvasElement
    var width: CGFloat
    var isFocused: Bool

    private var textBinding: Binding<String> {
        Binding(
            get: { element.text ?? "" },
            set: { newValue in
                store.updateElementText(element.id, text: newValue)
            }
        )
    }

    var body: some View {
        let contentWidth = max(width - DesignSystem.blockContentPadding * 2, 1)

        AutoGrowingTextView(
            text: textBinding,
            isEditable: isFocused,
            width: contentWidth,
            onHeightChange: { measured in
                store.setTextHeight(element.id, height: measured)
            },
            onFocusDidBegin: {
                store.focusText(element.id)
            },
            onFocusDidEnd: {
                store.clearTextFocus(element.id)
            }
        )
        .frame(width: contentWidth, alignment: .topLeading)
        .padding(DesignSystem.blockContentPadding)
        .overlay(alignment: .topLeading) {
            if element.text?.isEmpty != false {
                Text("Type here…")
                    .foregroundStyle(.secondary)
                    .padding(DesignSystem.blockContentPadding)
                    .allowsHitTesting(false)
            }
        }
    }
}