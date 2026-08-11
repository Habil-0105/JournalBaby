import SwiftUI
import UIKit

/// A text view with no fixed height: every time its text (or the width
/// it's given) changes, it reports its own intrinsic content height via
/// `onHeightChange`, so the caller can grow the element's frame to match.
///
/// SwiftUI's native `TextEditor` doesn't expose intrinsic content size in
/// a way that plays well with a freeform canvas, so this is a thin
/// `UITextView` wrapper instead — `sizeThatFits` gives an exact answer.
///
/// Editing is opt-in: the view is only editable when focused, and it
/// reports focus transitions back so the store knows whether dragging the
/// text block should move it or let the caret handle the touch.
struct AutoGrowingTextView: UIViewRepresentable {
    @Binding var text: String
    /// Only interactive/editable when it's focused (double-tap / explicit
    /// edit). Reflects `CanvasStore.focusedTextID`.
    var isEditable: Bool
    var width: CGFloat
    var onHeightChange: (CGFloat) -> Void
    var onFocusDidBegin: () -> Void
    var onFocusDidEnd: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        // Wrapping width tracks the view's own bounds width — this only
        // does anything useful once that bounds width is actually fixed,
        // which is what `sizeThatFits(_:uiView:context:)` below does.
        view.textContainer.widthTracksTextView = true
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
        // Defer responder changes to the next runloop tick. Calling
        // `becomeFirstResponder()` synchronously from `updateUIView` —
        // especially while a mode-switch `.transition`/`withAnimation` is
        // still laying out the hierarchy (adding a text block from the
        // carousel toolbar auto-focuses it) — re-enters UIKit's responder
        // machinery mid-layout and can deadlock the main thread. Doing it
        // async makes focus feel identical but never runs during layout.
        DispatchQueue.main.async {
            if isEditable && !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            } else if !isEditable && uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
        recalculateHeight(for: uiView)
    }

    /// Explicitly tells SwiftUI the exact size to give this view — a
    /// fixed width (so text wraps instead of running off edge-to-edge
    /// unbounded) and a height computed from that width. Without this,
    /// a `UIViewRepresentable` wrapping a non-scrolling `UITextView` has
    /// no reliable intrinsic width to lay out against, so wrapping never
    /// kicks in and the text view just grows however wide its content
    /// wants — which is exactly the "types past the block" bug.
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
            parent.onFocusDidBegin()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusDidEnd()
        }
    }
}