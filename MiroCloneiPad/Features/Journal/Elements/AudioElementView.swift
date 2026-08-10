import SwiftUI
import Combine
import AVFoundation

struct AudioElementView: View {
    @ObservedObject var store: CanvasStore
    var element: CanvasElement

    @StateObject private var player = AudioPlaybackManager()

    var body: some View {
        VStack(spacing: 6) {
            Button {
                guard let fileName = element.audioFileName else { return }
                let url = store.audioURL.appendingPathComponent(fileName)
                player.toggle(url: url)
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
            }
            .buttonStyle(.plain)

            if let duration = element.audioDuration {
                Text(formatted(duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignSystem.blockContentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatted(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Simple play/pause wrapper around AVAudioPlayer for a single clip.
final class AudioPlaybackManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(url: URL) {
        if isPlaying {
            player?.stop()
            isPlaying = false
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
            isPlaying = true
        } catch {
            print("Playback error: \(error)")
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}
