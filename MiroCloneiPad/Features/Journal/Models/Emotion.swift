import Foundation

/// The journal's global emotion. There is exactly ONE per journal — it is
/// not associated with any individual page, and switching pages never
/// changes it. This is a pure value type (String-backed, `CaseIterable`,
/// `Hashable`, `Equatable`) so it can be persisted later without a rewrite.
enum Emotion: String, CaseIterable, Identifiable {
    case happy
    case calm
    case excited
    case grateful
    case sad
    case angry
    case anxious
    case tired
    case lonely
    case overwhelmed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .happy: "Happy"
        case .calm: "Calm"
        case .excited: "Excited"
        case .grateful: "Grateful"
        case .sad: "Sad"
        case .angry: "Angry"
        case .anxious: "Anxious"
        case .tired: "Tired"
        case .lonely: "Lonely"
        case .overwhelmed: "Overwhelmed"
        }
    }

    var emoji: String {
        switch self {
        case .happy: "😊"
        case .calm: "😌"
        case .excited: "🤩"
        case .grateful: "🙏"
        case .sad: "😔"
        case .angry: "😠"
        case .anxious: "😰"
        case .tired: "😴"
        case .lonely: "🥺"
        case .overwhelmed: "😵"
        }
    }
}