import SwiftUI

/// The Global Emotion Stamp — the carousel-only UI for the journal's single
/// global emotion. It is a physical-journal-stamp representation of
/// `CanvasStore.globalEmotion`: an empty dashed stamp with a "+" when no
/// emotion is chosen, or the emoji + label when one is. Tapping it opens the
/// emotion picker sheet.
///
/// It renders inside `PageCarouselView`'s own coordinate space (position and
/// scale passed in by the carousel), so it never floats in screen space and
/// scales/repositions together with the carousel. Only its own small frame
/// is hit-testable — the carousel's swipe / pinch gestures keep working
/// everywhere else.
struct EmotionStampView: View {
    @ObservedObject var store: CanvasStore
    /// The stamp's display size, computed by the carousel from the available
    /// space to the right of the current paper.
    let size: CGSize

    @State private var showEmotionPicker = false

    var body: some View {
        Button {
            showEmotionPicker = true
        } label: {
            stampLabel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(width: size.width, height: size.height)
        .sheet(isPresented: $showEmotionPicker) {
            EmotionPickerSheet(store: store)
        }
        .accessibilityLabel(
            store.globalEmotion.map { "Emotion: \($0.label)" } ?? "Add an emotion"
        )
    }

    // MARK: - Stamp visuals

    @ViewBuilder
    private var stampLabel: some View {
        if let emotion = store.globalEmotion {
            filledStamp(emotion)
        } else {
            emptyStamp
        }
    }

    /// No emotion — a dashed placeholder stamp with a "+".
    private var emptyStamp: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(Color(red: 1.0, green: 0.97, blue: 0.88).opacity(0.55))
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .strokeBorder(
                    Color(red: 0.62, green: 0.48, blue: 0.22).opacity(0.5),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )

            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .medium))
                Text("How do\nyou feel?")
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(.secondary)
        }
    }

    /// An emotion is selected — emoji + label inside a double-lined
    /// rubber-stamp border.
    private func filledStamp(_ emotion: Emotion) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(Color(red: 1.0, green: 0.97, blue: 0.88))
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(Color(red: 0.62, green: 0.48, blue: 0.22).opacity(0.45), lineWidth: 1.5)
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius - 5)
                .stroke(Color(red: 0.62, green: 0.48, blue: 0.22).opacity(0.45), lineWidth: 1.5)
                .padding(4)

            VStack(spacing: 6) {
                Text(emotion.emoji)
                    .font(.system(size: 34))
                Text(emotion.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.35, green: 0.28, blue: 0.15))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6)
        }
    }
}

/// The emotion selection sheet. Lists every emotion in a grid; tapping one
/// sets the journal's global emotion (updating the stamp + the global hint's
/// question immediately) and dismisses. A "Clear" button removes the emotion.
struct EmotionPickerSheet: View {
    @ObservedObject var store: CanvasStore
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Emotion.allCases) { emotion in
                        emotionCell(emotion)
                    }
                }
                .padding(20)
            }
            .navigationTitle("How do you feel?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if store.globalEmotion != nil {
                        Button("Clear") {
                            store.setEmotion(nil)
                            dismiss()
                        }
                    }
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func emotionCell(_ emotion: Emotion) -> some View {
        let isSelected = store.globalEmotion == emotion
        return Button {
            store.setEmotion(emotion)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                Text(emotion.emoji)
                    .font(.system(size: 36))
                Text(emotion.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}