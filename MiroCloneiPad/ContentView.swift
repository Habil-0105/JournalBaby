import SwiftUI
import PhotosUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var store = CanvasStore()
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showAudioSheet = false
    /// True while the Scribble tool is active. While on, every
    /// `PageView` renders its page-level PencilKit canvas with
    /// `isUserInteractionEnabled = true`, so taps on the page draw
    /// strokes. While off, the canvas is a non-tap-through overlay
    /// and normal element gestures work.
    @State private var scribbleMode: Bool = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let singlePageWidth = geo.size.width
                let pages = store.layoutPages(pageWidth: singlePageWidth, pageHeight: geo.size.height)
                let spreads = store.layoutSpreads(pageWidth: geo.size.width, pageHeight: geo.size.height)
                let totalPages = max(pages.count, 1)

                BookPageCurlView(
                    store: store,
                    spreads: spreads,
                    pageWidth: geo.size.width,
                    pageHeight: geo.size.height,
                    totalPages: totalPages,
                    scribbleMode: scribbleMode
                )
                .background(Color(.systemGroupedBackground))
                .onChange(of: pages.count) { _, newCount in
                    if store.currentPageIndex >= newCount {
                        store.currentPageIndex = max(newCount - 1, 0)
                    }
                }
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        store.addText()
                    } label: {
                        Label("Add Text", systemImage: "textformat")
                    }

                    PhotosPicker(selection: $photosPickerItem, matching: .images) {
                        Label("Add Image", systemImage: "photo")
                    }

                    Button {
                        showAudioSheet = true
                    } label: {
                        Label("Add Audio", systemImage: "mic")
                    }

                    Button {
                        scribbleMode.toggle()
                    } label: {
                        Label(
                            scribbleMode ? "Done Drawing" : "Scribble",
                            systemImage: scribbleMode ? "checkmark.circle.fill" : "scribble"
                        )
                    }
                    .tint(scribbleMode ? .accentColor : nil)
                }
            }
            .sheet(isPresented: $showAudioSheet) {
                AudioRecorderSheet(store: store)
            }
            .onChange(of: photosPickerItem) { _, newItem in
                Task {
                    if let newItem, let data = try? await newItem.loadTransferable(type: Data.self) {
                        store.addImage(data: data)
                    }
                    photosPickerItem = nil
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
