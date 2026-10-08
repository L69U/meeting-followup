import SwiftUI
import AVFoundation
import Combine

@MainActor final class RecordingPlayer: ObservableObject {
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var ticker: AnyCancellable?

    func load(_ url: URL) {
        stop()
        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.prepareToPlay()
            player = audio
            duration = audio.duration
            error = nil
            ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                guard let self, let player = self.player else { return }
                self.position = player.currentTime
                self.playing = player.isPlaying
            }
        } catch { self.error = "此录音暂时无法回听：\(error.localizedDescription)" }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying { player.pause(); playing = false }
        else {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                playing = player.play()
                if !playing { error = "播放失败，请重新打开会议。" }
            } catch { self.error = error.localizedDescription }
        }
    }

    func seek(_ time: Double, play: Bool = false) {
        guard time.isFinite, let player else { return }
        player.currentTime = min(max(0, time), duration)
        position = player.currentTime
        if play && !player.isPlaying { toggle() }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        playing = false
        position = 0
        duration = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        let value = Int(max(0, seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

struct RecordingControls: View {
    @ObservedObject var player: RecordingPlayer
    var body: some View {
        VStack(spacing: 12) {
            if let error = player.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button { player.seek(player.position - 10) } label: { Image(systemName: "gobackward.10") }
                    .accessibilityLabel("后退十秒")
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill").font(.largeTitle)
                }.accessibilityLabel(player.playing ? "暂停" : "播放原始录音")
                Spacer()
                Button { player.seek(player.position + 10) } label: { Image(systemName: "goforward.10") }
                    .accessibilityLabel("前进十秒")
            }.buttonStyle(.borderless)
            Slider(value: Binding(get: { player.position }, set: { player.seek($0) }), in: 0...max(0.01, player.duration))
                .accessibilityLabel("播放进度")
            HStack {
                Text(RecordingPlayer.time(player.position))
                Spacer()
                Text(RecordingPlayer.time(player.duration))
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }.disabled(player.duration <= 0)
    }
}
