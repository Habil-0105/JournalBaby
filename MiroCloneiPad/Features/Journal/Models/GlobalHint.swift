import CoreGraphics

/// The journal's global hint: a single note shared by every page, styled
/// like a lightweight handwritten post-it.
///
/// This type holds only the *static* configuration — the card geometry, the
/// default position, and the pool of prompt strings. The actual state (which
/// hint is showing and where it sits) lives at the journal level of
/// `CanvasStore` (`hintText` / `hintPosition`), so every page renders the
/// same hint at the same position and the store is the single source of
/// truth. There is deliberately no hint data on `Page`.
enum GlobalHint {
    /// The card's starting size (top-leading origin). The current size is
    /// stored at the journal level (`CanvasStore.hintSize`) so every page
    /// renders the same resized hint; this is just the initial value.
    static let defaultSize = CGSize(width: 280, height: 120)

    /// Clamps for the user-driven resize (min / max).
    static let minSize = CGSize(width: 200, height: 80)
    static let maxSize = CGSize(width: 420, height: 260)

    /// How far the circular refresh button extends past the card's top and
    /// right edges. `CanvasStore.moveHint` reserves this so the *whole* hint
    /// (refresh button included) stays inside the paper.
    static let buttonOverhang = CGSize(width: 14, height: 14)

    /// Where the hint starts (top-leading). Fits even the narrowest
    /// supported canvas (iOS 17 devices are all >= 375pt wide, giving a
    /// writing canvas of >= ~318pt); the user can drag it anywhere, clamped
    /// to the paper.
    static let defaultPosition = CGPoint(x: 20, y: 200)

    /// The pool of prompts the refresh button cycles through. A static,
    /// local collection — no external AI service.
    static let prompts: [String] = [
        "Even on hard days, there's a lesson. What's yours today?",
        "What made you smile today — even for a second?",
        "Name one small thing you're proud of today.",
        "What's one kind thing you did for yourself this week?",
        "What feels heavy right now? What's one tiny lift you could try?",
        "What moment from today would you want to remember?",
        "What's one truth today taught you about yourself?",
        "If today were a chapter title, what would it be?",
        "What are you quietly looking forward to?",
        "What are you grateful for right now, however small?"
    ]

    /// Cycles to the next prompt without immediately repeating the current
    /// one (as long as there is more than one prompt).
    static func nextPrompt(after current: String) -> String {
        guard !prompts.isEmpty else { return current }
        guard let index = prompts.firstIndex(of: current) else {
            return prompts[0]
        }
        return prompts[(index + 1) % prompts.count]
    }
}