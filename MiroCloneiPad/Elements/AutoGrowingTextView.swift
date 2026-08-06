import SwiftUI
import UIKit

/// A text view with no fixed height: every time its text (or the width
/// it's given) changes, it reports its own intrinsic content height via
/// `onHeightChange`, so the caller can grow the block's frame to match.
///
/// SwiftUI's native `TextEditor` doesn't expose intrinsic content size in
/// a way that plays well with a custom layout engine, so this is a thin
/// `UITextView` wrapper instead — `sizeThatFits` gives an exact answer.
struct AutoGrowingTextView: UIViewRepresentable {
    @Binding var text: String
    /// Only interactive/editable when its block is selected — mirrors
    /// `DrawingElementView`'s "select first, then interact" pattern so
    /// tapping the block to select it doesn't get swallowed by the text
    /// view's own touch handling.
    var isEditable: Bool
    var width: CGFloat
    var onHeightChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.text = text
        view.isEditable = isEditable
        view.isUserInteractionEnabled = isEditable
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.isEditable = isEditable
        uiView.isUserInteractionEnabled = isEditable
        recalculateHeight(for: uiView)
    }

    private func recalculateHeight(for uiView: UITextView) {
        guard width > 0 else { return }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        DispatchQueue.main.async {
            onHeightChange(size.height)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoGrowingTextView
        init(_ parent: AutoGrowingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.recalculateHeight(for: textView)
        }
    }
}
