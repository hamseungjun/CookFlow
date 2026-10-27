import XCTest
@testable import CookFlowCore

final class VoiceConfirmationTests: XCTestCase {
    private func ready() throws -> CookingSession {
        var session = CookingSession(recipe: CookingFlow.prepare(try RecipeEngine.generate(selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: .init())))
        try SessionEngine.apply(.approveAllPreparation, to: &session)
        try SessionEngine.apply(.beginCooking, to: &session)
        return session
    }
    func testTimedConfirmationAsksForSetupAndUntimedConfirmationKeepsTheAction() throws {
        let session = try ready()
        var step = try XCTUnwrap(session.currentStep)
        let goal = CookingVoiceCommand.confirmationGoal(for: step)
        XCTAssertFalse(goal.contains("끓여"))
        XCTAssertFalse(goal.contains("볶아"))
        for item in step.requiredItems { XCTAssertTrue(goal.contains(item.ingredient.name)) }
        step.durationSeconds = 0
        XCTAssertEqual(CookingVoiceCommand.confirmationGoal(for: step),step.instruction)
    }
    func testMicrophoneTurnsOffForTimerAndReturnsOnlyWhenActionIsNeeded() throws {
        var session = try ready()
        func enabled(_ session: CookingSession, speaking: Bool = false) -> Bool {
            HandsFreeVoicePolicy.canListen(session: session, enabled: true, visible: true, foreground: true, speaking: speaking, deciding: false)
        }
        XCTAssertTrue(enabled(session))
        try SessionEngine.apply(.startTimer, to: &session)
        XCTAssertFalse(enabled(session))
        try SessionEngine.apply(.pause, to: &session)
        XCTAssertTrue(enabled(session))
        try SessionEngine.apply(.resume, to: &session)
        XCTAssertFalse(enabled(session))
        try SessionEngine.apply(.resetTimer, to: &session)
        XCTAssertTrue(enabled(session))
        try SessionEngine.apply(.startTimer, to: &session)
        try SessionEngine.apply(.advanceAfterTimer, to: &session, at: session.targetEndAt!)
        XCTAssertFalse(enabled(session, speaking: true))
        XCTAssertTrue(enabled(session))
        try SessionEngine.apply(.previous, to: &session)
        XCTAssertFalse(enabled(session)) // Completed waits do not reopen the microphone.
        try SessionEngine.apply(.addTime(30), to: &session)
        XCTAssertFalse(enabled(session))
        try SessionEngine.apply(.cancel, to: &session)
        XCTAssertFalse(enabled(session))
    }
    func testMicrophoneSilenceNeverSubmitsAndSpeechWaitsForEnd() {
        var quiet = VoiceActivityWindow()
        for sample in 1...159 { XCTAssertEqual(quiet.observe(decibels: -65, elapsed: Double(sample) * 0.05), .waiting) }
        XCTAssertEqual(quiet.observe(decibels: -65, elapsed: 8), .silence)
        var speech = VoiceActivityWindow()
        for sample in 1...10 { _ = speech.observe(decibels: -60, elapsed: Double(sample) * 0.05) }
        for sample in 11...20 { XCTAssertEqual(speech.observe(decibels: -22, elapsed: Double(sample) * 0.05), .speaking) }
        XCTAssertEqual(speech.observe(decibels: -60, elapsed: 1.5), .speaking)
        XCTAssertEqual(speech.observe(decibels: -60, elapsed: 2.2), .finish)
        var noise = VoiceActivityWindow()
        for sample in 1...160 {
            let value = noise.observe(decibels: -36, elapsed: Double(sample) * 0.05)
            XCTAssertEqual(value, sample == 160 ? .silence : .waiting)
        }
    }
    func testConfirmationStartsWaitThenAutomaticallyAdvancesWithoutSkippingCooking() throws {
        for phrase in ["넣었어", "넣었어요!", "했어", "했어요", "다 했어"] {
            XCTAssertEqual(CookingVoiceCommand.parse(phrase), .ingredientsAdded)
            var session = try ready()
            let now = Date(timeIntervalSince1970: 1000)
            let step = try XCTUnwrap(session.currentStep)
            let action = try XCTUnwrap(CookingVoiceCommand.confirmationAction(session: session, expectedStepID: step.id, expectedVisit: session.events.count, validUntil: now.addingTimeInterval(45), speaking: false, at: now))
            try SessionEngine.apply(action, to: &session, at: now)
            XCTAssertEqual(session.phase, .active)
            XCTAssertEqual(session.stepIndex, 0)
            XCTAssertNil(CookingVoiceCommand.confirmationAction(session: session, expectedStepID: step.id, expectedVisit: session.events.count, validUntil: now.addingTimeInterval(45), speaking: false, at: now))
            XCTAssertFalse(try SessionEngine.apply(.advanceAfterTimer, to: &session, at: now.addingTimeInterval(Double(step.durationSeconds) - 1)))
            XCTAssertTrue(try SessionEngine.apply(.advanceAfterTimer, to: &session, at: session.targetEndAt!))
            XCTAssertEqual(session.stepIndex, 1)
            XCTAssertEqual(session.phase, .ready)
        }
    }
    func testExpiredStaleAndAppSpeechCannotConfirm() throws {
        let session = try ready()
        let now = Date(timeIntervalSince1970: 1000)
        let id = session.currentStep!.id
        let visit = session.events.count
        XCTAssertNil(CookingVoiceCommand.confirmationAction(session: session, expectedStepID: id, expectedVisit: visit, validUntil: nil, speaking: false, at: now))
        XCTAssertNil(CookingVoiceCommand.confirmationAction(session: session, expectedStepID: id, expectedVisit: visit, validUntil: now.addingTimeInterval(-1), speaking: false, at: now))
        XCTAssertNil(CookingVoiceCommand.confirmationAction(session: session, expectedStepID: UUID(), expectedVisit: visit, validUntil: now.addingTimeInterval(45), speaking: false, at: now))
        XCTAssertNil(CookingVoiceCommand.confirmationAction(session: session, expectedStepID: id, expectedVisit: visit - 1, validUntil: now.addingTimeInterval(45), speaking: false, at: now))
        XCTAssertNil(CookingVoiceCommand.confirmationAction(session: session, expectedStepID: id, expectedVisit: visit, validUntil: now.addingTimeInterval(45), speaking: true, at: now))
        for phrase in ["아직 안 했어", "안 넣었어", "방금 했어라고 말했어", "넣었어 다음", "했어?"] {
            XCTAssertNil(CookingVoiceCommand.parse(phrase))
        }
    }
    func testDecisionCompletionSkipAndLateReply() throws {
        var session = try ready()
        let now = Date()
        let id = session.currentStep!.id
        let visit = session.events.count
        let window = now.addingTimeInterval(45)
        func action(_ intent: String, _ snapshot: CookingSession, _ expected: Int) -> SessionAction? {
            CookingVoiceCommand.decisionAction(intent: intent, session: snapshot, expectedStepID: id, expectedVisit: expected, validUntil: window, speaking: false, at: now)
        }
        XCTAssertNil(action("keep", session, visit))
        try SessionEngine.apply(try XCTUnwrap(action("confirm", session, visit)), to: &session, at: now)
        XCTAssertEqual(session.phase, .active)
        XCTAssertEqual(session.stepIndex, 0)
        XCTAssertNil(action("confirm", session, session.events.count))
        XCTAssertNil(action("skip", session, visit)) // Late reply cannot affect a changed visit.
        XCTAssertNil(action("skip", session, session.events.count))
        XCTAssertEqual(session.stepIndex, 0)
        XCTAssertEqual(session.phase, .active)
        XCTAssertNil(OfflineVoiceIntent.action("confirm", session: session, stepID: id, visit: session.events.count, at: now))
        try SessionEngine.apply(.advanceAfterTimer, to: &session, at: session.targetEndAt!)
        XCTAssertEqual(session.stepIndex, 1)
        var untimed = try ready()
        untimed.recipe.steps[0].durationSeconds = 0
        let next = CookingVoiceCommand.decisionAction(intent: "confirm", session: untimed, expectedStepID: untimed.currentStep?.id, expectedVisit: untimed.events.count, validUntil: window, speaking: false, at: now)
        try SessionEngine.apply(try XCTUnwrap(next), to: &untimed)
        XCTAssertEqual(untimed.stepIndex, 1)
    }

    func testBriefClatterCannotSubmitAudio() {
        var window = VoiceActivityWindow()
        var final: VoiceActivityWindow.Result = .waiting
        for sample in 1...160 {
            let db: Double = (20...22).contains(sample) ? -15 : -60
            final = window.observe(decibels: db, elapsed: Double(sample) * 0.05)
            XCTAssertNotEqual(final, .finish)
        }
        XCTAssertEqual(final, .silence)
    }
    func testHighSteadyFanDoesNotTriggerCapture() {
        var window = VoiceActivityWindow()
        for sample in 1...160 {
            let result = window.observe(decibels: -20, elapsed: Double(sample) * 0.05)
            XCTAssertEqual(result, sample == 160 ? .silence : .waiting)
        }
    }

}
