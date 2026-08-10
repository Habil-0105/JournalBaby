import SwiftUI
import PhotosUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var store = CanvasStore()
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showAudioSheet = false

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
                    totalPages: totalPages
                )
                .background(Color(.systemGroupedBackground))
                .onChange(of: pages.count) { _, newCount in
                    if store.currentPageIndex >= newCount {
                        store.currentPageIndex = max(newCount - 1, 0)
                        print("111")
                    } else {
                        print("222")
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
