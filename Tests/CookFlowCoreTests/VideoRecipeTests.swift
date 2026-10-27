import XCTest
@testable import CookFlowCore

final class VideoRecipeTests: XCTestCase {
    func testAICompletedVideoKeepsProvenanceAndMapsKitchenHeat() throws {
        var draft = try self.draft()
        draft.steps[0].heat = .mediumHigh
        draft.ai_completions = [.init(field: "steps.0.heat", label: "가열 화력", value: "중강불", reason: "영상에 없는 화력을 보완했어요.")]
        let encoded = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(VideoRecipeDraft.self, from: encoded)
        XCTAssertTrue(decoded.isAIFilled("steps.0.heat"))
        var kitchen = KitchenProfile(); kitchen.numericMap["mediumHigh"] = 7
        let result = try decoded.recipe(source: "https://youtu.be/qWbHSOplcvY", kitchen: kitchen, preferences: .init())
        XCTAssertTrue(result.warnings.contains { $0.contains("AI 보완") && $0.contains("중강불") })
        XCTAssertEqual(result.sourceVideoURL, "https://www.youtube.com/watch?v=qWbHSOplcvY")
        XCTAssertTrue(result.steps.contains { $0.heatTo == .mediumHigh && $0.deviceSetting == "7단계" })
    }
    func testOnlyYouTubeVideoLinksAreAccepted() throws {
        XCTAssertEqual(try YouTubeLink.canonical("https://youtu.be/qWbHSOplcvY?t=20").absoluteString, "https://www.youtube.com/watch?v=qWbHSOplcvY")
        XCTAssertEqual(try YouTubeLink.canonical("https://www.youtube.com/shorts/qWbHSOplcvY").absoluteString, "https://www.youtube.com/watch?v=qWbHSOplcvY")
        for url in ["https://youtube.com.evil.com/watch?v=qWbHSOplcvY", "https://youtube.com@evil.com/watch?v=qWbHSOplcvY", "http://youtu.be/qWbHSOplcvY", "https://youtube.com/playlist?list=abc", "https://youtube.com/watch?v=../etc"] { XCTAssertThrowsError(try YouTubeLink.canonical(url)) }
    }
    private func draft() throws -> VideoRecipeDraft {
        let json = #"{"title":"영상의 양파 요리","servings":2,"waterML":0,"ingredients":[{"id":"onion","name":"양파","amount":1,"unit":"개","fresh":true,"cut":"슬라이스"}],"steps":[{"action":"heat","title":"불 켜기","instruction":"중불로 조절하세요.","seconds":0,"heat":"medium","ingredientIDs":[]},{"action":"add","title":"양파 넣기","instruction":"양파를 넣으세요.","seconds":0,"heat":null,"ingredientIDs":["onion"]},{"action":"stir","title":"볶기","instruction":"3분 볶으세요.","seconds":180,"heat":null,"ingredientIDs":[]}],"uncertainties":[]}"#
        return try JSONDecoder().decode(VideoRecipeDraft.self, from: Data(json.utf8))
    }
    func testImportedRecipeUsesRegisteredHeatAndRunsThroughExistingSession() throws {
        let result = try draft().recipe(source: "https://youtu.be/qWbHSOplcvY", kitchen: .init(), preferences: .init())
        XCTAssertEqual(result.title, "영상의 양파 요리")
        XCTAssertEqual(result.steps[0].deviceSetting, KitchenProfile().setting(.medium))
        XCTAssertEqual(result.items[0].householdQuantity, "1개")
        XCTAssertEqual(result.steps.last?.heatTo, .off)
        var session = CookingSession(recipe: result)
        for check in session.checks { try SessionEngine.apply(.approvePreparation(check.id), to: &session) }
        try SessionEngine.apply(.beginCooking, to: &session)
        var now = Date()
        while session.state == .cooking {
            if session.currentStep!.durationSeconds > 0 {
                try SessionEngine.apply(.startTimer, to: &session, at: now)
                now = now.addingTimeInterval(Double(session.currentStep!.durationSeconds) + 1)
                try SessionEngine.apply(.timerExpired, to: &session, at: now)
            }
            try SessionEngine.apply(.done, to: &session, at: now)
        }
        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(result)).sourceVideoURL, result.sourceVideoURL)
    }
    func testRealVideoExtractionRequiresServingsAndAddsExplicitHeatStep() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/video-recipe.json")
        var d = try JSONDecoder().decode(VideoRecipeDraft.self, from: Data(contentsOf: file))
        XCTAssertThrowsError(try d.recipe(source: "https://youtu.be/qWbHSOplcvY", kitchen: nil, preferences: .init()))
        d.servings = 2
        let result = try d.recipe(source: "https://youtu.be/qWbHSOplcvY", kitchen: .init(), preferences: .init())
        XCTAssertEqual(result.items.count, 10)
        XCTAssertEqual(result.title, "돼지고기 김치찌개")
        let timed = try XCTUnwrap(result.steps.firstIndex { $0.durationSeconds == 600 })
        XCTAssertEqual(result.steps[timed - 1].actionType, .heat)
        XCTAssertEqual(result.steps[timed - 1].heatTo, .low)
        XCTAssertEqual(result.steps[timed].deviceSetting, KitchenProfile().setting(.low))
        XCTAssertTrue(result.items.contains { $0.ingredient.unit == "큰술" && $0.householdQuantity == "1큰술" })
    }
    func testInvalidExtractionCannotExecute() throws {
        var d = try draft(); d.ingredients[0].amount = 0
        XCTAssertThrowsError(try d.recipe(source: "https://youtu.be/qWbHSOplcvY", kitchen: nil, preferences: .init()))
        d = try draft(); d.steps[0].heat = nil
        XCTAssertThrowsError(try d.recipe(source: "https://youtu.be/qWbHSOplcvY", kitchen: nil, preferences: .init()))
        d = try draft(); d.steps.removeFirst(); d.steps[1].title = "양파 볶기"
        XCTAssertThrowsError(try d.recipe(source: "https://youtu.be/qWbHSOplcvY", kitchen: nil, preferences: .init()))
        d = try draft(); d.steps[1].ingredientIDs = ["missing"]
        XCTAssertThrowsError(try d.recipe(source: "https://youtu.be/qWbHSOplcvY", kitchen: nil, preferences: .init()))
        d = try draft()
        XCTAssertNoThrow(try d.recipe(source: "https://youtu.be/qWbHSOplcvY", kitchen: nil, preferences: .init()))
    }
    func testLegacyRecipesDecodeWithoutVideoFields() throws {
        let recipe = try RecipeEngine.generate(selected: ["doenjang", "tofu"], quantities: [:], preferences: .init())
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as! [String: Any]
        object.removeValue(forKey: "importedTitle"); object.removeValue(forKey: "sourceVideoURL")
        let decoded = try JSONDecoder().decode(Recipe.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.title, "된장찌개"); XCTAssertNil(decoded.sourceVideoURL)
    }
}
