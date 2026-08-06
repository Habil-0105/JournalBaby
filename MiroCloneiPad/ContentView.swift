import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var store = CanvasStore()
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showAudioSheet = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let containerWidth = max(geo.size.width - DesignSystem.pagePadding * 2, 0)

                ScrollView(.vertical, showsIndicators: true) {
                    PageView(store: store, pageWidth: geo.size.width, minHeight: geo.size.height)
                }
                .background(Color(.systemGroupedBackground))
                .onAppear { store.updateContainerWidth(containerWidth) }
                .onChange(of: geo.size) { _, _ in
                    store.updateContainerWidth(containerWidth)
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
