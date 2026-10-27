#if CORE_STANDALONE
import Foundation
#else
import XCTest
@testable import CookFlowCore
#endif

final class CookFlowCoreTests: XCTestCase {
    private func recipe(_ selected: Set<String> = ["tofu", "zucchini", "tojang", "stockCoin"], kitchen: KitchenProfile = .init(), preferences: Preferences = .init(), quantities: [String: Double] = [:]) throws -> Recipe {
        try RecipeEngine.generate(kitchen: kitchen, selected: selected, quantities: quantities, preferences: preferences)
    }
    private func running(_ recipe: Recipe? = nil) throws -> CookingSession {
        var session = CookingSession(recipe: try recipe ?? self.recipe())
        for check in session.checks { try SessionEngine.apply(.approvePreparation(check.id), to: &session) }
        try SessionEngine.apply(.beginCooking, to: &session, at: Date(timeIntervalSince1970: 1000))
        return session
    }
    func testPreparationUsesActionsWithoutDimensionsAndCorrectParticles() {
        for (name, cut, expected) in [("마늘", "0.3cm 이하 다지기", "마늘을 다져주세요."), ("양파", "1.5~2cm 깍둑", "양파를 깍둑썰어주세요."), ("애호박", "0.5~0.8cm 반달", "애호박을 반달 모양으로 썰어주세요."), ("대파", "0.5cm 송송", "대파를 송송 썰어주세요."), ("당근", "2mm 채썰기", "당근을 채썰어주세요.")] {
            XCTAssertEqual(PreparationGuide.instruction(name: name, cut: cut), expected)
            XCTAssertFalse(PreparationGuide.instruction(name: name, cut: cut).contains("cm"))
        }
        XCTAssertEqual(PreparationGuide.shape("0.2cm 다지기"), .chopped)
        XCTAssertEqual(PreparationGuide.shape("작게 깍둑썰기"), .dice)
        XCTAssertEqual(PreparationGuide.shape("송송"), .slice)
        XCTAssertEqual(PreparationGuide.shape("깨서 풀어두기"), .beaten)
        XCTAssertEqual(PreparationGuide.instruction(name: "계란", cut: "깨서 풀어두기"), "계란을 볼에 깨 넣고 잘 풀어주세요.")
        XCTAssertTrue(PreparationGuide.instruction(name: "순두부", cut: "봉지째 준비하고 조리할 때 숟가락으로 떠 넣기").contains("봉지째 준비"))
    }
    func testThreeMenusHaveDistinctStepsAndComplete() throws {
        for menu in [RecipeMenu.doenjang, .kimchi, .sundubu] {
            let result = try RecipeEngine.generate(selected: menu.defaultIngredients, quantities: [:], preferences: Preferences(), menu: menu)
            XCTAssertEqual(result.title, menu.title)
            XCTAssertEqual(Set(result.items.map(\.id)), menu.defaultIngredients)
            if menu == .kimchi {
                XCTAssertTrue(result.steps.contains { $0.title == "김치 충분히 끓이기" && $0.durationSeconds == 600 })
                XCTAssertFalse(result.steps.contains { $0.title == "된장 풀기" })
            }
            if menu == .sundubu {
                XCTAssertEqual(result.items.first { $0.id == "softTofu" }?.amount, 700)
                let tofu = try XCTUnwrap(result.steps.firstIndex { $0.requiredItems.contains { $0.id == "softTofu" } })
                let vegetables = try XCTUnwrap(result.steps.firstIndex { $0.title == "애호박 익히기" })
                XCTAssertGreaterThan(tofu, vegetables)
            }
            var session = try running(result)
            while let step = session.currentStep {
                if step.durationSeconds > 0 {
                    try SessionEngine.apply(.startTimer, to: &session)
                    try SessionEngine.apply(.timerExpired, to: &session, at: session.targetEndAt!)
                }
                try SessionEngine.apply(.done, to: &session)
            }
            XCTAssertEqual(session.state, .completed)
            let restored = try JSONDecoder().decode(CookingSession.self, from: JSONEncoder().encode(session))
            XCTAssertEqual(restored.recipe.title, menu.title)
        }
    }
    func testNewMenusRequireTheirMainIngredientAndCannotRemoveIt() throws {
        for menu in [RecipeMenu.kimchi, .sundubu] {
            XCTAssertThrowsError(try RecipeEngine.generate(selected: ["onion"], quantities: [:], preferences: Preferences(), menu: menu))
            let recipe = try RecipeEngine.generate(selected: menu.defaultIngredients, quantities: [:], preferences: Preferences(), menu: menu)
            var session = try running(recipe)
            XCTAssertThrowsError(try RecipeRevisionEngine.revise(&session, amounts: [:], remove: menu.essentialIngredients, waterML: nil, note: "제외"))
        }
        XCTAssertThrowsError(try RecipeEngine.generate(selected: ["softTofu", "doenjang"], quantities: [:], preferences: Preferences(), menu: .sundubu))
    }
    func testHouseholdMeasuresAndShoppingLinks() throws {
        let oil = RecipeItem(ingredient: try XCTUnwrap(Catalog.item("oil")), amount: 15)
        XCTAssertEqual(oil.householdQuantity, "약 1큰술 (15ml)")
        let tofu = RecipeItem(ingredient: try XCTUnwrap(Catalog.item("tofu")), amount: 150)
        XCTAssertEqual(tofu.householdQuantity, "약 ½모 (150g)")
        XCTAssertEqual(HouseholdMeasure.water(400), "약 2컵 (400ml)")
        let url = GroceryLinks.coupangSearch("순두부 & 김치")
        XCTAssertEqual(url.host, "www.coupang.com")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "로켓프레시 순두부 & 김치")
    }
    func testWaterRevisionUpdatesCupAndRawMeasurements() throws {
        var session = try running(recipe(["doenjang", "tofu"]))
        try RecipeRevisionEngine.revise(&session, amounts: [:], remove: [], waterML: 280, note: "물 줄이기")
        let step = try XCTUnwrap(session.recipe.steps.first { $0.title == "물 계량해 붓기" })
        XCTAssertTrue(step.instruction.contains("약 1½컵 (280ml)"))
        XCTAssertFalse(step.instruction.contains("350ml"))
    }

    func testOnlySelectedIngredientsUsed() throws {
        let selected: Set<String> = ["tofu", "zucchini", "tojang", "stockCoin"]
        let result = try recipe(selected)
        XCTAssertEqual(Set(result.items.map(\.id)), selected)
        XCTAssertTrue(result.steps.flatMap(\.requiredItems).allSatisfy { selected.contains($0.id) })
        XCTAssertFalse(result.steps.contains { $0.title.contains("볶") || $0.title.contains("기름") })
    }
    func testPasteRequiredAndStockOptional() throws {
        XCTAssertThrowsError(try recipe(["tofu", "zucchini"]))
        XCTAssertNoThrow(try recipe(["doenjang", "tofu"]))
    }
    func testServingsScaleAmountsButNotTimeLinearly() throws {
        var one = Preferences(); one.servings = 1
        var four = Preferences(); four.servings = 4
        var kitchen = KitchenProfile(); kitchen.capacity = 4000
        let a = try recipe(kitchen: kitchen, preferences: one)
        let b = try recipe(kitchen: kitchen, preferences: four)
        XCTAssertEqual(b.waterML, a.waterML * 4)
        XCTAssertEqual(b.items.first { $0.id == "tofu" }!.amount, a.items.first { $0.id == "tofu" }!.amount * 4)
        XCTAssertLessThan(b.estimatedSeconds, a.estimatedSeconds * 2)
    }
    func testDialGasUsesUserPositions() throws {
        var kitchen = KitchenProfile(); kitchen.heatingType = .gas; kitchen.controlType = .knob
        kitchen.dialMap["mediumHigh"] = "시계 방향 두 번째 눈금"
        let result = try recipe(kitchen: kitchen)
        let steps = result.steps.filter { $0.actionType == .heat }
        XCTAssertTrue(steps.contains { $0.instruction.contains("시계 방향 두 번째 눈금") })
        XCTAssertTrue(steps.allSatisfy { !$0.instruction.contains("6단계") })
        XCTAssertTrue(steps.allSatisfy { $0.instruction.contains(kitchen.setting($0.heatFrom)) && $0.instruction.contains(kitchen.setting($0.heatTo)) })
    }
    func testInvalidHeatMappingRejected() {
        var kitchen = KitchenProfile(); kitchen.maximum = 3
        XCTAssertThrowsError(try recipe(kitchen: kitchen))
        kitchen = KitchenProfile(); kitchen.numericMap["low"] = 2.5
        XCTAssertFalse(kitchen.validationErrors().isEmpty)
        kitchen.halfSteps = true
        XCTAssertTrue(kitchen.validationErrors().isEmpty)
    }
    func testInsufficientPasteRejected() {
        XCTAssertThrowsError(try recipe(quantities: ["tojang": 1]))
    }
    func testLegacyCookwareDoesNotBlockRegistrationOrRecipes() throws {
        var kitchen = KitchenProfile()
        kitchen.capacity = 0; kitchen.diameter = -1; kitchen.material = "기존 냄비"
        XCTAssertTrue(kitchen.validationErrors().isEmpty)
        let result = try recipe(kitchen: kitchen)
        XCTAssertTrue(result.warnings.contains { $0.contains("충분한 여유") })
        let placement = try XCTUnwrap(result.steps.first { $0.actionType == .placement })
        XCTAssertFalse(placement.instruction.contains("기존 냄비"))
        XCTAssertFalse(placement.instruction.contains("cm"))
        let restored = try JSONDecoder().decode(KitchenProfile.self, from: JSONEncoder().encode(kitchen))
        XCTAssertEqual(restored.id, kitchen.id)
    }

    func testCookingWithoutKitchenUsesGeneralHeatAndSurvivesReplay() throws {
        let result = try RecipeEngine.generate(selected: ["doenjang", "tofu", "zucchini"], quantities: [:], preferences: Preferences())
        XCTAssertEqual(result.kitchen.usesGeneralGuidance, true)
        XCTAssertEqual(result.kitchen.setting(.medium), "중불")
        XCTAssertEqual(result.kitchen.setting(.high), "강불")
        XCTAssertEqual(result.kitchen.setting(.off), "전원 OFF")
        let heating = result.steps.filter { $0.actionType == .heat }
        XCTAssertFalse(heating.isEmpty)
        XCTAssertTrue(heating.allSatisfy { !$0.instruction.contains("단계") && !$0.instruction.contains("기타") })
        let restored = try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(restored.kitchen.setting(.mediumHigh), "중강불")
        XCTAssertTrue(result.warnings.contains { $0.contains("주방 등록 없이") })
    }

    func testAvailableFreshAmountRespected() throws {
        let result = try recipe(quantities: ["tofu": 60])
        XCTAssertEqual(result.items.first { $0.id == "tofu" }?.amount, 60)
        XCTAssertTrue(result.warnings.contains { $0.contains("두부") && $0.contains("60g") })
    }
    func testDietConflictsRejected() {
        var preferences = Preferences(); preferences.excludeMeat = true
        XCTAssertThrowsError(try recipe(["doenjang", "pork"], preferences: preferences))
        preferences = Preferences(); preferences.excludeSeafood = true
        XCTAssertThrowsError(try recipe(["doenjang", "stockCoin"], preferences: preferences))
    }
    func testSautePrerequisitesAndAtomicActions() throws {
        var preferences = Preferences(); preferences.saute = true
        XCTAssertThrowsError(try recipe(preferences: preferences))
        let result = try recipe(["doenjang", "onion", "oil", "tofu"], preferences: preferences)
        XCTAssertTrue(result.steps.contains { $0.title == "향채 볶기" })
        XCTAssertTrue(result.steps.filter { $0.actionType == .heat }.allSatisfy { $0.durationSeconds == 0 })
        XCTAssertTrue(result.steps.filter { $0.actionType == .add }.allSatisfy { $0.durationSeconds == 0 })
    }
    func testPreparationCannotBeSkipped() throws {
        var session = CookingSession(recipe: try recipe())
        XCTAssertThrowsError(try SessionEngine.apply(.beginCooking, to: &session))
        for check in session.checks { try SessionEngine.apply(.approvePreparation(check.id), to: &session) }
        XCTAssertNoThrow(try SessionEngine.apply(.beginCooking, to: &session))
    }
    func testTimerExpiryDoesNotAdvanceAndPrematureDoneRejected() throws {
        var session = try running()
        while session.currentStep!.durationSeconds == 0 { try SessionEngine.apply(.done, to: &session) }
        let index = session.stepIndex
        let start = Date(timeIntervalSince1970: 2000)
        XCTAssertThrowsError(try SessionEngine.apply(.done, to: &session, at: start))
        try SessionEngine.apply(.startTimer, to: &session, at: start)
        XCTAssertThrowsError(try SessionEngine.apply(.done, to: &session, at: start))
        try SessionEngine.apply(.timerExpired, to: &session, at: session.targetEndAt!)
        XCTAssertEqual(session.stepIndex, index)
        XCTAssertEqual(session.phase, .awaitingConfirmation)
        try SessionEngine.apply(.done, to: &session)
        XCTAssertEqual(session.stepIndex, index + 1)
    }
    func testPauseResumeAndExtendPreserveAbsoluteTime() throws {
        var session = try running()
        while session.currentStep!.durationSeconds == 0 { try SessionEngine.apply(.done, to: &session) }
        let start = Date(timeIntervalSince1970: 2000)
        let duration = session.currentStep!.durationSeconds
        try SessionEngine.apply(.startTimer, to: &session, at: start)
        try SessionEngine.apply(.pause, to: &session, at: start.addingTimeInterval(20))
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(500)), duration - 20)
        try SessionEngine.apply(.addTime(60), to: &session)
        try SessionEngine.apply(.resume, to: &session, at: start.addingTimeInterval(1000))
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(1000)), duration + 40)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(1030)), duration + 10)
    }
    func testDuplicateEventDoesNotSkipStep() throws {
        var session = try running()
        try SessionEngine.apply(.done, to: &session, key: "same-key")
        let index = session.stepIndex
        XCTAssertFalse(try SessionEngine.apply(.done, to: &session, key: "same-key"))
        XCTAssertEqual(session.stepIndex, index)
    }
    func testPersistenceRestoresTimerAndSnapshot() throws {
        var session = try running()
        while session.currentStep!.durationSeconds == 0 { try SessionEngine.apply(.done, to: &session) }
        let start = Date(timeIntervalSince1970: 2000)
        try SessionEngine.apply(.startTimer, to: &session, at: start)
        let restored = try JSONDecoder().decode(CookingSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.currentStep, session.currentStep)
        XCTAssertEqual(restored.remaining(at: start.addingTimeInterval(10)), session.currentStep!.durationSeconds - 10)
        XCTAssertEqual(restored.events.count, session.events.count)
    }
    func testCompleteJourneyWithExplicitConfirmations() throws {
        var session = try running()
        while let step = session.currentStep {
            if step.durationSeconds > 0 {
                try SessionEngine.apply(.startTimer, to: &session)
                try SessionEngine.apply(.timerExpired, to: &session, at: session.targetEndAt!)
            }
            try SessionEngine.apply(.done, to: &session)
        }
        XCTAssertEqual(session.state, .completed)
        XCTAssertNotNil(session.completedAt)
        XCTAssertNil(session.targetEndAt)
    }
    func testCancelStopsTimer() throws {
        var session = try running()
        try SessionEngine.apply(.cancel, to: &session)
        XCTAssertEqual(session.state, .cancelled)
        XCTAssertThrowsError(try SessionEngine.apply(.done, to: &session))
    }
    func testSpeechAndScreenShareExactSource() throws {
        let result = try recipe()
        for step in result.steps {
            XCTAssertEqual(step.speechText, step.instruction)
            if step.durationSeconds > 0 { XCTAssertFalse(step.timerStartEvent.isEmpty); XCTAssertTrue(step.instruction.contains("시작")) }
            for item in step.requiredItems { XCTAssertTrue(step.instruction.contains(item.quantityText)); XCTAssertTrue(step.instruction.contains(item.ingredient.name)) }
        }
    }
    func testExpiredTimerCanBeExtendedWithoutAdvancing() throws {
        var session = try running()
        while session.currentStep!.durationSeconds == 0 { try SessionEngine.apply(.done, to: &session) }
        let index = session.stepIndex
        try SessionEngine.apply(.startTimer, to: &session)
        let end = session.targetEndAt!
        try SessionEngine.apply(.timerExpired, to: &session, at: end)
        try SessionEngine.apply(.addTime(30), to: &session, at: end.addingTimeInterval(50))
        XCTAssertEqual(session.remaining(at: end.addingTimeInterval(50)), 30)
        XCTAssertEqual(session.stepIndex, index)
        XCTAssertEqual(session.phase, .active)
    }
    func testRevisionsPreserveCompletedActionsAndRemoveOnlyFutureItems() throws {
        var session = try running(recipe(["doenjang", "potato", "tofu"]))
        try SessionEngine.apply(.done, to: &session)
        let first = session.recipe.steps[0]
        try RecipeRevisionEngine.revise(&session, amounts: ["tofu": 75], remove: ["potato"], waterML: nil, note: "두부 줄이고 감자 제외")
        XCTAssertEqual(session.recipe.steps[0], first)
        XCTAssertFalse(session.recipe.items.contains { $0.id == "potato" })
        XCTAssertFalse(session.recipe.steps.dropFirst(session.stepIndex).flatMap(\.requiredItems).contains { $0.id == "potato" })
        XCTAssertEqual(session.recipe.items.first { $0.id == "tofu" }?.amount, 75)
        XCTAssertTrue(session.recipe.steps.contains { $0.instruction.contains("두부 약 ¼모 (75g)") })
        XCTAssertEqual(session.recipe.revisions.count, 1)
    }
    func testCannotReviseAlreadyAddedItemsOrActiveTimer() throws {
        var session = try running()
        while session.currentStep!.durationSeconds == 0 { try SessionEngine.apply(.done, to: &session) }
        XCTAssertThrowsError(try RecipeRevisionEngine.revise(&session, amounts: [:], remove: [], waterML: 300, note: "물 줄이기"))
        try SessionEngine.apply(.startTimer, to: &session)
        XCTAssertThrowsError(try RecipeRevisionEngine.revise(&session, amounts: ["tofu": 100], remove: [], waterML: nil, note: "진행 중 수정"))
    }
    func testAuxiliaryTimersRestoreAndPauseTogether() throws {
        var session = try running()
        let start = Date(timeIntervalSince1970: 2000)
        try SessionEngine.addAuxiliaryTimer(to: &session, label: "별도 작업", seconds: 120, at: start)
        try SessionEngine.addAuxiliaryTimer(to: &session, label: "두 번째 작업", seconds: 60, at: start)
        try SessionEngine.apply(.pause, to: &session, at: start.addingTimeInterval(20))
        XCTAssertEqual(session.auxiliaryTimers[0].remaining(at: start.addingTimeInterval(500)), 100)
        XCTAssertEqual(session.auxiliaryTimers[1].remaining(at: start.addingTimeInterval(500)), 40)
        let bytes = try JSONEncoder().encode(session)
        session = try JSONDecoder().decode(CookingSession.self, from: bytes)
        try SessionEngine.apply(.resume, to: &session, at: start.addingTimeInterval(1000))
        XCTAssertEqual(session.auxiliaryTimers[0].remaining(at: start.addingTimeInterval(1010)), 90)
        XCTAssertEqual(session.auxiliaryTimers[1].remaining(at: start.addingTimeInterval(1010)), 30)
        XCTAssertEqual(session.stepIndex, 0)
    }

    func testVisualDialSupportsBothDirectionsAndReverseStrength() throws {
        var dial = DialConfiguration()
        dial.startAngle = 330; dial.sweep = 90; dial.clockwise = true
        XCTAssertEqual(dial.endAngle, 60)
        dial.strongAtEnd = true
        XCTAssertEqual(dial.angle(for: .low), 339)
        XCTAssertEqual(dial.angle(for: .high), 51)
        dial.clockwise = false; dial.sweep = 270
        XCTAssertEqual(dial.endAngle, 60)
        dial.strongAtEnd = false
        XCTAssertEqual(dial.angle(for: .high), 303)
        XCTAssertEqual(dial.angle(for: .low), 87)
        var kitchen = KitchenProfile(); kitchen.heatingType = .gas; kitchen.controlType = .knob; kitchen.dialConfiguration = dial
        XCTAssertTrue(kitchen.validationErrors().isEmpty)
        let result = try recipe(kitchen: kitchen)
        XCTAssertTrue(result.steps.filter { $0.actionType == .heat && $0.heatTo != .off }.allSatisfy { $0.instruction.contains("시") && !$0.instruction.contains("단계") })
    }
    func testNumericRangeRescaleAndHeatDragPreserveValidOrder() {
        var profile = KitchenProfile()
        HeatControlMath.rescale(profile: &profile, minimum: 0, maximum: 3)
        XCTAssertTrue(profile.validationErrors().isEmpty)
        HeatControlMath.setHeat(3, level: .low, profile: &profile)
        XCTAssertTrue(profile.validationErrors().isEmpty)
        XCTAssertTrue(profile.numericMap.values.allSatisfy { $0 == 3 })
        HeatControlMath.setHeat(0, level: .high, profile: &profile)
        XCTAssertTrue(profile.validationErrors().isEmpty)
        XCTAssertTrue(profile.numericMap.values.allSatisfy { $0 == 1 })
        profile.halfSteps = true
        HeatControlMath.rescale(profile: &profile, minimum: 0.5, maximum: 8.5)
        XCTAssertTrue(profile.validationErrors().isEmpty)
    }
    func testNumericHeatRangesRecoverAfterRoundingAndKeepDistinctLevels() {
        var profile = KitchenProfile()
        HeatControlMath.rescale(profile: &profile, minimum: 1, maximum: 3)
        HeatControlMath.rescale(profile: &profile, minimum: 1, maximum: 9)
        let levels: [HeatLevel] = [.low, .mediumLow, .medium, .mediumHigh, .high]
        XCTAssertEqual(levels.map { profile.numericMap[$0.rawValue]! }, [1, 3, 5, 7, 9])
        HeatControlMath.setHeat(9, level: .medium, profile: &profile)
        let values = levels.map { profile.numericMap[$0.rawValue]! }
        XCTAssertTrue(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })
        XCTAssertEqual(profile.numericMap["medium"], 7)
        XCTAssertTrue(profile.validationErrors().isEmpty)
        HeatControlMath.setHeat(1, level: .high, profile: &profile)
        let changed = levels.map { profile.numericMap[$0.rawValue]! }
        XCTAssertTrue(zip(changed, changed.dropFirst()).allSatisfy { $0 < $1 })
        XCTAssertTrue(profile.validationErrors().isEmpty)
    }

    func testClockwiseOffDialKeepsHeatingPositionsAwayFromOff() {
        var dial = DialConfiguration.clockwiseFromOff(sweep: 180)
        XCTAssertEqual(dial.angle(for: .off), 0)
        XCTAssertEqual(dial.endAngle, 180)
        XCTAssertTrue(dial.clockwise)
        let heats: [HeatLevel] = [.low, .mediumLow, .medium, .mediumHigh, .high]
        let angles = heats.map { dial.angle(for: $0) }
        XCTAssertEqual(angles, angles.sorted())
        XCTAssertTrue(angles.allSatisfy { $0 > 0 && $0 < 180 })
        dial.moveEnd(to: 0)
        XCTAssertEqual(dial.sweep, 30)
        XCTAssertEqual(dial.startAngle, 0)
        XCTAssertTrue(dial.validationErrors.isEmpty)
        XCTAssertEqual(DialConfiguration.clockwiseFromOff(sweep: .nan).sweep, 270)
    }

    func testDialDragClampsSweepAndLegacyProfileDecodes() throws {
        var dial = DialConfiguration(); dial.startAngle = 0; dial.clockwise = true
        dial.moveEnd(to: 0)
        XCTAssertEqual(dial.sweep, 30)
        dial.moveEnd(to: 359)
        XCTAssertEqual(dial.sweep, 330)
        XCTAssertEqual(DialConfiguration.clockLabel(0), "12시 방향")
        XCTAssertEqual(DialConfiguration.clockLabel(90), "3시 방향")
        var old = KitchenProfile(); old.controlType = .knob
        let encoded = try JSONEncoder().encode(old)
        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json.removeValue(forKey: "dialConfiguration")
        let restored = try JSONDecoder().decode(KitchenProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.dialConfiguration)
        XCTAssertEqual(restored.setting(.medium), old.setting(.medium))
    }

}
