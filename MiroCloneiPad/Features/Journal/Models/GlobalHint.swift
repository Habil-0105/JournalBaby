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

    /// The default question shown when no emotion is selected — the hint's
    /// general context.
    static let generalQuestion =
        "Even on hard days, there's a lesson. What's yours today?"

    /// The general prompt pool (no emotion selected) — the refresh button
    /// cycles through these.
    static let generalQuestions: [String] = [
        generalQuestion,
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

    /// Emotion → question pools. Extend any array to add more questions the
    /// refresh button cycles through for that emotion.
    static let questionsByEmotion: [Emotion: [String]] = [
        .happy: [
            "What made you smile today?",
            "What's the best part of your day so far?",
            "What moment today would you want to relive?"
        ],
        .calm: [
            "What helped you feel at peace today?",
            "Where did you find a quiet moment today?"
        ],
        .excited: [
            "What are you looking forward to?",
            "What's making your heart race today — in a good way?"
        ],
        .grateful: [
            "What are you grateful for today?",
            "What small thing are you thankful for right now?"
        ],
        .sad: [
            "What's been weighing on your heart today?",
            "What would help you feel even a little lighter?"
        ],
        .angry: [
            "What made you feel frustrated today?",
            "What's one way you could let that frustration out?"
        ],
        .anxious: [
            "What's been on your mind lately?",
            "What's one small thing you can control right now?"
        ],
        .tired: [
            "What has been draining your energy today?",
            "What would give you a real rest tonight?"
        ],
        .lonely: [
            "Who do you wish you were closer to today?",
            "What kind of connection would feel good right now?"
        ],
        .overwhelmed: [
            "What's one thing you can let go of today?",
            "What's the smallest next step you could take?"
        ]
    ]

    /// The pool of questions for the current emotion context (general pool
    /// when no emotion is selected).
    static func questions(for emotion: Emotion?) -> [String] {
        guard let emotion,
              let questions = questionsByEmotion[emotion],
              !questions.isEmpty else {
            return generalQuestions
        }
        return questions
    }

    /// The question a hint should start on for the given emotion context.
    static func initialQuestion(for emotion: Emotion?) -> String {
        questions(for: emotion)[0]
    }

    /// Cycles to the next prompt in `pool` without immediately repeating the
    /// current one (as long as the pool has more than one entry).
    static func nextPrompt(after current: String, in pool: [String]) -> String {
        guard !pool.isEmpty else { return current }
        guard let index = pool.firstIndex(of: current) else {
            return pool[0]
        }
        return pool[(index + 1) % pool.count]
    }
}