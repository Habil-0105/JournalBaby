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

                    hintToolbarButton

                    if store.writingMode {
                        LayerOrderToolbarButton(store: store)
                    }

                    if store.writingMode {
                        Button {
                            store.exitWritingMode()
                        } label: {
                            Label("Exit Writing", systemImage: "pencil.tip.crop.circle.badge.minus")
                        }
                    }
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

    /// The Scribble toolbar button. In carousel mode it enters writing mode
    /// AND arms drawing (that's what "Scribble" means — draw now). In writing
    /// mode it toggles drawing on/off: drawing is opt-in and never engaged
    /// automatically when entering the mode, so this button is the explicit
    /// "active drawing tool" selector. Exiting writing mode is a separate,
    /// always-present button so the user is never left without an exit.
    @ViewBuilder
    private var scribbleToolbarButton: some View {
        if store.writingMode {
            Button {
                if store.drawMode {
                    store.disableDrawing()
                } else {
                    store.enableDrawing()
                }
            } label: {
                Label(
                    store.drawMode ? "Hide Scribble" : "Scribble",
                    systemImage: "scribble"
                )
            }
        } else {
            Button {
                enterWritingModeIfNeeded()
                store.enableDrawing()
            } label: {
                Label("Scribble", systemImage: "scribble")
            }
        }
    }

    /// The hint-visibility toggle. Only shown in writing mode — in carousel
    /// mode the hint isn't rendered, so there's nothing to control. Follows
    /// the same on/off indicator convention as the Scribble button: filled
    /// icon + accent tint while the hint is visible, outline + secondary
    /// while it's dismissed. Toggles the store's temporary `hintVisible`
    /// state; it resets to visible on the next writing session.
    @ViewBuilder
    private var hintToolbarButton: some View {
        if store.writingMode {
            Button {
                store.hintVisible.toggle()
            } label: {
                Label(
                    store.hintVisible ? "Hide Hint" : "Show Hint",
                    systemImage: store.hintVisible ? "lightbulb.fill" : "lightbulb"
                )
            }
            .tint(store.hintVisible ? Color.accentColor : Color.secondary)
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
