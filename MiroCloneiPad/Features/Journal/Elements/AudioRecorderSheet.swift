import SwiftUI
import Combine
import AVFoundation

/// Handles microphone permission + recording to a temp file.
final class AudioRecorderManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordedURL: URL?

    func requestPermissionAndStart() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.start()
                } else {
                    self?.permissionDenied = true
                }
            }
        }
    }

    private func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            recorder = try AVAudioRecorder(url: tempURL, settings: settings)
            recorder?.record()
            recordedURL = tempURL
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.elapsed += 0.1
            }
        } catch {
            print("Recording error: \(error)")
        }
    }

    func stop() -> (url: URL, duration: TimeInterval)? {
        recorder?.stop()
        timer?.invalidate()
        isRecording = false
        guard let url = recordedURL else { return nil }
        return (url, elapsed)
    }
}

/// Modal sheet: tap to start recording, tap again to stop and drop the
/// clip onto the page as a new audio element.
struct AudioRecorderSheet: View {
    @ObservedObject var store: CanvasStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorderManager()

    var body: some View {
        VStack(spacing: 24) {
            Text(recorder.isRecording ? "Recording…" : "Ready to record")
                .font(.headline)

            Text(String(format: "%.1fs", recorder.elapsed))
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .monospacedDigit()

            Button {
                if recorder.isRecording {
                    if let result = recorder.stop() {
                        store.addAudio(fileURL: result.url, duration: result.duration)
                    }
                    dismiss()
                } else {
                    recorder.requestPermissionAndStart()
                }
            } label: {
                Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(recorder.isRecording ? .red : .accentColor)
            }
            .buttonStyle(.plain)

            if recorder.permissionDenied {
                Text("Microphone access is disabled. Enable it in Settings to record audio.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Cancel") { dismiss() }
                .padding(.top, 8)
        }
        .padding(40)
        .frame(minWidth: 320)
    }
}
