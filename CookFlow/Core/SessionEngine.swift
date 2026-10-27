import Foundation

public enum SessionAction {
    case approvePreparation(String), approveAllPreparation, beginCooking, startTimer, resetTimer, timerExpired, advanceAfterTimer, previous, done, finishEarly, skipCurrent, pause, resume, addTime(Int), cancel
}
public enum SessionEngine {
    @discardableResult public static func apply(_ action: SessionAction, to session: inout CookingSession, key: String = UUID().uuidString, at now: Date = Date()) throws -> Bool {
        guard !session.processedKeys.contains(key) else { return false }
        let stepID = session.currentStep?.id
        var eventType = ""
        var detail = ""
        func reject(_ text: String) -> RecipeError { .invalid(text) }
        switch action {
        case .approvePreparation(let id):
            guard session.state == .preparing, let index = session.checks.firstIndex(where: { $0.id == id }) else { throw reject("준비 중인 재료가 아닙니다.") }
            session.checks[index].status = .approved
            session.checks[index].feedback = "사용자가 준비를 마쳤습니다."
            eventType = "PREP_USER_APPROVED"; detail = id
        case .approveAllPreparation:
            guard session.state == .preparing else { throw reject("재료 준비 화면에서 시작해주세요.") }
            for index in session.checks.indices where session.checks[index].status != .approved {
                session.checks[index].status = .approved
                session.checks[index].feedback = "사용자가 재료 준비를 마쳤습니다."
            }
            eventType = "PREP_ALL_APPROVED"; detail = "전체 손질·계량 직접 확인"
        case .beginCooking:
            guard session.state == .preparing, session.checks.allSatisfy({ $0.status == .approved }) else { throw reject("재료 준비를 마치면 조리를 시작해주세요.") }
            session.state = .cooking; session.startedAt = now; session.phase = .ready; eventType = "BEGIN_COOKING"
        case .startTimer:
            guard session.state == .cooking, session.phase == .ready, let step = session.currentStep, step.durationSeconds > 0 else { throw reject("현재 단계에서는 타이머를 시작할 수 없습니다.") }
            session.targetEndAt = now.addingTimeInterval(Double(step.durationSeconds)); session.phase = .active; eventType = "START_TIMER"
        case .resetTimer:
            guard session.state == .cooking, session.phase == .active, (session.currentStep?.durationSeconds ?? 0) > 0 else { throw reject("진행 중인 타이머만 되돌릴 수 있습니다.") }
            session.targetEndAt = nil; session.pausedSeconds = nil; session.phase = .ready
            eventType = "RESET_TIMER"; detail = "재료 투입 전 타이머 시작 취소"
        case .timerExpired:
            guard session.state == .cooking, session.phase == .active, session.remaining(at: now) == 0 else { return false }
            session.phase = .awaitingConfirmation; eventType = "TIMER_EXPIRED"
        case .advanceAfterTimer:
            guard session.state == .cooking, session.phase == .active, session.remaining(at: now) == 0 else { return false }
            if session.stepIndex + 1 < session.recipe.steps.count {
                session.stepIndex += 1; session.targetEndAt = nil; session.pausedSeconds = nil; session.phase = .ready
            } else {
                session.phase = .awaitingConfirmation
            }
            eventType = "AUTO_ADVANCE"; detail = "타이머 종료 후 다음 안내"
        case .previous:
            guard [.cooking, .paused].contains(session.state), session.stepIndex > 0 else { throw reject("돌아갈 이전 단계가 없습니다.") }
            session.stepIndex -= 1; session.state = .cooking; session.pausedSeconds = nil
            if session.currentStep?.durationSeconds ?? 0 > 0 {
                session.phase = .awaitingConfirmation; session.targetEndAt = now
            } else { session.phase = .ready; session.targetEndAt = nil }
            for index in session.auxiliaryTimers.indices {
                if let remaining = session.auxiliaryTimers[index].pausedSeconds {
                    session.auxiliaryTimers[index].targetEndAt = now.addingTimeInterval(remaining)
                    session.auxiliaryTimers[index].pausedSeconds = nil
                }
            }
            eventType = "PREVIOUS_STEP"; detail = "이전 단계에서 익힘 확인 또는 시간 추가"
        case .done, .finishEarly, .skipCurrent:
            guard session.state == .cooking, let step = session.currentStep else { throw reject("진행 중인 조리가 없습니다.") }
            var early = false
            var skip = false
            if case .skipCurrent = action { skip = true }
            if case .finishEarly = action {
                guard step.durationSeconds > 0, session.phase == .active else { throw reject("시작한 타이머에서 실제 익힘을 확인한 뒤 넘어갈 수 있습니다.") }
                early = true
            }
            if !early && !skip && step.durationSeconds > 0 && session.phase != .awaitingConfirmation { throw reject("타이머를 시작하거나 실제 익힘을 확인한 뒤 넘어가주세요.") }
            session.stepIndex += 1; session.targetEndAt = nil; session.pausedSeconds = nil; session.phase = .ready
            if session.stepIndex >= session.recipe.steps.count { session.state = .completed; session.completedAt = now; session.auxiliaryTimers = [] }
            eventType = skip ? "USER_SKIP" : early ? "USER_DONE_EARLY" : "USER_DONE"; if skip { detail = "사용자의 명시적인 음성 요청으로 단계 건너뛰기" } else if early { detail = "사용자가 실제 익힘을 확인하고 타이머보다 먼저 완료" }
        case .pause:
            guard session.state == .cooking else { throw reject("진행 중에만 일시정지할 수 있습니다.") }
            session.pausedSeconds = session.targetEndAt.map { max(0, $0.timeIntervalSince(now)) }
            session.targetEndAt = nil
            for index in session.auxiliaryTimers.indices {
                if let end = session.auxiliaryTimers[index].targetEndAt {
                    session.auxiliaryTimers[index].pausedSeconds = max(0, end.timeIntervalSince(now))
                    session.auxiliaryTimers[index].targetEndAt = nil
                }
            }
            session.state = .paused; eventType = "PAUSE"
        case .resume:
            guard session.state == .paused else { throw reject("일시정지 상태가 아닙니다.") }
            if let remaining = session.pausedSeconds { session.targetEndAt = now.addingTimeInterval(remaining) }
            session.pausedSeconds = nil
            for index in session.auxiliaryTimers.indices {
                if let remaining = session.auxiliaryTimers[index].pausedSeconds {
                    session.auxiliaryTimers[index].targetEndAt = now.addingTimeInterval(remaining)
                    session.auxiliaryTimers[index].pausedSeconds = nil
                }
            }
            session.state = .cooking; eventType = "RESUME"
        case .addTime(let seconds):
            guard [30, 60, 120].contains(seconds), [.cooking, .paused].contains(session.state), session.currentStep?.durationSeconds ?? 0 > 0, session.phase != .ready else { throw reject("시작한 타이머에 30초·1분·2분을 추가할 수 있습니다.") }
            if session.state == .paused { session.pausedSeconds = (session.pausedSeconds ?? 0) + Double(seconds) }
            else { session.targetEndAt = max(session.targetEndAt ?? now, now).addingTimeInterval(Double(seconds)) }
            session.phase = .active; eventType = "ADD_TIME"; detail = "\(seconds)초"
        case .cancel:
            guard ![.completed, .saved, .cancelled].contains(session.state) else { throw reject("이미 종료된 조리입니다.") }
            session.state = .cancelled; session.auxiliaryTimers = []; session.targetEndAt = nil; session.pausedSeconds = nil; session.completedAt = now; eventType = "CANCEL"
        }
        session.processedKeys.insert(key)
        session.events.append(.init(at: now, stepID: stepID, type: eventType, detail: detail))
        return true
    }

    public static func addAuxiliaryTimer(to session: inout CookingSession, label: String, seconds: Int, at now: Date = Date()) throws {
        guard session.state == .cooking, (30...3600).contains(seconds), session.auxiliaryTimers.count < 4 else { throw RecipeError.invalid("조리 중에 30초~60분 보조 타이머를 최대 4개 추가할 수 있습니다.") }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw RecipeError.invalid("보조 타이머 이름을 입력해주세요.") }
        session.auxiliaryTimers.append(.init(label: name, targetEndAt: now.addingTimeInterval(Double(seconds))))
        session.events.append(.init(at: now, stepID: session.currentStep?.id, type: "AUX_TIMER_START", detail: "\(name) · \(seconds)초"))
    }
}

/// Deliberately accepts complete, single commands rather than matching words in conversation.
public enum CookingVoiceCommand: Equatable {
    case ingredientsAdded, pause, resume, extend(Int), repeatGuide, remainingTime, heat
    public static func isConfident(_ scores: [Double]) -> Bool {
        guard !scores.isEmpty, scores.allSatisfy({ $0.isFinite && (0.65...1).contains($0) }) else { return false }
        return scores.reduce(0, +) / Double(scores.count) >= 0.85
    }
    public static func confirmationGoal(for step: CookingStep) -> String {
        guard step.durationSeconds > 0 else { return step.instruction }
        if step.requiredItems.isEmpty || step.timerStartEvent == "화력 설정 확인 후 시작" {
            return "불을 안내한 세기로 맞춰주세요."
        }
        let names = step.requiredItems.map { $0.ingredient.name }.joined(separator: ", ")
        return "\(names)을 모두 넣어주세요."
    }
    public static func decisionAction(intent: String, session: CookingSession, expectedStepID: UUID?, expectedVisit: Int, validUntil: Date?, speaking: Bool, at now: Date = Date()) -> SessionAction? {
        guard session.state == .cooking, expectedStepID == session.currentStep?.id,
              expectedVisit == session.events.count, !speaking, let validUntil, now <= validUntil,
              let step = session.currentStep else { return nil }
        // Classification never grants permission to skip a timer or complete a running phase.
        guard intent == "confirm", session.phase == .ready else { return nil }
        return step.durationSeconds > 0 ? .startTimer : .done
    }
    public static func confirmationAction(session: CookingSession, expectedStepID: UUID?, expectedVisit: Int, validUntil: Date?, speaking: Bool, at now: Date = Date()) -> SessionAction? {
        guard session.state == .cooking, session.phase == .ready,
              expectedStepID == session.currentStep?.id, expectedVisit == session.events.count,
              !speaking, let validUntil, now <= validUntil,
              (session.currentStep?.durationSeconds ?? 0) > 0 else { return nil }
        return .startTimer
    }
    public static func parse(_ text: String) -> CookingVoiceCommand? {
        guard !text.contains("?") && !text.contains("？") else { return nil }
        let normalized = text.filter { !$0.isWhitespace && !".!?。！？".contains($0) }
        switch normalized {
        case "넣었어", "넣었어요", "다넣었어", "다넣었어요", "했어", "했어요", "다했어", "다했어요": return .ingredientsAdded
        case "잠깐멈춰", "멈춰", "일시정지": return .pause
        case "계속", "계속해", "이어서": return .resume
        case "더기다려", "30초추가", "삼십초추가": return .extend(30)
        case "1분추가", "일분추가": return .extend(60)
        case "2분추가", "이분추가": return .extend(120)
        case "다시말해줘", "다시들려줘", "다시읽어줘", "레시피다시읽어줘", "요리법다시읽어줘",
             "현재단계다시읽어줘", "이단계다시읽어줘", "조리순서다시알려줘", "현재단계다시설명해줘": return .repeatGuide
        case "남은시간", "시간얼마남았어": return .remainingTime
        case "화력몇단계", "불몇단계": return .heat
        default: return nil
        }
    }
}


public enum HandsFreeVoicePolicy {
    public static func canListen(session: CookingSession?, enabled: Bool, visible: Bool, foreground: Bool, speaking: Bool, deciding: Bool) -> Bool {
        guard let session else { return false }
        let waitingForCommand = session.state == .paused || (session.state == .cooking && session.phase == .ready)
        return enabled && visible && foreground && !speaking && !deciding && waitingForCommand
    }
}
public enum OfflineVoiceIntent {
    public static func parse(_ text: String) -> String? {
        // Do not strip question marks: questions must never become confirmations.
        guard !text.contains("?") && !text.contains("？") else { return nil }
        let t = text.filter { !$0.isWhitespace && !".!。！".contains($0) }
        switch t {
        case "했어", "했어요", "다했어", "다했어요", "넣었어", "넣었어요", "다넣었어", "다넣었어요": return "confirm"
        case "잠깐멈춰", "멈춰", "일시정지": return "pause"
        case "계속", "계속해", "이어서": return "resume"
        case "아직안넣었어", "아직안넣었어요": return "reset"
        default: return nil
        }
    }
    public static func action(_ intent: String, session: CookingSession, stepID: UUID?, visit: Int, at now: Date = Date()) -> SessionAction? {
        guard session.currentStep?.id == stepID, session.events.count == visit else { return nil }
        switch intent {
        case "confirm": return CookingVoiceCommand.decisionAction(intent: intent, session: session, expectedStepID: stepID, expectedVisit: visit, validUntil: now.addingTimeInterval(1), speaking: false, at: now)
        case "pause": return session.state == .cooking ? .pause : nil
        case "resume": return session.state == .paused ? .resume : nil
        case "reset": return session.state == .cooking && session.phase == .active ? .resetTimer : nil
        default: return nil
        }
    }
}

/// Segment short commands after speech and silence; quiet microphone windows never become AI requests.
public struct VoiceActivityWindow {
    public enum Result { case waiting, speaking, finish, silence }
    private var noiseFloor: Double = -60
    private var calibration: [Double] = []
    private var speechDuration: Double = 0
    private var consecutive: Double = 0
    private var longest: Double = 0
    private var lastSpeech: Double?
    private var previousTime: Double = 0
    public init() {}
    public mutating func observe(decibels: Double, elapsed: Double) -> Result {
        guard decibels.isFinite, elapsed.isFinite, elapsed >= previousTime else { return .waiting }
        let delta = min(0.1, elapsed - previousTime); previousTime = elapsed
        if elapsed <= 0.35 {
            calibration.append(decibels)
            let levels = calibration.sorted()
            noiseFloor = levels[Int(Double(levels.count - 1) * 0.7)]
            return .waiting
        }
        let threshold = max(-46, noiseFloor + 10)
        if decibels > threshold {
            speechDuration += delta; consecutive += delta; longest = max(longest, consecutive); lastSpeech = elapsed
        } else {
            consecutive = 0
            if lastSpeech == nil { noiseFloor = noiseFloor * 0.95 + decibels * 0.05 }
        }
        let candidate = speechDuration >= 0.4 && longest >= 0.28
        if candidate, let lastSpeech, elapsed - lastSpeech >= 1.1 { return .finish }
        if elapsed >= 8 { return candidate ? .finish : .silence }
        return lastSpeech == nil ? .waiting : .speaking
    }
}

