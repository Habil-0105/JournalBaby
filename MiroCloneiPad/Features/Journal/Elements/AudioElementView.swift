import SwiftUI
import Combine
import AVFoundation

struct AudioElementView: View {
    @ObservedObject var store: CanvasStore
    var element: CanvasElement

    /// The one shared playback manager, hosted by the store. Observing it
    /// (instead of owning a per-view manager) is what enforces the
    /// "exactly one audio element playing at a time" rule: starting any
    /// clip stops whatever was playing, regardless of which element the
    /// user tapped.
    @ObservedObject var player: AudioPlaybackManager

    init(store: CanvasStore, element: CanvasElement) {
        self.store = store
        self.element = element
        self.player = store.audioPlayer
    }

    var body: some View {
        VStack(spacing: 6) {
            Button {
                guard let fileName = element.audioFileName else { return }
                let url = store.audioURL.appendingPathComponent(fileName)
                player.toggle(url: url, for: element.id)
            } label: {
                Image(systemName: isThisElementPlaying ? "pause.circle.fill" : "play.circle.fill")
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

    /// Whether THIS element is the one currently producing sound. Only the
    /// active clip shows the pause icon; every other element shows play.
    private var isThisElementPlaying: Bool {
        player.isPlaying && player.elementID == element.id
    }

    private func formatted(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Single shared play/pause wrapper around `AVAudioPlayer`. One instance
/// lives on the store and all `AudioElementView`s drive it. Because there
/// is exactly one manager, starting one clip automatically stops the
/// previously playing clip (if any) — two audios can never overlap.
final class AudioPlaybackManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false

    /// The element currently holding the audio (or nil). Lets each view
    /// decide whether IT is the active player.
    @Published private(set) var elementID: UUID?

    private var player: AVAudioPlayer?

    /// Taps the same clip that is already playing → stop it. Taps any
    /// other clip (or a stopped clip) → stop the current playback (if any)
    /// and start this one.
    func toggle(url: URL, for id: UUID) {
        if isPlaying && elementID == id {
            stop()
            return
        }
        player?.stop()
        player = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
            isPlaying = true
            elementID = id
        } catch {
            print("Playback error: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        elementID = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        isPlaying = false
        elementID = nil
    }
}