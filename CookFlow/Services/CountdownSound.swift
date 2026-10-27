import AVFoundation

@MainActor final class CountdownSound {
    private var player: AVAudioPlayer?
    private var tracker = CountdownCue()
    private let beep = CountdownSound.wave(finish: false)
    private let bell = CountdownSound.wave(finish: true)

    func update(timers: [(id: String, remaining: Int)]) {
        tracker.retain(ids: Set(timers.map(\.id)))
        var cue: Int?
        for timer in timers where tracker.update(id: timer.id, remaining: timer.remaining) {
            cue = min(cue ?? timer.remaining, timer.remaining)
        }
        guard let cue else { return }
        // Timer sounds are independent of the spoken-guide switch.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(data: cue == 0 ? bell : beep)
        if player?.play() == true { TestingAudioCapture.play(cue == 0 ? bell : beep, lane: "timer") }
    }

    private static func wave(finish: Bool) -> Data {
        let rate = 24_000
        let duration = finish ? 0.85 : 0.13
        let count = Int(Double(rate) * duration)
        var pcm = Data()
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            let attack = min(1, t / 0.008)
            let envelope = finish ? exp(-t * 4.5) : min(1, (duration - t) / 0.025)
            let frequency = finish ? 1320.0 : 880.0
            let tone = sin(2 * .pi * frequency * t) + (finish ? 0.22 * sin(2 * .pi * frequency * 2 * t) : 0)
            var sample = Int16(tone * attack * envelope * 12_000).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        append(UInt32(36 + pcm.count)); data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(UInt32(pcm.count)); data.append(pcm)
        return data
    }
}
