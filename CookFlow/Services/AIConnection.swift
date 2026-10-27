import Foundation
import CryptoKit

struct AIServiceStatus: Identifiable {
    let id: String
    let title: String
    let configured: Bool?
}
struct VoiceDecision: Decodable {
    var reason: String?
    let intent: String
    let confidence: Double
}
enum AIConnection {
    static var pairedBase: String {
        let saved = UserDefaults.standard.string(forKey: "cookflowServerBaseOverride")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? (Bundle.main.object(forInfoDictionaryKey: "CookFlowServerBase") as? String ?? "") : saved
    }
    private static func defaultEndpoint(_ path: String) -> String {
        #if targetEnvironment(simulator)
        return "http://localhost:8765" + path
        #else
        return pairedBase.isEmpty ? "" : pairedBase + path
        #endif
    }
    static func configuredEndpoint(_ saved: String?, fallback: String) -> String {
        guard let saved, !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fallback }
        #if !targetEnvironment(simulator)
        if let url = URL(string: saved), let host = url.host,
           ["localhost", "127.0.0.1", "0.0.0.0"].contains(host) || host.hasSuffix(".local") && url.port == 8765 || host.hasSuffix(".trycloudflare.com") && host != URL(string: pairedBase)?.host {
            return fallback
        }
        #endif
        return saved
    }
    static func checkConnection() async throws -> String {
        let base: String
        #if targetEnvironment(simulator)
        base = "http://localhost:8765"
        #else
        base = pairedBase
        #endif
        guard !base.isEmpty else { throw RecipeError.invalid("AI 서버 연결이 설정되지 않았어요.") }
        var request = URLRequest(url: try endpoint(base + "/health")); request.timeoutInterval = 15
        authorize(&request)
        let (bytes, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], result["status"] as? String == "ready" else { throw RecipeError.invalid("AI 서버 연결 인증을 확인해주세요.") }
        return "AI 서버 응답 확인됨"
    }
    static func serviceStatuses() async throws -> [AIServiceStatus] {
        let base: String
        #if targetEnvironment(simulator)
        base = "http://localhost:8765"
        #else
        base = pairedBase
        #endif
        guard !base.isEmpty else { throw RecipeError.invalid("AI 서버 주소를 먼저 연결해주세요.") }
        var request = URLRequest(url: try endpoint(base + "/health")); request.timeoutInterval = 15
        authorize(&request)
        let (bytes, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], result["status"] as? String == "ready",
              let values = result["services"] as? [String: Bool] else { throw RecipeError.invalid("AI 서버 상태를 읽지 못했어요.") }
        let entries: [(String, String)] = [("recipes", "AI 맞춤 레시피"), ("video", "YouTube 레시피"), ("preparation_images", "손질 예시 이미지"), ("transcription", "음성 받아쓰기"), ("decision", "음성 명령 이해"), ("speech", "AI 음성 안내")]
        return entries.map { AIServiceStatus(id: $0.0, title: $0.1, configured: values[$0.0]) }
    }
    static func authorize(_ request: inout URLRequest) {
        guard let url = request.url, let paired = URL(string: pairedBase),
              ((url.host == paired.host && url.port == paired.port && url.scheme == paired.scheme) || (["localhost", "127.0.0.1"].contains(url.host ?? "") && url.port == 8765 && url.scheme == "http")),
              let token = Bundle.main.object(forInfoDictionaryKey: "CookFlowClientToken") as? String else { return }
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    }
    static var localTranscription: String { defaultEndpoint("/api/voice/transcribe") }
    static func transcribe(audio: Data, mime: String = "audio/mp4", context: [String] = []) async throws -> String {
        struct Result: Decodable { let text: String }
        var request = URLRequest(url: try endpoint(localTranscription)); request.httpMethod = "POST"; request.timeoutInterval = 40
        authorize(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["audio_base64": audio.base64EncodedString(), "mime": mime, "context": context])
        for attempt in 0..<2 {
            let (bytes, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if [429, 502, 503, 504].contains(code), attempt == 0 { try await Task.sleep(for: .milliseconds(500)); continue }
            guard code == 200 else { throw RecipeError.invalid("음성 받아쓰기 서버 연결 실패 (\(code))") }
            return try JSONDecoder().decode(Result.self, from: bytes).text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw RecipeError.invalid("음성 받아쓰기가 지연됐어요.")
    }
    static var localDecision: String { defaultEndpoint("/api/voice/decide") }
    static func voiceDecision(text: String, session: CookingSession, endpoint: String) async throws -> VoiceDecision {
        var request = URLRequest(url: try self.endpoint(endpoint)); request.httpMethod = "POST"; request.timeoutInterval = 12
        authorize(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "title": session.currentStep?.title ?? "", "instruction": session.currentStep?.instruction ?? "", "phase": session.state == .paused ? "paused" : session.phase.rawValue, "required_items": session.currentStep?.requiredItems.map { $0.ingredient.name } ?? [], "confirmation_goal": session.currentStep.map { CookingVoiceCommand.confirmationGoal(for: $0) } ?? ""])
        let allowed = Set(["confirm", "skip", "pause", "resume", "repeat", "reset", "extend30", "extend60", "extend120", "remaining", "heat", "keep"])
        for attempt in 0..<2 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if [429, 502, 503, 504].contains(code), attempt == 0 {
                    try await Task.sleep(for: .milliseconds(400 * (attempt + 1))); continue
                }
                guard code == 200 else { throw RecipeError.invalid(code == 401 || code == 403 ? "AI 서버 연결 인증이 맞지 않아요." : "음성 AI 서버가 응답하지 않았어요.") }
                let result = try JSONDecoder().decode(VoiceDecision.self, from: data)
                guard allowed.contains(result.intent), result.confidence.isFinite, (0...1).contains(result.confidence) else { throw RecipeError.invalid("음성 판정 형식이 잘못됐어요.") }
                return result
            } catch let error as URLError {
                guard attempt == 0, [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) else { throw error }
                try await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
            }
        }
        throw RecipeError.invalid("음성 AI 연결이 지연됐어요.")
    }

    static var localVideo: String { defaultEndpoint("/api/video-recipe") }
    static var localSpeech: String { defaultEndpoint("/api/speech") }
    static func speech(text: String, endpoint: String) async throws -> Data {
        var request = URLRequest(url: try self.endpoint(endpoint)); request.httpMethod = "POST"; request.timeoutInterval = 25
        authorize(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            // A previous request or another device may still occupy the server's two slots.
            if status == 429 && attempt < 2 {
                try await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
                continue
            }
            guard status == 200, data.starts(with: Data("RIFF".utf8)), data.count < 12 * 1024 * 1024 else { throw RecipeError.invalid("자연스러운 음성에 연결하지 못했습니다.") }
            return data
        }
        throw RecipeError.invalid("음성 안내가 잠시 지연되고 있어요. 다시 시도해주세요.")
    }
    static var localPreparationImage: String { defaultEndpoint("/api/preparation-image") }
    static func preparationImage(ingredient: String, shape: String, method: String, retry: Bool = false) async throws -> Data {
        let identity = ingredient + "\n" + shape + "\n" + (["slice", "reference"].contains(shape) ? method : "") + "\nprep-photo-v1"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PreparationImages")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(key + ".png")
        if let bytes = try? Data(contentsOf: file), bytes.starts(with: Data([137,80,78,71,13,10,26,10])) { return bytes }
        let base = localPreparationImage
        var request = URLRequest(url: try endpoint(base)); request.httpMethod = "POST"; request.timeoutInterval = 20
        authorize(&request); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["ingredient": ingredient, "shape": shape, "method": method, "retry": retry])
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            try Task.checkCancellation()
            let (bytes, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RecipeError.invalid("손질 예시를 불러오지 못했어요.") }
            let result = try JSONDecoder().decode(PreparationImageResult.self, from: bytes)
            if result.status == "ready", let encoded = result.image_base64, let image = Data(base64Encoded: encoded), image.count < 12 * 1024 * 1024, image.starts(with: Data([137,80,78,71,13,10,26,10])) {
                try image.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                return image
            }
            if result.status == "failed" { throw RecipeError.invalid(result.error ?? "예시 생성이 지연돼요. 글 안내로 준비할 수 있어요.") }
            guard result.id.count == 64, result.id.allSatisfy({ $0.isHexDigit }) else { throw RecipeError.invalid("손질 예시 주소가 올바르지 않아요.") }
            try await Task.sleep(for: .seconds(2))
            request = URLRequest(url: try endpoint(base + "/" + result.id)); request.timeoutInterval = 20; authorize(&request)
        }
        throw RecipeError.invalid("사진은 준비되면 다시 확인할 수 있어요. 조리는 바로 시작할 수 있어요.")
    }
    static var localGeneration: String { defaultEndpoint("/api/recipe/generate") }
    static func generate(dish: String, ingredients: String, preferences: Preferences, endpoint: String, baseline: Recipe? = nil) async throws -> VideoRecipeDraft {
        var request = URLRequest(url: try self.endpoint(endpoint)); request.httpMethod = "POST"; request.timeoutInterval = 180
        authorize(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["dish": dish, "ingredients": ingredients, "servings": preferences.servings, "spice": preferences.spice, "salt": preferences.salt, "excludeMeat": preferences.excludeMeat, "excludeSeafood": preferences.excludeSeafood]
        var reference = baseline
        if reference == nil, let menu = RecipeMenu.matching(dish) {
            var referencePreferences = preferences
            referencePreferences.excludeMeat = false; referencePreferences.excludeSeafood = false
            reference = try? RecipeEngine.generate(selected: menu.defaultIngredients, quantities: [:], preferences: referencePreferences, menu: menu)
        }
        if let baseline = reference { body["baseline_recipe"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(baseline)) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
            throw RecipeError.invalid(error?["error"] ?? "AI 레시피를 만들지 못했습니다.")
        }
        return try JSONDecoder().decode(VideoRecipeDraft.self, from: data)
    }
    static func endpoint(_ value: String) throws -> URL {
        guard let url = URL(string: value), let host = url.host, url.user == nil, url.password == nil else { throw RecipeError.invalid("내 주방에서 AI 서버 주소를 연결해주세요.") }
        if url.scheme == "https" { return url }
        if url.scheme == "http", let paired = URL(string: pairedBase),
           host == paired.host, url.port == paired.port, host.hasSuffix(".local") { return url }
        #if DEBUG
        if url.scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host) { return url }
        #endif
        throw RecipeError.invalid("AI 서버는 HTTPS 주소로 연결해주세요.")
    }
    static func video(source: String, endpoint: String, requestedServings: Int = 1) async throws -> VideoRecipeDraft {
        let sourceURL = try YouTubeLink.canonical(source)
        var request = URLRequest(url: try self.endpoint(endpoint)); request.httpMethod = "POST"; request.timeoutInterval = 480
        authorize(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["url": sourceURL.absoluteString, "requested_servings": requestedServings])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
            throw RecipeError.invalid(error?["error"] ?? "영상 분석 서버에 연결하지 못했습니다.")
        }
        return try JSONDecoder().decode(VideoRecipeDraft.self, from: data)
    }
}

private struct PreparationImageResult: Decodable {
    let id: String
    let status: String
    let image_base64: String?
    let error: String?
}
