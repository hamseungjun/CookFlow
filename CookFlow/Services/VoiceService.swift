import AVFoundation
import CryptoKit
import Speech
import SwiftUI

@MainActor final class VoiceService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var speaking = false
    private var fixtureConsumed = false
    var onReadyToListen: (() -> Void)?
    var onListeningEnded: (() -> Void)?
    var onEmptyTranscription: (() -> Void)?
    private var silenceTask: Task<Void, Never>?
    var onSpeechFinished: (() -> Void)?
    private var playbackFinished: (() -> Void)?
    private var recognitionID = UUID()
    @Published var listening = false
    @Published var transcribing = false
    @Published var microphoneLevel: Double = 0
    private var microphoneRecorder: AVAudioRecorder?
    private var microphoneURL: URL?
    private var microphoneStartup: [String: Any] = [:]
    private var microphoneTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    @Published var transcript = ""
    @Published var error: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var installedTap = false
    @Published var voiceStatus = "AI 음성 안내"
    private var playback: AVAudioPlayer?
    private var speechTask: Task<Void, Never>?
    private var utteranceID = UUID()
    private var prefetchTask: Task<Void, Never>?
    private var prefetchQueue: [(text: String, endpoint: String)] = []
    private var pendingAudio: [String: Task<Data, Error>] = [:]
    private let audioCache = NSCache<NSString, NSData>()
    private var preparedAudio: [String: Data] = [:]
    // Two provider requests at a time, shared by playback and background preparation.
    private var activeAudioRequests = 0
    private var activeBackgroundAudioRequests = 0
    private var priorityAudioKeys: Set<String> = []
    func prepareAll(_ texts: [String], endpoint: String, progress: (Int, Int) -> Void) async throws {
        let unique = Array(NSOrderedSet(array: texts)) as! [String]
        preparedAudio.removeAll(keepingCapacity: true)
        var next = 0
        var completed = 0
        try await withThrowingTaskGroup(of: (String, Data).self) { group in
            func enqueue(_ text: String) {
                group.addTask { @MainActor [self] in
                    try Task.checkCancellation()
                    return (text, try await audioData(text: text, endpoint: endpoint, priority: true))
                }
            }
            for _ in 0..<min(2, unique.count) { enqueue(unique[next]); next += 1 }
            while let (text, bytes) = try await group.next() {
                try Task.checkCancellation()
                let player = try AVAudioPlayer(data: bytes)
                guard player.prepareToPlay() else { throw RecipeError.invalid("안내 음성을 준비하지 못했습니다.") }
                preparedAudio[endpoint + "\n" + text] = bytes
                completed += 1
                progress(completed, unique.count)
                if next < unique.count { enqueue(unique[next]); next += 1 }
            }
        }
        TestingAudioCapture.note("all_voice_prepared", detail: String(completed))
    }
    private func playPrepared(_ bytes: Data) throws {
        playback = try AVAudioPlayer(data: bytes); playback?.delegate = self; playback?.prepareToPlay()
        guard playback?.play() == true else { throw RecipeError.invalid("음성을 재생하지 못했습니다.") }
        TestingAudioCapture.play(bytes, lane: "voice")
        voiceStatus = "AI 음성 · 따뜻한 안내"
    }
    func speak(_ text: String, endpoint: String = "") {
        stopListening()
        playbackFinished = onSpeechFinished; onSpeechFinished = nil
        speaking = true
        TestingAudioCapture.stop("voice")
        speechTask?.cancel(); playback?.stop(); playback = nil; error = nil
        utteranceID = UUID(); let id = utteranceID
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        guard !endpoint.isEmpty else { speaking = false; playbackFinished = nil; voiceStatus = "음성 서버 연결 필요"; error = "내 주방에서 음성 서버를 연결해주세요."; return }
        audioCache.countLimit = 64; audioCache.totalCostLimit = 48 * 1024 * 1024
        let cacheKey = (endpoint + "\n" + text) as NSString
        voiceStatus = "자연스러운 음성 준비 중"
        if let bytes = preparedAudio[endpoint + "\n" + text] {
            TestingAudioCapture.note("prepared_playback", detail: text)
            do { try playPrepared(bytes); return }
            catch { speaking = false; self.error = "안내 음성을 재생하지 못했어요."; onReadyToListen?(); return }
        }
        speechTask = Task { [weak self] in
            guard let self else { return }
            do {
                let bytes: Data
                bytes = try await audioData(text: text, endpoint: endpoint, priority: true)
                guard !Task.isCancelled, utteranceID == id, !listening else { return }
                audioCache.setObject(bytes as NSData, forKey: cacheKey, cost: bytes.count)
                playback = try AVAudioPlayer(data: bytes); playback?.delegate = self; playback?.prepareToPlay()
                guard playback?.play() == true else { throw RecipeError.invalid("음성을 재생하지 못했습니다.") }
                TestingAudioCapture.play(bytes, lane: "voice")
                voiceStatus = "AI 음성 · 따뜻한 안내"
            } catch {
                guard !Task.isCancelled, utteranceID == id, !listening else { return }
                speaking = false; playbackFinished = nil
                voiceStatus = "AI 음성 연결을 확인해주세요"
                self.error = "음성을 불러오지 못했어요. 화면 안내를 따라 진행할 수 있어요."
                self.onReadyToListen?()
            }
        }
    }
    private func audioData(text: String, endpoint: String, priority: Bool = false) async throws -> Data {
        let key = endpoint + "\n" + text
        if let data = audioCache.object(forKey: key as NSString) { return data as Data }
        if let url = cachedFile(key), let bytes = try? Data(contentsOf: url), bytes.starts(with: Data("RIFF".utf8)), bytes.count < 12 * 1024 * 1024 {
            audioCache.setObject(bytes as NSData, forKey: key as NSString, cost: bytes.count)
            return bytes
        }
        TestingAudioCapture.note("voice_fetch", detail: text)
        if priority { priorityAudioKeys.insert(key) }
        let task: Task<Data, Error>
        if let pending = pendingAudio[key] { task = pending }
        else {
            task = Task { [self] in
                while activeAudioRequests >= 2 || (!priorityAudioKeys.contains(key) && activeBackgroundAudioRequests >= 1) {
                    try await Task.sleep(for: .milliseconds(25))
                }
                try Task.checkCancellation()
                let background = !priorityAudioKeys.contains(key)
                activeAudioRequests += 1
                if background { activeBackgroundAudioRequests += 1 }
                defer {
                    activeAudioRequests -= 1
                    if background { activeBackgroundAudioRequests -= 1 }
                }
                return try await AIConnection.speech(text: text, endpoint: endpoint)
            }
            pendingAudio[key] = task
        }
        defer { pendingAudio[key] = nil; priorityAudioKeys.remove(key) }
        let data = try await task.value
        audioCache.countLimit = 64; audioCache.totalCostLimit = 48 * 1024 * 1024
        audioCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        saveAudio(data, key: key)
        return data
    }
    func preload(_ texts: [String], endpoint: String) {
        guard !endpoint.isEmpty else { return }
        let incoming = texts.map { (text: $0, endpoint: endpoint) }
        // Replace obsolete recipe jobs; one background slot leaves room for an immediate guide.
        prefetchQueue = incoming
        prefetchQueue = Array(prefetchQueue.prefix(64))
        guard prefetchTask == nil else { return }
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<2 {
                    group.addTask { @MainActor [self] in
                        while !self.prefetchQueue.isEmpty {
                            let next = self.prefetchQueue.removeFirst()
                            _ = try? await self.audioData(text: next.text, endpoint: next.endpoint)
                        }
                    }
                }
            }
            prefetchTask = nil
        }
    }
    private func cachedFile(_ key: String) -> URL? {
        guard let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = root.appendingPathComponent("CookFlowSpeech", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(hash + ".wav")
    }
    private func saveAudio(_ data: Data, key: String) {
        guard let url = cachedFile(key) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let files = (try? FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        let sorted = files.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        var size = 0
        for (index, file) in sorted.enumerated() {
            size += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if index >= 64 || size > 96 * 1024 * 1024 { try? FileManager.default.removeItem(at: file) }
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.playback === player else { return }
            self.speaking = false
            let finished = self.playbackFinished; self.playbackFinished = nil
            if flag { finished?() }; self.onReadyToListen?()
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.playback === player else { return }
            self.speaking = false; self.playbackFinished = nil; self.onReadyToListen?()
        }
    }
    func stopSpeaking() {
        speaking = false; playbackFinished = nil; onSpeechFinished = nil
        TestingAudioCapture.stop("voice")
        utteranceID = UUID(); speechTask?.cancel(); speechTask = nil
        playback?.stop(); playback = nil
    }
    func listen(context: [String] = [], onResult: @escaping (String) -> Void) async {
        guard !speaking else { return }
        stopListening()
        let id = UUID(); recognitionID = id
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test") && ProcessInfo.processInfo.arguments.contains("--voice-file-test") {
            guard !fixtureConsumed else { return }; fixtureConsumed = true
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceInputs/command.wav")
            guard let bytes = try? Data(contentsOf: url) else { error = "검증용 음성 파일이 없습니다."; return }
            submitRecording(bytes, mime: "audio/wav", id: id, fixture: true, context: context, onResult: onResult)
            return
        }
        #endif
        let allowed = await withCheckedContinuation { continuation in AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) } }
        guard recognitionID == id, !speaking else { return }
        guard allowed else { error = "마이크 권한을 허용해주세요. 설정 → CookFlow → 마이크에서 켤 수 있어요."; return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-" + id.uuidString + ".wav")
            microphoneURL = url
            let session = AVAudioSession.sharedInstance()
            let sampleRate = session.sampleRate > 0 ? session.sampleRate : 44100
            microphoneStartup = ["sample_rate": sampleRate, "inputs": session.currentRoute.inputs.map { $0.portType.rawValue }, "permission": session.recordPermission.rawValue]
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord() else { throw RecipeError.invalid("녹음 파일 준비 실패") }
            guard recorder.record() else { throw RecipeError.invalid("마이크 녹음 실행 실패") }
            microphoneRecorder = recorder; listening = true; voiceStatus = "OpenAI 음성 인식 · 듣고 있어요"
            let started = Date()
            microphoneTask = Task { [weak self] in
                var activity = VoiceActivityWindow()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled, let self, self.recognitionID == id, self.listening, !self.speaking else { return }
                    recorder.updateMeters()
                    let db = Double(recorder.averagePower(forChannel: 0))
                    self.microphoneLevel = min(1, pow(10, db / 20) * 6)
                    switch activity.observe(decibels: db, elapsed: Date().timeIntervalSince(started)) {
                    case .finish:
                        recorder.stop(); self.microphoneRecorder = nil; self.microphoneURL = nil
                        let bytes = try? Data(contentsOf: url); try? FileManager.default.removeItem(at: url)
                        self.listening = false; self.microphoneLevel = 0
                        guard let bytes else { self.error = "녹음 파일을 읽지 못했어요. 화면의 단계 버튼을 사용할 수 있어요."; self.onListeningEnded?(); return }
                        self.submitRecording(bytes, id: id, context: context, onResult: onResult)
                        return
                    case .silence: self.stopListening(notify: true); return
                    case .speaking: self.voiceStatus = "목소리 감지 · 말이 끝나길 기다려요"
                    case .waiting: break
                    }
                }
            }
        } catch { stopListening(); self.error = "녹음 시작 실패 (\((error as NSError).code)): \(error.localizedDescription)" }
    }
    private func submitRecording(_ bytes: Data, mime: String = "audio/wav", id: UUID, fixture: Bool = false, context: [String] = [], onResult: @escaping (String) -> Void) {
        transcribing = true; voiceStatus = "OpenAI가 목소리를 받아쓰는 중"
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await AIConnection.transcribe(audio: bytes, mime: mime, context: context)
                guard !Task.isCancelled, self.recognitionID == id, !self.speaking else { return }
                self.transcribing = false; self.error = nil; self.transcript = text
                #if DEBUG
                if fixture { self.fixtureResult(["transcript": text, "accepted": !text.isEmpty, "engine": "gpt-4o-transcribe"]) }
                #endif
                if text.isEmpty { self.voiceStatus = "음성을 문장으로 옮기지 못했어요."; self.onEmptyTranscription?(); self.onListeningEnded?() }
                else { self.voiceStatus = "인식한 문장을 확인 중"; onResult(text) }
            } catch {
                guard !Task.isCancelled, self.recognitionID == id else { return }
                self.transcribing = false; self.error = "음성 받아쓰기 연결 실패. \(error.localizedDescription)"
                self.onListeningEnded?()
            }
        }
    }
    #if DEBUG
    var recordingMicrophone: Bool { microphoneRecorder?.isRecording ?? false }
    func probeMicrophone() async {
        await listen { _ in }
        try? await Task.sleep(for: .seconds(1))
        let result: [String: Any] = ["startup": microphoneStartup, "listening": listening, "recorder_running": microphoneRecorder?.isRecording ?? false, "input_level": microphoneLevel, "error": error ?? "", "inputs": AVAudioSession.sharedInstance().currentRoute.inputs.map { $0.portType.rawValue }]
        stopListening()
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceInputs")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let bytes = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? bytes.write(to: folder.appendingPathComponent("microphone-probe.json"), options: .atomic) }
    }
    #endif
    #if DEBUG
    private func fixtureResult(_ result: [String: Any]) {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceInputs")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let bytes = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? bytes.write(to: folder.appendingPathComponent("result.json"), options: .atomic) }
    }
    private func recognizeFixture(id: UUID, context: [String], onResult: @escaping (String) -> Void) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")), recognizer.isAvailable else {
            error = "이 시뮬레이터에서 한국어 음성 인식을 사용할 수 없습니다."
            fixtureResult(["error": error!]); return
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceInputs/command.wav")
        guard FileManager.default.fileExists(atPath: url.path) else { error = "검증 음성 파일이 없습니다."; fixtureResult(["error": error!]); return }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.contextualStrings = ["했어", "했어요", "넣었어", "넣었어요", "다 했어요", "다 넣었어요", "다음 단계로 넘어가", "잠깐 멈춰", "아직 안 넣었어", "아직 안 했어", "계속해", "다시 말해줘", "남은 시간", "불 몇 단계야"] + context
        listening = true
        fixtureResult(["state": "recognizing"])
        task = recognizer.recognitionTask(with: request) { [weak self] result, recognitionError in
            Task { @MainActor in
                guard let self, self.listening, self.recognitionID == id, !self.speaking else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    let scores = result.bestTranscription.segments.map { Double($0.confidence) }
                    let accepted = CookingVoiceCommand.isConfident(scores)
                    self.fixtureResult(["transcript": text, "confidence": scores, "accepted": accepted])
                    self.stopListening()
                    if accepted { onResult(text) }
                    else { self.error = "검증 음성 인식이 불확실합니다." }
                } else if let recognitionError {
                    self.fixtureResult(["error": recognitionError.localizedDescription, "transcript": self.transcript])
                    self.stopListening(); self.error = "검증 음성 인식 실패: " + recognitionError.localizedDescription
                }
            }
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.listening else { return }
            self.fixtureResult(["error": "음성 인식 응답 시간 초과", "transcript": self.transcript])
            self.stopListening(); self.error = "검증 음성 인식 응답 시간 초과"
        }
    }
    #endif
    func stopListening(notify: Bool = false) {
        microphoneTask?.cancel(); microphoneTask = nil
        transcriptionTask?.cancel(); transcriptionTask = nil
        microphoneRecorder?.stop(); microphoneRecorder = nil
        if let url = microphoneURL { try? FileManager.default.removeItem(at: url) }; microphoneURL = nil
        transcribing = false; microphoneLevel = 0
        silenceTask?.cancel(); silenceTask = nil
        recognitionID = UUID()
        listening = false; timeout?.cancel(); timeout = nil
        engine.stop()
        if installedTap { engine.inputNode.removeTap(onBus: 0); installedTap = false }
        request?.endAudio(); task?.cancel(); request = nil; task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if notify { onListeningEnded?() }
    }
}
