import Foundation
import AVFoundation

// Combine screen frames with the exact generated sounds played by the DEBUG app.
// Audio starts/stops follow app playback timestamps; no synthetic narration is added.
let args = CommandLine.arguments
guard args.count >= 6, let start = Double(args[3]) else { fatalError("video events start output audio-directory") }
let video = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let folder = URL(fileURLWithPath: args[5])
let lines = try String(contentsOfFile: args[2], encoding: .utf8).split(separator: "\n")
let events = try lines.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }.sorted { ($0["time"] as! Double) < ($1["time"] as! Double) }
let composition = AVMutableComposition()
let duration = args.count > 6 ? CMTime(seconds: min(Double(args[6]) ?? video.duration.seconds, video.duration.seconds), preferredTimescale: 600) : video.duration
let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
let sourceVideo = video.tracks(withMediaType: .video)[0]
try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
videoTrack.preferredTransform = sourceVideo.preferredTransform
var clips = 0
for (index, event) in events.enumerated() {
    guard event["type"] as? String == "play", let name = event["file"] as? String, let stamp = event["time"] as? Double, let lane = event["lane"] as? String else { continue }
    let offset = stamp - start
    guard offset >= 0, offset < duration.seconds else { continue }
    let audio = AVURLAsset(url: folder.appendingPathComponent(name))
    guard let source = audio.tracks(withMediaType: .audio).first else { continue }
    var seconds = min(audio.duration.seconds, duration.seconds - offset)
    if let next = events.dropFirst(index + 1).first(where: { $0["lane"] as? String == lane }), let stop = next["time"] as? Double { seconds = min(seconds, stop - stamp) }
    guard seconds > 0.01 else { continue }
    let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try track.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 24000)), of: source, at: CMTime(seconds: offset, preferredTimescale: 24000))
    clips += 1
}
let output = URL(fileURLWithPath: args[4])
let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080)!
export.outputURL = output; export.outputFileType = .mp4; export.shouldOptimizeForNetworkUse = true
export.exportAsynchronously {
    if export.status == .completed { print("Exported \(clips) actual app audio clips; \(Int(duration.seconds)) seconds"); exit(0) }
    print(export.error?.localizedDescription ?? "Export failed"); exit(1)
}
dispatchMain()
