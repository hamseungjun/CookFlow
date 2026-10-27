import XCTest
@testable import CookFlowCore

final class AIRecipeTests: XCTestCase {
    func testRealGeneratedDoenjangCanUseCookingSession() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ai-recipe.json")
        let draft = try JSONDecoder().decode(VideoRecipeDraft.self, from: Data(contentsOf: path))
        let recipe = try draft.generatedRecipe(kitchen: nil, preferences: Preferences())
        XCTAssertEqual(recipe.recipeOrigin, .ai)
        XCTAssertTrue(recipe.steps.contains { $0.durationSeconds > 0 })
        XCTAssertTrue(recipe.steps.contains { $0.actionType == .heat })
        let session = CookingSession(recipe: recipe)
        XCTAssertEqual(session.state, .preparing)
        XCTAssertFalse(recipe.items.isEmpty)
    }
    func testGeneratedRecipeHasDistinctOriginAndKeepsPreferences() throws {
        let json = #"{"title":"두부 한 끼","servings":2,"waterML":0,"ingredients":[{"id":"tofu","name":"두부","amount":200,"unit":"g","fresh":true,"cut":"깍둑썰기"}],"steps":[{"action":"add","title":"두부 담기","instruction":"두부를 접시에 담으세요","seconds":0,"heat":"off","ingredientIDs":["tofu"]}],"uncertainties":[]}"#
        let draft = try JSONDecoder().decode(VideoRecipeDraft.self, from: Data(json.utf8))
        var prefs = Preferences(); prefs.spice = 0
        let recipe = try draft.generatedRecipe(kitchen: nil, preferences: prefs)
        XCTAssertEqual(recipe.recipeOrigin, .ai)
        XCTAssertNil(recipe.sourceVideoURL)
        XCTAssertEqual(recipe.preferences.spice, 0)
        XCTAssertEqual(recipe.steps.last?.heatTo, .off)
        let restored = try JSONDecoder().decode(SavedRecipe.self, from: JSONEncoder().encode(SavedRecipe(recipe: recipe)))
        XCTAssertEqual(restored.recipe, recipe)
        prefs.servings = 3
        XCTAssertThrowsError(try draft.generatedRecipe(kitchen: nil, preferences: prefs))
        prefs.servings = 2
        XCTAssertNoThrow(try draft.generatedRecipe(kitchen: nil, preferences: prefs))
    }
}
