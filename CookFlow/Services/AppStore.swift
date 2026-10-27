import AudioToolbox
import SwiftUI
import UserNotifications

struct AppData: Codable {
    var menu: RecipeMenu? = nil
    var menuSelections: [String: Set<String>]? = nil
    var kitchens: [KitchenProfile] = []
    var selectedKitchenID: UUID?
    var selected: Set<String> = ["tofu", "zucchini", "onion", "scallion", "doenjang"]
    var quantities: [String: Double] = [:]
    var preferences = Preferences()
    var session: CookingSession?
    var history: [CookingSession] = []
    var voiceEnabled = true
    var voiceControlEnabled: Bool? = nil
    var videoRecipeEndpoint: String? = nil
    var generationEndpoint: String? = nil
    var savedRecipes: [SavedRecipe]? = nil
    var speechEndpoint: String? = nil
    var naturalVoice: Bool? = nil
    var decisionEndpoint: String? = nil
}
@MainActor final class AppStore: ObservableObject {
    @Published var data: AppData { didSet { persist() } }
    @Published var message: String?
    @Published var selectedTab = 0
    @Published var handsFreeEnabled = true {
        didSet {
            if data.voiceControlEnabled != handsFreeEnabled { data.voiceControlEnabled = handsFreeEnabled }
            if handsFreeEnabled { scheduleListening() }
            else { listeningRestart?.cancel(); voice.stopListening() }
        }
    }
    @Published var voiceFeedback: String? = nil
    private var cookingScreenVisible = false
    private var foreground = true
    private var kitchenAnnouncementPending = false
    private var listeningRestart: Task<Void, Never>?
    @Published var notificationStatus = "알림 권한을 요청하지 않았습니다."
    let voice = VoiceService()
    private let countdownSound = CountdownSound()
    private let url: URL
    var kitchen: KitchenProfile? { data.kitchens.first { $0.id == data.selectedKitchenID } ?? data.kitchens.first }
    var activeSession: CookingSession? { data.session }
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CookFlow", isDirectory: true)
        #if DEBUG
        let uiTest = ProcessInfo.processInfo.arguments.contains("--ui-test")
        let previewNumeric = ProcessInfo.processInfo.arguments.contains("--preview-numeric")
        let previewDial = ProcessInfo.processInfo.arguments.contains("--preview-dial")
        url = directory.appendingPathComponent(uiTest ? "state-ui-test.json" : previewNumeric || previewDial ? "state-flow-preview.json" : "state.json")
        #else
        url = directory.appendingPathComponent("state.json")
        #endif
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let bytes = try Data(contentsOf: url)
                data = try JSONDecoder().decode(AppData.self, from: bytes)
            } else { data = AppData() }
        } catch {
            // Preserve damaged state instead of overwriting the only copy.
            try? FileManager.default.copyItem(at: url, to: directory.appendingPathComponent("state-recovery-\(Int(Date().timeIntervalSince1970)).json"))
            data = AppData()
            message = "저장 정보를 읽지 못했습니다. 원본을 복구용으로 보관했습니다."
        }
        #if DEBUG
        if uiTest && ProcessInfo.processInfo.arguments.contains("--ui-test-reset") { data = AppData() }
        #endif
        if data.savedRecipes == nil {
            var ids = Set<UUID>()
            data.savedRecipes = data.history.compactMap { $0.recipe.recipeOrigin == .youtube && ids.insert($0.recipe.id).inserted ? SavedRecipe(recipe: $0.recipe) : nil }
        }
        let previousDefaultHeat: [String: Double] = ["low": 2, "mediumLow": 3, "medium": 4, "mediumHigh": 6, "high": 7]
        let strongerDefaultHeat: [String: Double] = ["low": 2, "mediumLow": 4, "medium": 6, "mediumHigh": 8, "high": 9]
        for index in data.kitchens.indices where data.kitchens[index].controlType.isNumeric && data.kitchens[index].numericMap == previousDefaultHeat {
            data.kitchens[index].numericMap = strongerDefaultHeat
            data.kitchens[index].calibrationSeconds = nil
        }
        #if DEBUG
        if previewNumeric || previewDial {
            var kitchen = KitchenProfile(); kitchen.name = "우리 집 주방"
            if previewDial { kitchen.heatingType = .gas; kitchen.controlType = .dial; kitchen.dialConfiguration = .clockwiseFromOff() }
            data = AppData(); data.kitchens = [kitchen]; data.selectedKitchenID = kitchen.id; data.voiceEnabled = false
            if let recipe = try? RecipeEngine.generate(kitchen: kitchen, selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: Preferences(), menu: .doenjang) {
                var session = CookingSession(recipe: CookingFlow.prepare(recipe, kitchen: kitchen))
                for check in session.checks { try? SessionEngine.apply(.approvePreparation(check.id), to: &session) }
                try? SessionEngine.apply(.beginCooking, to: &session)
                data.session = session; selectedTab = 1
            }
        }
        #endif
        #if DEBUG
        if uiTest && ProcessInfo.processInfo.arguments.contains("--voice-file-test") {
            data = AppData(); data.voiceEnabled = true
            if let recipe = try? RecipeEngine.generate(selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: .init()) {
                var session = CookingSession(recipe: CookingFlow.prepare(recipe))
                try? SessionEngine.apply(.approveAllPreparation, to: &session)
                try? SessionEngine.apply(.beginCooking, to: &session)
                data.session = session; selectedTab = 1
            }
        }
        #endif
        #if DEBUG
        if uiTest && ProcessInfo.processInfo.arguments.contains("--sundubu-voice-demo"),
           let recipe = try? RecipeEngine.generate(selected: RecipeMenu.sundubu.defaultIngredients, quantities: [:], preferences: .init(), menu: .sundubu) {
            data = AppData(); data.menu = .sundubu; data.voiceEnabled = true
            data.session = CookingSession(recipe: CookingFlow.prepare(recipe)); selectedTab = 1
        }
        #endif
        data.preferences.servings = 1
        handsFreeEnabled = data.voiceControlEnabled ?? true
        if data.session?.auxiliaryTimers.isEmpty == false { data.session?.auxiliaryTimers = []; updateNotification() }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--phone-ai-check") {
            Task {
                do {
                    let status = try await AIConnection.checkConnection(); print("PHONE_AI_CHECK: " + status)
                    let sample = CookingSession(recipe: try RecipeEngine.generate(selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: .init()))
                    let decision = try await AIConnection.voiceDecision(text: "다했어요", session: sample, endpoint: AIConnection.localDecision)
                    print("PHONE_AI_DECISION: " + decision.intent)
                }
                catch { print("PHONE_AI_CHECK_FAILED: " + error.localizedDescription) }
            }
        }
        #endif
        // Silence and kitchen noise should not prompt the cook to repeat themselves.
        voice.onEmptyTranscription = { [weak self] in self?.voiceFeedback = nil }
        voice.onReadyToListen = { [weak self] in self?.scheduleListening() }
        voice.onListeningEnded = { [weak self] in self?.scheduleListening() }
        bindKitchenGuidance()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--microphone-check") {
            if uiTest { data = AppData() }
            Task { try? await Task.sleep(for: .seconds(2)); await voice.probeMicrophone() }
        }
        #endif
        #if DEBUG
        if uiTest && ProcessInfo.processInfo.arguments.contains("--timer-mic-test"),
           let source = try? RecipeEngine.generate(selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: .init()) {
            let recipe = CookingFlow.prepare(source)
            data = AppData(); data.voiceEnabled = true; data.voiceControlEnabled = false; handsFreeEnabled = false
            var session = CookingSession(recipe: recipe)
            try? SessionEngine.apply(.approveAllPreparation, to: &session); try? SessionEngine.apply(.beginCooking, to: &session)
            data.session = session; selectedTab = 1
            Task {
                try? await Task.sleep(for: .seconds(2))
                do {
                    try await voice.prepareAll(["타이머가 시작됐어요.", cookingNarration(for: recipe.steps[1], recipe: recipe)], endpoint: AIConnection.localSpeech) { _, _ in }
                    handsFreeEnabled = true; scheduleListening()
                    try? await Task.sleep(for: .milliseconds(1200))
                    recordTimerMicCheck("before_timer")
                    perform(.startTimer)
                    if var current = data.session { current.targetEndAt = Date().addingTimeInterval(5); data.session = current }
                    recordTimerMicCheck("timer_started")
                    for _ in 0..<35 {
                        try? await Task.sleep(for: .milliseconds(100))
                        if !voice.speaking { break }
                    }
                    recordTimerMicCheck("timer_announcement_finished")
                    for _ in 0..<450 {
                        try? await Task.sleep(for: .milliseconds(100))
                        if data.session?.stepIndex == 1 && !voice.speaking { break }
                    }
                    try? await Task.sleep(for: .milliseconds(1200))
                    recordTimerMicCheck("next_guide_finished")
                    voice.stopListening()
                } catch { recordTimerMicCheck("test_error: " + error.localizedDescription) }
            }
        }
        #endif
    }
    #if DEBUG
    private var timerMicChecks: [[String: Any]] = []
    private func recordTimerMicCheck(_ point: String) {
        timerMicChecks.append(["point": point, "state": data.session?.state.rawValue ?? "", "phase": data.session?.phase.rawValue ?? "", "step": data.session?.stepIndex ?? -1, "listening": voice.listening, "recording": voice.recordingMicrophone, "speaking": voice.speaking, "error": voice.error ?? ""])
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceInputs")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let bytes = try? JSONSerialization.data(withJSONObject: timerMicChecks, options: [.prettyPrinted, .sortedKeys]) { try? bytes.write(to: folder.appendingPathComponent("timer-microphone.json"), options: .atomic) }
    }
    #endif
    func persist() {
        do { let bytes = try JSONEncoder().encode(data); try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { message = "기기에 저장하지 못했습니다: \(error.localizedDescription)" }
    }
    func saveKitchen(_ profile: KitchenProfile) -> Bool {
        let errors = profile.validationErrors()
        guard errors.isEmpty else { message = errors.joined(separator: "\n"); return false }
        guard !data.kitchens.contains(where: { $0.id != profile.id && $0.name.trimmingCharacters(in: .whitespaces) == profile.name.trimmingCharacters(in: .whitespaces) }) else { message = "동일한 이름의 주방이 있습니다. 다른 이름을 입력해주세요."; return false }
        if let index = data.kitchens.firstIndex(where: { $0.id == profile.id }) { data.kitchens[index] = profile } else { data.kitchens.append(profile) }
        data.selectedKitchenID = profile.id
        bindKitchenGuidance()
        return true
    }
    func selectKitchen(_ id: UUID?) { data.selectedKitchenID = id; bindKitchenGuidance() }
    func bindKitchenGuidance() {
        guard var session = data.session, [.preparing, .cooking, .paused].contains(session.state) else { return }
        if kitchen == nil && session.recipe.kitchen.usesGeneralGuidance == true { return }
        let profile = kitchen ?? .generalGuidance()
        guard session.recipe.kitchen != profile else { return }
        session.recipe = CookingFlow.rebindKitchen(session.recipe, to: profile)
        session.events.append(.init(at: Date(), stepID: session.currentStep?.id, type: "KITCHEN_GUIDANCE_UPDATED", detail: profile.name))
        data.session = session; voice.stopListening(); kitchenAnnouncementPending = true
    }
    func selectMenu(_ menu: RecipeMenu) {
        let previous = data.menu ?? .doenjang
        if previous != menu {
            var selections = data.menuSelections ?? [:]
            selections[previous.rawValue] = data.selected
            data.selected = selections[menu.rawValue] ?? menu.defaultIngredients
            data.menuSelections = selections
        }
        data.menu = menu
    }
    func generate(menu: RecipeMenu = .doenjang) -> Recipe? {
        do { return try RecipeEngine.generate(kitchen: kitchen, selected: data.selected, quantities: data.quantities, preferences: data.preferences, menu: menu) }
        catch { message = error.localizedDescription; return nil }
    }
    var savedRecipes: [SavedRecipe] { (data.savedRecipes ?? []).filter { $0.recipe.recipeOrigin == .youtube } }
    func saveRecipe(_ recipe: Recipe) {
        guard recipe.recipeOrigin == .youtube else { return }
        var recipes = savedRecipes
        let source = recipe.sourceVideoURL.flatMap { try? YouTubeLink.canonical($0) }
        if let index = recipes.firstIndex(where: {
            $0.id == recipe.id || (source != nil && $0.recipe.sourceVideoURL.flatMap { try? YouTubeLink.canonical($0) } == source)
        }) {
            var updated = recipe
            updated.id = recipes[index].id
            recipes[index].recipe = updated
        } else { recipes.insert(SavedRecipe(recipe: recipe), at: 0) }
        data.savedRecipes = recipes
    }
    func favorite(_ id: UUID) {
        var recipes = savedRecipes
        if let index = recipes.firstIndex(where: { $0.id == id }) { recipes[index].favorite.toggle(); data.savedRecipes = recipes }
    }
    func removeRecipe(_ id: UUID) { data.savedRecipes = savedRecipes.filter { $0.id != id } }
    func confirm(_ recipe: Recipe) { saveRecipe(recipe); data.session = CookingSession(recipe: CookingFlow.prepare(recipe, kitchen: kitchen)); selectedTab = 1; warmVoice() }
    @Published var preparingCookingVoice = false
    @Published var cookingVoiceProgress = ""
    private var preparedVoiceSignature: String?
    private func prepareCookingVoice(_ recipe: Recipe) {
        guard !preparingCookingVoice else { return }
        preparingCookingVoice = true
        let sessionID = data.session?.id
        let endpoint = AIConnection.configuredEndpoint(data.speechEndpoint, fallback: AIConnection.localSpeech)
        let texts = recipe.steps.map { cookingNarration(for: $0, recipe: recipe) }
        let signature = endpoint + texts.joined(separator: "\n")
        cookingVoiceProgress = "첫 조리 안내를 준비하고 있어요"
        Task {
            defer { preparingCookingVoice = false }
            do {
                try await voice.prepareAll(Array(texts.prefix(1)) + ["타이머가 시작됐어요."], endpoint: endpoint) { done, total in
                    cookingVoiceProgress = "첫 안내 준비 \(done)/\(total) · 나머지는 이어서 준비해요"
                }
                guard data.session?.id == sessionID, data.session?.state == .preparing,
                    let current = data.session else { return }
                let updated = CookingFlow.prepare(current.recipe, kitchen: kitchen)
                guard updated.steps.map({ self.cookingNarration(for: $0, recipe: updated) }) == texts,
                      (AIConnection.configuredEndpoint(data.speechEndpoint, fallback: AIConnection.localSpeech)) == endpoint else {
                    message = "주방이나 레시피가 바뀌었어요. 조리 시작을 다시 눌러주세요."; return
                }
                preparedVoiceSignature = signature
                voice.preload(Array(texts.dropFirst()) + Array(voiceControlTexts.dropFirst()) + current.recipe.steps.prefix(1).map { CookingNarration.text(for: $0, recipe: current.recipe) }, endpoint: endpoint)
                perform(.beginCooking)
            } catch { message = "안내 음성을 준비하지 못했어요. 연결을 확인하고 조리 시작을 다시 눌러주세요." }
        }
    }
    func perform(_ action: SessionAction, key: String? = nil) {
        guard var session = data.session else { return }
        let oldIndex = session.stepIndex
        do {
            if case .beginCooking = action {
                session.recipe = CookingFlow.prepare(session.recipe, kitchen: kitchen)
                let texts = session.recipe.steps.map { cookingNarration(for: $0, recipe: session.recipe) }
                let signature = (AIConnection.configuredEndpoint(data.speechEndpoint, fallback: AIConnection.localSpeech)) + texts.joined(separator: "\n")
                if data.voiceEnabled && preparedVoiceSignature != signature { prepareCookingVoice(session.recipe); return }
            }
            let changed = try SessionEngine.apply(action, to: &session, key: (key ?? UUID().uuidString) + "-visit-\(session.events.filter { $0.type == "PREVIOUS_STEP" }.count)")
            guard changed else { return }
            let enteredStage = oldIndex != session.stepIndex || session.events.last?.type == "BEGIN_COOKING"
            if enteredStage || session.events.last?.type == "RESET_TIMER" { ingredientVoiceUntil = nil }
            data.session = session
            if !HandsFreeVoicePolicy.canListen(session: session, enabled: true, visible: true, foreground: true, speaking: false, deciding: false) {
                listeningRestart?.cancel()
                if voice.listening || voice.transcribing { voice.stopListening() }
            }
            updateNotification()
            if enteredStage { TestingAudioCapture.note("stage_entered", detail: String(session.stepIndex)); speakCurrent(); warmVoice() }
            if session.events.last?.type == "TIMER_EXPIRED" { say("타이머가 끝났습니다. 재료 상태를 직접 확인한 뒤 완료를 눌러주세요.") }
            if session.events.last?.type == "START_TIMER" { say("타이머가 시작됐어요.") }
            if session.events.last?.type == "RESUME" { say("타이머를 다시 시작했어요.") }
            if session.events.last?.type == "PAUSE" { say("타이머를 잠깐 멈췄어요. 불은 직접 확인해주세요.") }
            scheduleListening()
        } catch { message = error.localizedDescription }
    }
    func tick() {
        guard let session = data.session, session.state == .cooking else { countdownSound.update(timers: []); return }
        var timers: [(id: String, remaining: Int)] = []
        if session.phase == .active, let end = session.targetEndAt {
            timers.append(("main-\(session.id)-\(session.stepIndex)-\(end.timeIntervalSince1970)", session.remaining()))
        }
        countdownSound.update(timers: timers)
        guard session.phase == .active, session.remaining() == 0 else { return }
        perform(.advanceAfterTimer, key: "expired-\(session.currentStep?.id.uuidString ?? "")-\(session.targetEndAt?.timeIntervalSince1970 ?? 0)")
    }
    func cookingScreen(_ visible: Bool) {
        cookingScreenVisible = visible
        if visible {
            if kitchenAnnouncementPending, let step = data.session?.currentStep, let profile = data.session?.recipe.kitchen {
                kitchenAnnouncementPending = false; say(profile.spokenSetting(step.heatTo))
            } else { scheduleListening() }
        } else { listeningRestart?.cancel(); voice.stopListening() }
    }
    func appForeground(_ active: Bool) {
        foreground = active
        if active { scheduleListening() } else { listeningRestart?.cancel(); voice.stopListening() }
    }
    func toggleHandsFree() { handsFreeEnabled.toggle() }
    func scheduleListening() {
        listeningRestart?.cancel()
        guard HandsFreeVoicePolicy.canListen(session: data.session, enabled: handsFreeEnabled,
            visible: cookingScreenVisible, foreground: foreground, speaking: voice.speaking, deciding: decidingVoice), !voice.transcribing else { return }
        listeningRestart = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, let self,
                  HandsFreeVoicePolicy.canListen(session: self.data.session, enabled: self.handsFreeEnabled,
                      visible: self.cookingScreenVisible, foreground: self.foreground, speaking: self.voice.speaking,
                      deciding: self.decidingVoice), !self.voice.listening, !self.voice.transcribing else { return }
            let id = self.data.session?.currentStep?.id
            let visit = self.data.session?.events.count ?? 0
            self.armVoiceInput()
            await self.voice.listen { [weak self] text in self?.receiveVoice(text, expectedStepID: id, expectedVisit: visit) }

        }
    }
    func say(_ text: String) { if data.voiceEnabled { voice.speak(text, endpoint: AIConnection.configuredEndpoint(data.speechEndpoint, fallback: AIConnection.localSpeech)) } }
    private var ingredientVoiceUntil: Date?
    func speakCurrent() {
        guard let session = data.session, let step = session.currentStep else { return }
        ingredientVoiceUntil = nil
        let visit = session.events.count
        voice.onSpeechFinished = { [weak self] in
            guard let self, self.data.session?.currentStep?.id == step.id,
                  self.data.session?.events.count == visit else { return }
            self.ingredientVoiceUntil = Date().addingTimeInterval(45)
        }
        say(cookingNarration(for: step, recipe: session.recipe, intro: session.events.last?.type == "BEGIN_COOKING"))
    }
    private func cookingNarration(for step: CookingStep, recipe: Recipe, intro: Bool = true) -> String {
        let guide = CookingNarration.text(for: step, recipe: recipe)
        return intro && step.id == recipe.steps.first?.id ? "안내가 끝나면 완료 여부를 편하게 말해주세요. 타이머는 자동으로 시작돼요. " + guide : guide
    }
    private var voiceControlTexts: [String] {
        ["타이머가 시작됐어요.", "타이머를 다시 시작했어요.", "타이머를 잠깐 멈췄어요. 불은 직접 확인해주세요.", "30초를 추가했습니다.", "60초를 추가했습니다.", "120초를 추가했습니다."]
    }
    func warmVoice() {
        guard data.voiceEnabled, let session = data.session else { return }
        let texts = session.recipe.steps.dropFirst(session.stepIndex).map { cookingNarration(for: $0, recipe: session.recipe) }
        voice.preload(["타이머가 시작됐어요."] + texts + Array(voiceControlTexts.dropFirst()), endpoint: AIConnection.configuredEndpoint(data.speechEndpoint, fallback: AIConnection.localSpeech))
    }
    func warmRecipeVoice(_ recipe: Recipe) {
        guard data.voiceEnabled else { return }
        let flow = CookingFlow.prepare(recipe, kitchen: kitchen)
        let texts = flow.steps.map { cookingNarration(for: $0, recipe: flow) }
        voice.preload(["타이머가 시작됐어요."] + texts + Array(voiceControlTexts.dropFirst()), endpoint: AIConnection.configuredEndpoint(data.speechEndpoint, fallback: AIConnection.localSpeech))
    }
    func saveReview(_ review: Review) {
        guard var session = data.session, session.state == .completed else { return }
        session.review = review; session.state = .saved
        if let index = data.history.firstIndex(where: { $0.id == session.id }) { data.history[index] = session } else { data.history.insert(session, at: 0) }
        data.session = session; selectedTab = 2
    }
    func requestNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            notificationStatus = granted ? "잠금 화면에서도 타이머 종료를 알립니다." : "알림이 꺼져 있습니다. 앱으로 돌아오면 남은 시간을 복원합니다."
            updateNotification()
        } catch { notificationStatus = "알림을 사용할 수 없습니다. 화면에서 타이머를 확인해주세요." }
    }
    func updateNotification() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard let session = data.session, session.state == .cooking, session.phase == .active, let end = session.targetEndAt, end > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "CookFlow · 타이머 종료"
        content.body = "\(session.currentStep?.title ?? "현재 단계") 타이머가 끝났어요. 앱으로 돌아오면 다음 안내로 넘어가며, 이전 단계로 돌아갈 수 있어요."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "cooking-timer", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false))
        center.add(request) { _ in }
    }

    func reviseRemaining(amounts: [String: Double], remove: Set<String>, water: Int?) -> Bool {
        guard var session = data.session else { return false }
        do {
            try RecipeRevisionEngine.revise(&session, amounts: amounts, remove: remove, waterML: water, note: "사용자가 남은 재료 분량을 변경했습니다.")
            data.session = session; updateNotification(); return true
        } catch { message = error.localizedDescription; return false }
    }
    func armVoiceInput() {
        guard !voice.speaking, !decidingVoice else { return }
        ingredientVoiceUntil = Date().addingTimeInterval(45)
    }
    @Published private(set) var decidingVoice = false
    func receiveVoice(_ text: String, expectedStepID: UUID?, expectedVisit: Int) {
        guard let session = data.session, session.state == .cooking || session.state == .paused,
              foreground, cookingScreenVisible, handsFreeEnabled,
              expectedStepID == session.currentStep?.id, expectedVisit == session.events.count, !voice.speaking, !decidingVoice else { scheduleListening(); return }
        voice.stopListening()
        let commandText = text
        let endpoint = AIConnection.configuredEndpoint(data.decisionEndpoint, fallback: AIConnection.localDecision)
        guard !endpoint.isEmpty else {
            guard let command = CookingVoiceCommand.parse(commandText) else { message = "음성 AI를 사용할 수 없어요. 아래 단계 버튼으로 진행해주세요."; return }
            applyVoiceCommand(command, session: session, expectedStepID: expectedStepID, expectedVisit: expectedVisit)
            return
        }
        decidingVoice = true
        let window = ingredientVoiceUntil
        voiceFeedback = nil
        Task {
            defer { decidingVoice = false; scheduleListening() }
            do {
                let decision = try await AIConnection.voiceDecision(text: commandText, session: session, endpoint: endpoint)
                guard let current = data.session, current.id == session.id, current.currentStep?.id == expectedStepID,
                      current.events.count == expectedVisit, !voice.speaking, foreground, cookingScreenVisible, handsFreeEnabled else { return }
                if decision.intent == "keep" {
                    switch decision.reason {
                    case "uncertain": voiceFeedback = "말을 정확히 처리하지 못했어요. 화면의 단계 버튼을 누르거나 안내를 다시 들을 수 있어요."
                    case "partial_action": voiceFeedback = "남은 재료를 모두 넣은 뒤 알려주세요."
                    case "timer_running": voiceFeedback = "타이머는 계속 진행 중이에요."
                    default: voiceFeedback = nil
                    }
                    return
                }
                let threshold = ["heat", "remaining", "repeat"].contains(decision.intent) ? 0.65 : 0.85
                guard decision.confidence >= threshold, decision.confidence <= 1 else { voiceFeedback = "명령을 확인하지 못했어요. 단계 버튼으로 진행하거나 안내를 다시 들을 수 있어요."; return }
                switch decision.intent {
                case "skip":
                    voiceFeedback = "음성으로 조리 시간을 건너뛰지 않아요."
                    return
                case "confirm":
                    guard let action = CookingVoiceCommand.decisionAction(intent: decision.intent, session: current, expectedStepID: expectedStepID, expectedVisit: expectedVisit, validUntil: window, speaking: voice.speaking) else {
                        voiceFeedback = current.phase == .active ? "타이머는 계속 진행 중이에요. 화면 버튼으로 시간을 조절할 수 있어요." : "화면의 단계 버튼으로 계속 진행할 수 있어요."
                        return
                    }
                    voiceFeedback = nil; ingredientVoiceUntil = nil; perform(action)
                case "pause": if current.state == .cooking { perform(.pause) }
                case "resume": if current.state == .paused { perform(.resume) }
                case "repeat": speakCurrent()
                case "reset": if current.state == .cooking && current.phase == .active { perform(.resetTimer) }
                case "extend30": if current.state == .cooking && current.phase == .active { perform(.addTime(30)) }
                case "extend60": if current.state == .cooking && current.phase == .active { perform(.addTime(60)) }
                case "extend120": if current.state == .cooking && current.phase == .active { perform(.addTime(120)) }
                case "remaining": say("남은 시간은 \(RecipeEngine.time(current.remaining()))입니다.")
                case "heat": if let step = current.currentStep { say(current.recipe.kitchen.spokenSetting(step.heatTo)) }
                default:
                    voiceFeedback = nil
                }
            } catch {
                // A transport failure never grants permission to change the cooking state.
                guard let current = data.session, current.id == session.id, current.currentStep?.id == expectedStepID,
                      current.events.count == expectedVisit, foreground, cookingScreenVisible, handsFreeEnabled, !voice.speaking else { return }
                voiceFeedback = "음성 서버 응답이 늦어 현재 단계는 유지했어요. 화면 버튼으로 진행할 수 있어요."
            }
        }
    }
    private func applyVoiceCommand(_ command: CookingVoiceCommand, session: CookingSession, expectedStepID: UUID?, expectedVisit: Int) {
        switch command {
        case .ingredientsAdded:
            guard let action = CookingVoiceCommand.confirmationAction(session: session, expectedStepID: expectedStepID, expectedVisit: expectedVisit, validUntil: ingredientVoiceUntil, speaking: voice.speaking) else {
                message = "재료 투입 확인은 안내 직후에만 받아요. 다시 듣거나 타이머 시작 버튼을 눌러주세요."
                return
            }
            ingredientVoiceUntil = nil
            perform(action)

        case .pause: perform(.pause)
        case .resume: perform(.resume)
        case .extend(let seconds): perform(.addTime(seconds))
        case .repeatGuide: speakCurrent()
        case .remainingTime: say("남은 시간은 \(RecipeEngine.time(session.remaining()))입니다.")
        case .heat:
            if let step = session.currentStep { say(session.recipe.kitchen.spokenSetting(step.heatTo)) }
        }
    }
}
