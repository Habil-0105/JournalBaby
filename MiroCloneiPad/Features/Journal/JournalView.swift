import SwiftUI
import PhotosUI

/// Root screen of the Journal feature. The app has two visual modes:
/// **carousel mode** (preview / browse) and **writing mode** (zoomed in,
/// only the current page visible). `JournalView.body` switches between
/// `PageCarouselView` and `WritingCanvasView` based on
/// `store.writingMode`. Enter writing mode by tapping the Scribble
/// toolbar button or pinching in on the canvas; exit by pinching out.
struct JournalView: View {
    @StateObject private var store = CanvasStore()
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showAudioSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if store.writingMode {
                    WritingCanvasView(store: store)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    PageCarouselView(store: store)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        enterWritingModeIfNeeded()
                        store.addText()
                    } label: {
                        Label("Add Text", systemImage: "textformat")
                    }

                    PhotosPicker(selection: $photosPickerItem, matching: .images) {
                        Label("Add Image", systemImage: "photo")
                    }

                    Button {
                        enterWritingModeIfNeeded()
                        showAudioSheet = true
                    } label: {
                        Label("Add Audio", systemImage: "mic")
                    }

                    scribbleToolbarButton
                }
            }
            .sheet(isPresented: $showAudioSheet) {
                AudioRecorderSheet(store: store)
            }
            .onChange(of: photosPickerItem) { _, newItem in
                guard newItem != nil else { return }
                // Picked a photo: enter writing mode first so the new
                // image lands on the writing canvas, then load the bytes
                // and add the element.
                enterWritingModeIfNeeded()
                Task {
                    if let newItem, let data = try? await newItem.loadTransferable(type: Data.self) {
                        store.addImage(data: data)
                    }
                    photosPickerItem = nil
                }
            }
        }
    }

    /// The Scribble toolbar button is the entry point into writing mode
    /// in carousel mode and the exit point while writing. The icon and
    /// label flip between the two so the affordance is always visible.
    @ViewBuilder
    private var scribbleToolbarButton: some View {
        if store.writingMode {
            Button {
                store.exitWritingMode()
            } label: {
                Label("Exit Writing", systemImage: "pencil.tip.crop.circle.badge.minus")
            }
        } else {
            Button {
                enterWritingModeIfNeeded()
            } label: {
                Label("Scribble", systemImage: "scribble")
            }
        }
    }

    /// Any toolbar tool tap in carousel mode is also a trigger to enter
    /// writing mode — the new element / picker / audio sheet should land
    /// on the writing canvas, not the carousel preview. No-op in writing
    /// mode.
    private func enterWritingModeIfNeeded() {
        guard !store.writingMode else { return }
        store.enterWritingMode()
    }
}

#Preview {
    JournalView()
}
