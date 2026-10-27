import XCTest
@testable import CookFlowCore

final class CookingFlowTests: XCTestCase {
    func testKitchenRebindPreservesStageIdentityAndTimers() throws {
        let original = CookingFlow.prepare(try RecipeEngine.generate(selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: .init(), menu: .doenjang))
        var kitchen = KitchenProfile(); kitchen.numericMap["mediumHigh"] = 7
        let numeric = CookingFlow.rebindKitchen(original, to: kitchen)
        XCTAssertEqual(numeric.steps.map(\.id), original.steps.map(\.id))
        XCTAssertEqual(numeric.steps.map(\.durationSeconds), original.steps.map(\.durationSeconds))
        let hot = try XCTUnwrap(numeric.steps.first { $0.heatTo == .mediumHigh })
        XCTAssertEqual(hot.deviceSetting, "7단계")
        XCTAssertTrue(hot.speechText.contains("7단계"))
        kitchen.controlType = .dial; kitchen.dialConfiguration = .clockwiseFromOff()
        let dial = CookingFlow.rebindKitchen(numeric, to: kitchen)
        XCTAssertTrue(dial.steps.first { $0.heatTo == .mediumHigh }!.speechText.contains("다이얼"))
        XCTAssertFalse(dial.steps.first { $0.heatTo == .mediumHigh }!.speechText.contains("7단계"))
        let general = CookingFlow.rebindKitchen(dial, to: .generalGuidance())
        XCTAssertEqual(general.steps.first { $0.heatTo == .mediumHigh }!.deviceSetting, "중강불")
    }
    func testHandsFreeOnlyListensOnVisibleForegroundCookingScreen() throws {
        var session = CookingSession(recipe: try RecipeEngine.generate(selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: .init()))
        XCTAssertFalse(HandsFreeVoicePolicy.canListen(session: session, enabled: true, visible: true, foreground: true, speaking: false, deciding: false))
        try SessionEngine.apply(.approveAllPreparation, to: &session)
        try SessionEngine.apply(.beginCooking, to: &session)
        XCTAssertTrue(HandsFreeVoicePolicy.canListen(session: session, enabled: true, visible: true, foreground: true, speaking: false, deciding: false))
        for flags in [(false,true,true,false,false),(true,false,true,false,false),(true,true,false,false,false),(true,true,true,true,false),(true,true,true,false,true)] {
            XCTAssertFalse(HandsFreeVoicePolicy.canListen(session: session, enabled: flags.0, visible: flags.1, foreground: flags.2, speaking: flags.3, deciding: flags.4))
        }
    }
    func testOfflineCompletionNeverAcceptsQuestionsNegationOrFuzzyWords() {
        for text in ["넣었어?", "안 넣었어", "해서", "넣었서", "다음으로 넘어가", "누가 했어", "넣었어라고 했어"] { XCTAssertNil(OfflineVoiceIntent.parse(text), text) }
        XCTAssertEqual(OfflineVoiceIntent.parse("넣었어요"), "confirm")
        XCTAssertEqual(OfflineVoiceIntent.parse("아직 안 넣었어"), "reset")
    }
    func testSundubuPreheatsBeforeOilAndAromaticsAndKeepsChiliLow() throws {
        let flow = CookingFlow.prepare(try RecipeEngine.generate(selected: RecipeMenu.sundubu.defaultIngredients, quantities: [:], preferences: .init(), menu: .sundubu))
        let preheat = try XCTUnwrap(flow.steps.first)
        XCTAssertEqual(preheat.title, "팬·냄비 예열")
        XCTAssertEqual(preheat.heatTo, .medium)
        XCTAssertEqual(preheat.durationSeconds, 120)
        XCTAssertEqual(preheat.requiredItems.map(\.id), ["oil"])
        XCTAssertEqual(preheat.timerStartEvent, "재료 투입 확인 후 시작")
        XCTAssertTrue(preheat.speechText.hasPrefix("불은 중불"))
        let fry = flow.steps[1]
        XCTAssertEqual(fry.title, "양파·마늘 볶기")
        XCTAssertTrue(fry.speechText.hasPrefix("불은 중약불"))
        XCTAssertFalse(fry.speechText.contains("식용유"))
        XCTAssertFalse(preheat.speechText.contains("제조사"))
        XCTAssertTrue(preheat.speechText.contains("식용유"))
        XCTAssertEqual(flow.steps.first { $0.title == "고추기름 내기" }?.heatTo, .low)
        XCTAssertEqual(flow, CookingFlow.prepare(flow))
        var session = CookingSession(recipe: flow)
        try SessionEngine.apply(.approveAllPreparation, to: &session)
        try SessionEngine.apply(.beginCooking, to: &session)
        try SessionEngine.apply(.startTimer, to: &session)
        try SessionEngine.apply(.advanceAfterTimer, to: &session, at: session.targetEndAt!)
        XCTAssertEqual(session.currentStep?.title, "양파·마늘 볶기")
        XCTAssertEqual(session.phase, .ready)
    }
    func testImportedTimedHeatPreservesPreheatDirections() throws {
        var recipe = try RecipeEngine.generate(selected: RecipeMenu.sundubu.defaultIngredients, quantities: [:], preferences: .init(), menu: .sundubu)
        var preheat = recipe.steps[0]
        preheat.actionType = .heat; preheat.title = "팬 예열"; preheat.instruction = "팬을 2분 예열해주세요."; preheat.durationSeconds = 120
        preheat.heatTo = .medium; preheat.requiredItems = []
        recipe.steps.insert(preheat, at: 0)
        let flow = CookingFlow.prepare(recipe)
        XCTAssertEqual(flow.steps.first?.durationSeconds, 120)
        XCTAssertTrue(flow.steps.first!.speechText.contains("2분 예열"))
        XCTAssertEqual(flow.steps.filter { $0.title.contains("예열") }.count, 1)
    }
    func testBoilingAndColdOilStepsDoNotGetFryingPreheat() throws {
        let original = try RecipeEngine.generate(selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: .init())
        let flow = CookingFlow.prepare(original)
        XCTAssertEqual(flow.steps.first?.title, "육수 끓이기")
        XCTAssertTrue(flow.steps.first!.speechText.hasPrefix("물"))
        XCTAssertFalse(flow.steps.contains { $0.title == "팬·냄비 예열" })
    }
    func testDoenjangHasFewerCheckpointsAndKeepsCookingTimers() throws {
        let original = try RecipeEngine.generate(kitchen: nil, selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: Preferences(), menu: .doenjang)
        let grouped = CookingFlow.prepare(original)
        XCTAssertLessThan(grouped.steps.count, original.steps.count / 2)
        XCTAssertEqual(grouped.steps.filter { $0.actionType == .simmer }.map(\.durationSeconds), original.steps.filter { $0.actionType == .simmer }.map(\.durationSeconds))
        XCTAssertEqual(Set(grouped.steps.flatMap { $0.requiredItems.map(\.id) }), Set(original.steps.flatMap { $0.requiredItems.map(\.id) }))
        XCTAssertEqual(grouped.steps.last?.actionType, .finish)
        XCTAssertEqual(grouped.steps.last?.heatTo, .off)
        XCTAssertTrue(grouped.steps.allSatisfy { !$0.instruction.contains("완료를 눌러") })
        XCTAssertEqual(grouped.steps.first?.title, "육수 끓이기")
        XCTAssertEqual(grouped, CookingFlow.prepare(grouped))
        print("된장찌개 조리 체크포인트: \(original.steps.count) → \(grouped.steps.count)")
    }
    func testCurrentKitchenMapsNumbersAndDialWithHeatNameInSpeech() throws {
        let original = try RecipeEngine.generate(kitchen: nil, selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: Preferences(), menu: .doenjang)
        var kitchen = KitchenProfile(); kitchen.numericMap[HeatLevel.mediumHigh.rawValue] = 8; kitchen.numericMap[HeatLevel.high.rawValue] = 9
        let grouped = CookingFlow.prepare(original, kitchen: kitchen)
        let hot = try XCTUnwrap(grouped.steps.first { $0.heatTo == .mediumHigh })
        XCTAssertEqual(hot.deviceSetting, "8단계")
        XCTAssertTrue(hot.speechText.contains("8단계"))
        XCTAssertTrue(hot.speechText.contains("강불"))
        XCTAssertLessThan(hot.speechText.count, 220)
        kitchen.controlType = .dial; kitchen.dialConfiguration = DialConfiguration.clockwiseFromOff()
        let dial = CookingFlow.prepare(original, kitchen: kitchen)
        let dialStep = try XCTUnwrap(dial.steps.first { $0.heatTo != .off })
        XCTAssertTrue(dialStep.deviceSetting.contains("다이얼"))
        XCTAssertTrue(dialStep.speechText.contains(dialStep.heatTo.label))
        XCTAssertEqual(dial.kitchen.dialConfiguration, kitchen.dialConfiguration)
        let remapped = CookingFlow.prepare(grouped, kitchen: kitchen)
        XCTAssertEqual(remapped.steps.count, grouped.steps.count)
        XCTAssertEqual(remapped.steps.map { $0.flowInstructions?.count }, grouped.steps.map { $0.flowInstructions?.count })
        XCTAssertTrue(remapped.steps.first?.speechText.contains("다이얼") == true)
        XCTAssertFalse(remapped.steps.first?.speechText.contains("8단계") == true)
    }
    func testEveryHomeMealFinishesWithOnePreparationApprovalAndGroupedStages() throws {
        for menu in RecipeMenu.allCases {
            let original = try RecipeEngine.generate(selected: menu.defaultIngredients, quantities: [:], preferences: .init(), menu: menu)
            let recipe = CookingFlow.prepare(original)
            XCTAssertLessThanOrEqual(recipe.steps.count, original.steps.count, menu.title)
            var session = CookingSession(recipe: recipe)
            try SessionEngine.apply(.approveAllPreparation, to: &session)
            XCTAssertTrue(session.checks.allSatisfy { $0.status == .approved })
            try SessionEngine.apply(.beginCooking, to: &session)
            var now = Date()
            while session.state == .cooking {
                let step = try XCTUnwrap(session.currentStep)
                if step.durationSeconds > 0 {
                    try SessionEngine.apply(.startTimer, to: &session, at: now)
                    now = now.addingTimeInterval(Double(step.durationSeconds) + 1)
                    try SessionEngine.apply(.timerExpired, to: &session, at: now)
                }
                try SessionEngine.apply(.done, to: &session, at: now)
            }
            XCTAssertEqual(session.state, .completed, menu.title)
            let restored = try JSONDecoder().decode(CookingSession.self, from: JSONEncoder().encode(session))
            XCTAssertEqual(restored.recipe, recipe)
        }
    }
    func testUserCanFinishStartedTimerWithoutPretendingItExpired() throws {
        let original = try RecipeEngine.generate(kitchen: nil, selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: Preferences(), menu: .doenjang)
        var session = CookingSession(recipe: CookingFlow.prepare(original))
        for check in session.checks { try SessionEngine.apply(.approvePreparation(check.id), to: &session) }
        try SessionEngine.apply(.beginCooking, to: &session)
        XCTAssertThrowsError(try SessionEngine.apply(.finishEarly, to: &session))
        let start = Date()
        try SessionEngine.apply(.startTimer, to: &session, at: start)
        try SessionEngine.apply(.finishEarly, to: &session, at: start.addingTimeInterval(2))
        XCTAssertEqual(session.stepIndex, 1)
        XCTAssertEqual(session.events.last?.type, "USER_DONE_EARLY")
        XCTAssertNil(session.targetEndAt)
        XCTAssertEqual(session.phase, .ready)
        XCTAssertFalse(session.events.contains { $0.type == "TIMER_EXPIRED" })
    }
    func testSmallPlacementTimersDoNotBlockAIRecipe() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ai-recipe.json")
        let draft = try JSONDecoder().decode(VideoRecipeDraft.self, from: Data(contentsOf: path))
        let original = try draft.generatedRecipe(kitchen: nil, preferences: Preferences())
        let flow = CookingFlow.prepare(original)
        XCTAssertLessThan(flow.steps.count, original.steps.count)
        XCTAssertEqual(flow.steps.filter { $0.durationSeconds > 0 }.map(\.durationSeconds), original.steps.filter { $0.actionType == .simmer }.map(\.durationSeconds))
        XCTAssertTrue(flow.steps.allSatisfy { !$0.speechText.contains("이번 조리 계량:") })
    }
    func testPreparedFreshIngredientsAreSpokenAsActionsAndScreenKeepsAmounts() throws {
        let original = try RecipeEngine.generate(selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: .init(), menu: .doenjang)
        let flow = CookingFlow.prepare(original)
        let speech = flow.steps.map(\.speechText).joined(separator: " ")
        XCTAssertTrue(speech.contains("두부를 냄비에 넣어주세요"))
        XCTAssertTrue(speech.contains("애호박을 냄비에 넣어주세요"))
        XCTAssertFalse(speech.contains("½모"))
        XCTAssertFalse(speech.contains("으로 준비한"))
        XCTAssertTrue(flow.steps.contains { $0.instruction.contains("1모") })
        XCTAssertTrue(speech.contains("큰술")) // Seasoning quantities remain actionable.
        XCTAssertTrue(speech.contains("컵")) // Water is still measured.
        var saved = flow
        saved.steps = saved.steps.map { var step = $0; step.spokenInstruction = "옛날 긴 안내"; return step }
        XCTAssertEqual(CookingFlow.prepare(saved).steps.map(\.speechText), flow.steps.map(\.speechText))
    }

    func testSplitPortionsKeepTheirQuantitiesInNarration() throws {
        var recipe = try RecipeEngine.generate(selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: .init(), menu: .doenjang)
        var step = try XCTUnwrap(recipe.steps.first { $0.requiredItems.contains { $0.id == "tofu" } })
        step.flowInstructions = nil
        step.instruction = "준비한 두부 ¼모를 냄비에 넣어주세요."
        var later = step
        later.id = UUID()
        later.instruction = "나머지 두부 ¼모를 넣어주세요."
        recipe.steps = [step, later]
        XCTAssertTrue(CookingNarration.text(for: step, recipe: recipe).contains("¼모"))
        XCTAssertTrue(CookingNarration.text(for: later, recipe: recipe).contains("나머지"))
        recipe.steps = [later]
        XCTAssertTrue(CookingNarration.text(for: later, recipe: recipe).contains("¼모"))
    }

    func testDoenjangStagesFollowCookingOrderAndWaitForIngredientConfirmation() throws {
        let flow = CookingFlow.prepare(try RecipeEngine.generate(selected: RecipeMenu.doenjang.defaultIngredients.union(["stockCoin"]), quantities: [:], preferences: .init(), menu: .doenjang))
        XCTAssertEqual(flow.steps.map(\.title), ["육수 끓이기", "된장 풀기", "채소 넣고 익히기", "두부 끓이기", "간 보고, 불 끄고 완성"])
        XCTAssertEqual(flow.steps.map(\.durationSeconds), [210, 30, 300, 240, 0])
        XCTAssertTrue(flow.steps[0].requiredItems.contains { $0.id == "stockCoin" })
        XCTAssertFalse(flow.steps[1].requiredItems.contains { $0.id == "zucchini" })
        XCTAssertTrue(flow.steps[2].requiredItems.contains { $0.id == "zucchini" })
        XCTAssertTrue(flow.steps[3].requiredItems.contains { $0.id == "tofu" })
        var session = CookingSession(recipe: flow)
        try SessionEngine.apply(.approveAllPreparation, to: &session)
        let start = Date(timeIntervalSince1970: 1000)
        try SessionEngine.apply(.beginCooking, to: &session, at: start)
        XCTAssertEqual(session.phase, .ready)
        try SessionEngine.apply(.startTimer, to: &session, at: start)
        XCTAssertEqual(session.remaining(at: start), 210)
        XCTAssertThrowsError(try SessionEngine.apply(.startTimer, to: &session, at: start))
        try SessionEngine.apply(.advanceAfterTimer, to: &session, at: start.addingTimeInterval(210))
        XCTAssertEqual(session.phase, .ready)
        try SessionEngine.apply(.startTimer, to: &session, at: start.addingTimeInterval(210))
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(210)), 30)
        try SessionEngine.apply(.previous, to: &session, at: start.addingTimeInterval(220))
        XCTAssertEqual(session.phase, .awaitingConfirmation)
    }

    func testVoiceAcceptsOnlyExactNonSkippingCommands() {
        XCTAssertEqual(CookingVoiceCommand.parse("넣었어요!"), .ingredientsAdded)
        XCTAssertEqual(CookingVoiceCommand.parse("더 기다려"), .extend(30))
        XCTAssertEqual(CookingVoiceCommand.parse("1분 추가"), .extend(60))
        for text in ["다음", "완료", "화력 변경했어", "이전", "아직 안 넣었어", "넣었어 다음", "방송에서 멈춰라고 했어", "추가 재료가 있어"] {
            XCTAssertNil(CookingVoiceCommand.parse(text), text)
        }
    }
    func testAccidentallyStartedTimerCanBeResetWithoutAdvancing() throws {
        let flow = CookingFlow.prepare(try RecipeEngine.generate(selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: .init(), menu: .doenjang))
        var session = CookingSession(recipe: flow)
        try SessionEngine.apply(.approveAllPreparation, to: &session)
        try SessionEngine.apply(.beginCooking, to: &session)
        try SessionEngine.apply(.startTimer, to: &session)
        try SessionEngine.apply(.resetTimer, to: &session)
        XCTAssertEqual(session.stepIndex, 0)
        XCTAssertEqual(session.phase, .ready)
        XCTAssertNil(session.targetEndAt)
        XCTAssertFalse(try SessionEngine.apply(.advanceAfterTimer, to: &session))
    }

    func testUncertainRecognitionNeverExecutesACommand() {
        XCTAssertTrue(CookingVoiceCommand.isConfident([0.95, 0.9]))
        for scores in [[], [0.5], [0.8, 0.8], [1.0, 0.6], [Double.nan], [Double.infinity]] {
            XCTAssertFalse(CookingVoiceCommand.isConfident(scores))
        }
    }

}
