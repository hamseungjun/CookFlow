import Foundation

/// Captures only the app's generated audio in an isolated DEBUG walkthrough.
/// No microphone or system audio is recorded.
@MainActor enum TestingAudioCapture {
    static func note(_ type: String, detail: String = "") {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-test") else { return }
        append(["type": type, "detail": detail, "time": Date().timeIntervalSince1970])
        #endif
    }
    static func play(_ data: Data, lane: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-test") else { return }
        let folder = directory
        let name = UUID().uuidString + ".wav"
        guard (try? data.write(to: folder.appendingPathComponent(name))) != nil else { return }
        append(["type": "play", "lane": lane, "file": name, "time": Date().timeIntervalSince1970])
        #endif
    }
    static func stop(_ lane: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-test") else { return }
        append(["type": "stop", "lane": lane, "time": Date().timeIntervalSince1970])
        #endif
    }
    #if DEBUG
    private static var directory: URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("CookFlowTestingAudio")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    private static func append(_ event: [String: Any]) {
        guard var line = try? JSONSerialization.data(withJSONObject: event) else { return }
        line.append(10)
        let url = directory.appendingPathComponent("events.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) { try? line.write(to: url); return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd(); try? handle.write(contentsOf: line)
        }
    }
    #endif
}
