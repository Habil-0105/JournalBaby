import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var store = CanvasStore()
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showAudioSheet = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let pages = store.layoutPages(pageWidth: geo.size.width, pageHeight: geo.size.height)
                let pageCount = max(pages.count, 1)

                BookPageCurlView(
                    store: store,
                    pages: pages,
                    pageWidth: geo.size.width,
                    pageHeight: geo.size.height
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
                        store.addDrawing()
                    } label: {
                        Label("Add Drawing", systemImage: "scribble")
                    }
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
