import SwiftUI

struct ImageElementView: View {
    @ObservedObject var store: CanvasStore
    var element: CanvasElement

    var body: some View {
        Group {
            if let fileName = element.imageFileName,
               let uiImage = UIImage(contentsOfFile: store.imagesURL.appendingPathComponent(fileName).path) {
                Image(uiImage: uiImage)
                    .resizable()
            } else {
                Color.gray.opacity(0.2)
                    .overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
