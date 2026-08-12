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
    /// When `true` (default), the wrapped `UITextView` calls
    /// `becomeFirstResponder()` as soon as `isEditable` becomes `true`
    /// — used by floating text elements so the keyboard appears the
    /// instant they're created. Set to `false` for surfaces that should
    /// only receive the keyboard after the user explicitly taps them
    /// (e.g. the page's full-body editor, which is editable from the
    /// moment writing mode opens but must not steal focus on entry).
    var becomesFirstResponderOnEdit: Bool = true
    var onHeightChange: (CGFloat) -> Void
    var onFocusDidBegin: () -> Void
    var onFocusDidEnd: () -> Void
    /// Called whenever the caret moves (typing, arrow keys, taps) with
    /// the caret's frame in the text view's own coordinate space. Used
    /// by the page-body editor to ask the canvas to keep the caret
    /// above the keyboard as the user types into long content.
    var onCaretRectChange: ((CGRect) -> Void)? = nil
    /// Hard cap on the text view's content height, in the same
    /// coordinate space as `width`. When non-nil, edits that would
    /// push the rendered text past this height are rejected (with a
    /// haptic + visual flash) so the content stays inside its
    /// container instead of overflowing and getting clipped. `nil`
    /// means no cap — the default for floating text elements, which
    /// grow their container to match their content.
    var maxHeight: CGFloat? = nil
    /// Called whenever the text view rejects a proposed edit because
    /// it would exceed `maxHeight`. Use this to surface user feedback
    /// (the wrapper already plays a haptic + flash; this is for
    /// additional UI like a toast).
    var onOverflowReject: (() -> Void)? = nil
    /// External focus control, used by surfaces where the owner (not
    /// the text view's own tap) decides when editing starts and stops
    /// (e.g. the page-body editor, which enters/exits editing when the
    /// user taps the paper). When nil (the default for floating text
    /// elements) focus is driven by `becomesFirstResponderOnEdit`.
    var isFocused: Bool? = nil

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
        // Asynchronously apply focus changes. Calling
        // `becomeFirstResponder()`/`resignFirstResponder()` synchronously
        // from `updateUIView` — especially while a mode-switch
        // `.transition`/`withAnimation` is still laying out the hierarchy —
        // re-enters UIKit's responder machinery mid-layout and can deadlock
        // the main thread. Doing it async makes focus feel identical but
        // never runs during layout.
        DispatchQueue.main.async {
            if let externallyFocused = isFocused {
                // External focus control (page-body editor): the owner
                // decides when editing starts/stops. Focusing here only
                // when editable, and resigning whenever the owner says
                // not-focused (this is what ends editing when the user
                // taps outside the editor).
                if externallyFocused && isEditable && !uiView.isFirstResponder {
                    uiView.becomeFirstResponder()
                } else if !externallyFocused && uiView.isFirstResponder {
                    uiView.resignFirstResponder()
                }
            } else {
                // Self-driven focus (floating text elements).
                if isEditable && becomesFirstResponderOnEdit && !uiView.isFirstResponder {
                    uiView.becomeFirstResponder()
                } else if !isEditable && uiView.isFirstResponder {
                    uiView.resignFirstResponder()
                }
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
        /// Haptic generator used when an edit is rejected for overflowing
        /// the configured `maxHeight`. Lazily created so it doesn't fire
        /// on every keystroke and stays ready for the next rejection.
        private lazy var overflowHaptic = UIImpactFeedbackGenerator(style: .light)

        init(_ parent: AutoGrowingTextView) {
            self.parent = parent
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Hard cap on content height: if the proposed edit would push
            // the rendered text past `maxHeight`, reject it so the text
            // stays inside its container instead of overflowing and
            // getting clipped. Allow deletions unconditionally (the user
            // must always be able to backspace to make room) and let
            // IME-composition edits through so the keyboard can keep
            // building the in-progress character without us rejecting
            // intermediate states.
            guard let maxHeight = parent.maxHeight, maxHeight > 0 else {
                return true
            }

            // Pure deletion: always allow.
            if text.isEmpty {
                return true
            }

            // IME composition (CJK / Korean): always allow. `markedTextRange`
            // is non-nil while the user is building a character; rejecting
            // here would make the IME un-usable.
            if textView.markedTextRange != nil {
                return true
            }

            // Compute the proposed text and measure it. We use a throwaway
            // `UITextView` configured the same way as the live one so the
            // answer is the same answer UIKit will give at the next
            // layout pass — cheaper than swapping text on the live view
            // and re-measuring.
            let nsCurrent = textView.text as NSString
            guard range.location <= nsCurrent.length,
                  range.location + range.length <= nsCurrent.length else {
                return true
            }
            let proposed = nsCurrent.replacingCharacters(in: range, with: text)
            let probe = UITextView()
            probe.font = textView.font
            probe.textContainerInset = textView.textContainerInset
            probe.textContainer.lineFragmentPadding = textView.textContainer.lineFragmentPadding
            probe.attributedText = NSAttributedString(
                string: proposed,
                attributes: [.font: textView.font ?? UIFont.preferredFont(forTextStyle: .body)]
            )
            probe.frame = CGRect(x: 0, y: 0, width: parent.width, height: .greatestFiniteMagnitude)
            let measured = probe.sizeThatFits(CGSize(
                width: parent.width,
                height: .greatestFiniteMagnitude
            )).height

            if measured > maxHeight {
                overflowHaptic.impactOccurred()
                parent.onOverflowReject?()
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.recalculateHeight(for: textView)
            reportCaret(for: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Fires on caret moves, arrow-key navigation, and tap-to-place
            // — all the moments the caret position that the canvas needs
            // for keyboard avoidance might have changed.
            reportCaret(for: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Report the caret BEFORE flipping focus so by the time
            // `bodyFocused` becomes true the keyboard-offset computation
            // in `WritingCanvasView` already has a caret rect to work
            // with. (Otherwise there's a one-tick window where the
            // canvas sees `bodyFocused == true` and `bodyCaretRect ==
            // nil` and produces an offset of 0 — which the user would
            // experience as the keyboard covering the editor for one
            // frame.)
            reportCaret(for: textView)
            parent.onFocusDidBegin()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // Match `textViewDidBeginEditing`'s order: clear dependent
            // state before flipping focus so observers never see a
            // half-transition (focused but stale rect).
            parent.onFocusDidEnd()
        }

        private func reportCaret(for textView: UITextView) {
            guard let callback = parent.onCaretRectChange else { return }
            let end = textView.selectedTextRange?.end ?? textView.beginningOfDocument
            let rect = textView.caretRect(for: end)
            // `caretRect(for:)` returns a rect in the text view's own
            // coordinate space; report it raw so callers can convert it
            // into the page / canvas space they need.
            callback(rect)
        }
    }
}