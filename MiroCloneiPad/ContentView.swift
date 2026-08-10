import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var store = CanvasStore()
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showAudioSheet = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                FreeformCanvasView(store: store, size: geo.size)
                    .background(Color(.systemGroupedBackground))
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
                        store.toggleDrawMode()
                    } label: {
                        Label(
                            store.drawMode ? "Scribble On" : "Scribble",
                            systemImage: store.drawMode ? "pencil.tip" : "scribble"
                        )
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