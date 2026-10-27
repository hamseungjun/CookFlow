import XCTest
@testable import CookFlowCore

final class PersonalRecipeBookTests: XCTestCase {
    func testSundubuKeepsChiliOilBeforeWaterAndSoftTofuLast() throws {
        let recipe = try RecipeEngine.generate(selected: RecipeMenu.sundubu.defaultIngredients, quantities: [:], preferences: .init(), menu: .sundubu)
        XCTAssertEqual(recipe.waterML, 500)
        for (id, amount) in ["softTofu": 700.0, "chiliPowder": 18, "soySauce": 30, "fishSauce": 10, "oil": 30, "stockCoin": 2] {
            XCTAssertEqual(recipe.items.first { $0.id == id }?.amount, amount, id)
        }
        let bloom = try XCTUnwrap(recipe.steps.firstIndex { $0.title == "고추기름 내기" })
        let water = try XCTUnwrap(recipe.steps.firstIndex { $0.title == "물 계량해 붓기" })
        let tofu = try XCTUnwrap(recipe.steps.firstIndex { $0.requiredItems.contains { $0.id == "softTofu" } })
        XCTAssertLessThan(bloom, water)
        XCTAssertLessThan(water, tofu)
        XCTAssertEqual(recipe.steps[bloom].heatTo, .low)
        XCTAssertEqual(recipe.steps[bloom].durationSeconds, 25)
        let flow = CookingFlow.prepare(recipe)
        let speech = flow.steps.map(\.speechText).joined(separator: " ")
        XCTAssertFalse(speech.contains("계량은"))
        XCTAssertFalse(speech.contains("조리 도구"))
        XCTAssertFalse(speech.contains("안정적으로"))
        XCTAssertTrue(speech.contains("많이 젓지"))
        XCTAssertTrue(speech.contains("큰술"))
        try JSONEncoder().encode(recipe).write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/sundubu-baseline.json"))
    }
    func testBookServingAmountsAndUserFixedBatchArePreserved() throws {
        var one = Preferences(); one.servings = 1
        let doenjang = try RecipeEngine.generate(selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: one)
        XCTAssertEqual(doenjang.waterML, 300)
        XCTAssertEqual(doenjang.items.first { $0.id == "stockCoin" }?.amount, 1)
        XCTAssertEqual(doenjang.items.first { $0.id == "doenjang" }?.amount, 27)
        let sundubu = try RecipeEngine.generate(selected: RecipeMenu.sundubu.defaultIngredients, quantities: [:], preferences: one, menu: .sundubu)
        XCTAssertEqual(sundubu.waterML, 250)
        XCTAssertEqual(sundubu.items.first { $0.id == "softTofu" }?.amount, 350)
        XCTAssertThrowsError(try RecipeEngine.generate(selected: RecipeMenu.jeyuk.defaultIngredients, quantities: ["pork": 100], preferences: .init(), menu: .jeyuk))
        for servings in [1, 2, 4] {
            var prefs = Preferences(); prefs.servings = servings; prefs.spice = 3; prefs.salt = 0
            let jeyuk = try RecipeEngine.generate(selected: RecipeMenu.jeyuk.defaultIngredients, quantities: [:], preferences: prefs, menu: .jeyuk)
            XCTAssertEqual(jeyuk.items.first { $0.id == "pork" }?.amount, 300)
            for (id, amount) in ["gochujang": 18.0, "chiliPowder": 6, "oysterSauce": 15, "sugar": 12, "garlic": 15] {
                XCTAssertEqual(jeyuk.items.first { $0.id == id }?.amount, amount)
            }
        }
    }
    func testOldAIGuidesDropEquipmentSentencesButKeepCookingActions() throws {
        var recipe = try RecipeEngine.generate(selected: RecipeMenu.sundubu.defaultIngredients, quantities: [:], preferences: .init(), menu: .sundubu)
        var step = recipe.steps[0]
        step.flowInstructions = nil
        step.instruction = "손질된 채소, 순두부, 양념, 물을 준비하고 조리 도구를 확인합니다. 화구 중앙에 냄비를 흔들리지 않게 올려놓습니다. 냄비에 물 350ml와 코인육수 1개를 넣습니다. 육수가 끓어오를 때까지 3분간 가열합니다."
        recipe.steps = [step]
        let text = CookingNarration.text(for: step, recipe: recipe)
        XCTAssertFalse(text.contains("흔들리지"))
        XCTAssertFalse(text.contains("조리 도구"))
        XCTAssertTrue(text.contains("350ml"))
        XCTAssertTrue(text.contains("3분"))
    }
    func testAllPersonalRecipesRetainSourceStatusAndExecutableIngredientCoverage() throws {
        let menus = RecipeMenu.allCases.filter { $0.baselineStatus != nil }
        XCTAssertEqual(menus.count, 26)
        for menu in menus {
            let recipe = try RecipeEngine.generate(selected: menu.defaultIngredients, quantities: [:], preferences: .init(), menu: menu)
            XCTAssertEqual(recipe.templateVersion, "3.0-personal-recipe-book")
            XCTAssertFalse(recipe.warnings.contains { $0.contains("승준 레시피북") || $0.contains("등록 레시피") })
            XCTAssertEqual(Set(recipe.items.map(\.id)), menu.defaultIngredients)
            XCTAssertEqual(Set(recipe.steps.filter { $0.actionType == .add }.flatMap { $0.requiredItems.map(\.id) }), menu.defaultIngredients)
        }
    }
    func testActualAIAddedMushroomPreservesFlavorPhasesAndCompletes() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/personal-sundubu-ai.json")
        let draft = try JSONDecoder().decode(VideoRecipeDraft.self, from: Data(contentsOf: url))
        let recipe = try draft.generatedRecipe(kitchen: nil, preferences: .init())
        let flow = CookingFlow.prepare(recipe)
        let bloom = try XCTUnwrap(flow.steps.firstIndex { $0.title == "고추기름 내기" })
        let broth = try XCTUnwrap(flow.steps.firstIndex { $0.title == "국물 끓이기" })
        XCTAssertLessThan(bloom, broth)
        XCTAssertEqual(flow.steps[bloom].heatTo, .low)
        XCTAssertEqual(flow.steps[bloom].durationSeconds, 25)
        XCTAssertTrue(flow.steps[bloom].speechText.contains("3큰술"))
        XCTAssertFalse(flow.steps.map(\.speechText).joined().contains("계량은"))
        var session = CookingSession(recipe: flow)
        try SessionEngine.apply(.approveAllPreparation, to: &session)
        try SessionEngine.apply(.beginCooking, to: &session)
        while let step = session.currentStep {
            if step.durationSeconds > 0 {
                try SessionEngine.apply(.startTimer, to: &session)
                try SessionEngine.apply(.advanceAfterTimer, to: &session, at: session.targetEndAt!)
            } else { try SessionEngine.apply(.done, to: &session) }
        }
        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(RecipeMenu.matching("칼칼한 순두부찌개"), .sundubu)
        XCTAssertEqual(RecipeMenu.matching("우삼겹 순두부찌개"), .beefSundubu)
    }

    func testBulletActionsPreserveCookingDetailsAndNeverSpeakListMarkers() throws {
        var recipe = try RecipeEngine.generate(selected: RecipeMenu.sundubu.defaultIngredients, quantities: [:], preferences: .init(), menu: .sundubu)
        var step = try XCTUnwrap(recipe.steps.first { $0.title == "순두부 끓이기" })
        step.flowInstructions = nil
        step.instruction = "- 순두부를 넣어주세요.\n- 3분 더 끓여주세요.\n- 많이 젓지 마세요."
        recipe.steps = [step]
        let actions = CookingNarration.actions(for: step, recipe: recipe)
        XCTAssertEqual(actions.count, 3)
        XCTAssertTrue(actions[0].contains("순두부를 넣어주세요"))
        XCTAssertTrue(actions[1].contains("3분"))
        XCTAssertTrue(actions[2].contains("많이 젓지"))
        XCTAssertFalse(actions.joined().contains("타이머 시작"))
        XCTAssertFalse(CookingNarration.text(for: step, recipe: recipe).contains("- "))
        step.instruction = "1. 순두부를 넣어주세요.\n2. 3분 더 끓여주세요."
        XCTAssertEqual(CookingNarration.actions(for: step, recipe: recipe).count, 2)
        XCTAssertFalse(CookingNarration.actions(for: step, recipe: recipe)[0].hasPrefix("1."))
    }

}
