import SwiftUI
import UIKit

/// A text view with no fixed height: every time its text (or the width
/// it's given) changes, it reports its own intrinsic content height via
/// `onHeightChange`, so the caller can grow the block's frame to match.
///
/// SwiftUI's native `TextEditor` doesn't expose intrinsic content size in
/// a way that plays well with a custom layout engine, so this is a thin
/// `UITextView` wrapper instead — `sizeThatFits` gives an exact answer.
///
/// The view is the text-input surface for the text element. Taps and
/// typing land here directly through UIKit's first-responder chain. The
/// delegate reports first-responder changes via `onFocusChange` so the
/// parent can keep the selection ring in sync without attaching a body
/// tap that would compete with the text view's own gestures.
///
/// Drag recognition (so the parent `ElementContainerView` can grab a
/// finger that starts moving on a text block and turn it into an
/// element-move drag) is delegated to SwiftUI's gesture system at the
/// parent level — the text view itself doesn't try to recognize pan
/// gestures, so it never fights with the parent's drag.
struct AutoGrowingTextView: UIViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var width: CGFloat
    var onFocusChange: (Bool) -> Void
    var onHeightChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.delegate = context.coordinator
        view.text = text
        view.isEditable = isEditable
        view.isUserInteractionEnabled = isEditable
        view.isSelectable = isEditable
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.isEditable = isEditable
        uiView.isUserInteractionEnabled = isEditable
        uiView.isSelectable = isEditable
        recalculateHeight(for: uiView)
    }

    /// Explicitly tells SwiftUI the exact size to give this view — a
    /// fixed width (so text wraps instead of running off edge-to-edge
    /// unbounded) and a height computed from that width.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let targetWidth = proposal.width ?? width
        let size = uiView.sizeThatFits(CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: targetWidth, height: max(size.height, 1))
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

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange(false)
        }
    }
}
