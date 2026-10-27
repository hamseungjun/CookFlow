import XCTest
@testable import CookFlowCore

final class HomeMealTests: XCTestCase {
    func testThirtyMenusHaveCategoriesReferencesAndAllIngredientsUsed() throws {
        XCTAssertEqual(RecipeMenu.allCases.count, 48)
        XCTAssertEqual(RecipeMenu.allCases.first, .doenjang)
        XCTAssertEqual(Set(RecipeMenu.allCases.map(\.category)), ["국·찌개", "메인요리", "반찬", "밥·한그릇", "파스타"])
        for menu in RecipeMenu.allCases {
            let result = try RecipeEngine.generate(selected: menu.defaultIngredients, quantities: [:], preferences: .init(), menu: menu)
            XCTAssertEqual(result.title, menu.title)
            XCTAssertTrue(result.importedTitle == nil)
            XCTAssertEqual(Set(result.steps.filter { $0.actionType == .add }.flatMap { $0.requiredItems.map(\.id) }), Set(result.items.map(\.id)), menu.title)
            XCTAssertEqual(result.steps.last?.heatTo, .off)
            XCTAssertEqual(menu.referenceURL.host, "www.10000recipe.com")
            XCTAssertEqual(URLComponents(url: menu.referenceURL, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, menu.title)
        }
    }
    func testEveryMenuRunsPreparationTimersAndCompletionAtDifferentServings() throws {
        for menu in RecipeMenu.allCases {
            for servings in [1, 2, 4] {
                var prefs = Preferences(); prefs.servings = servings
                let result = try RecipeEngine.generate(selected: menu.defaultIngredients, quantities: [:], preferences: prefs, menu: menu)
                var session = CookingSession(recipe: result)
                for check in session.checks { try SessionEngine.apply(.approvePreparation(check.id), to: &session) }
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
                XCTAssertEqual(session.state, .completed, "\(menu.title) \(servings)인분")
                let decoded = try JSONDecoder().decode(CookingSession.self, from: JSONEncoder().encode(session))
                XCTAssertEqual(decoded.recipe.menu, menu)
                XCTAssertTrue(result.items.allSatisfy { $0.amount > 0 && $0.amount.isFinite })
            }
        }
    }
    func testDishSpecificCutsAndMethods() throws {
        let potato = try RecipeEngine.generate(selected: RecipeMenu.stirPotato.defaultIngredients, quantities: [:], preferences: .init(), menu: .stirPotato)
        XCTAssertTrue(potato.items.first { $0.id == "potato" }!.ingredient.cut.contains("채썰기"))
        XCTAssertEqual(potato.waterML, 0)
        let soup = try RecipeEngine.generate(selected: RecipeMenu.beefRadish.defaultIngredients, quantities: [:], preferences: .init(), menu: .beefRadish)
        XCTAssertGreaterThan(soup.waterML, 0)
        XCTAssertTrue(soup.steps.contains { $0.title == "물 계량해 붓기" })
        let salad = try RecipeEngine.generate(selected: RecipeMenu.cucumberMuchim.defaultIngredients, quantities: [:], preferences: .init(), menu: .cucumberMuchim)
        XCTAssertFalse(salad.steps.contains { $0.heatTo != .off })
        let omelet = try RecipeEngine.generate(selected: RecipeMenu.eggRoll.defaultIngredients, quantities: [:], preferences: .init(), menu: .eggRoll)
        XCTAssertTrue(omelet.steps.contains { $0.title == "달걀 말기" })
    }
    func testEssentialIngredientsAndDietaryExclusionsAreEnforced() throws {
        for menu in RecipeMenu.allCases where !menu.isOriginalStew {
            for required in menu.essentialIngredients {
                XCTAssertThrowsError(try RecipeEngine.generate(selected: menu.defaultIngredients.subtracting([required]), quantities: [:], preferences: .init(), menu: menu), "\(menu.title): \(required)")
            }
        }
        prefs = Preferences(); prefs.excludeMeat = true
        XCTAssertThrowsError(try RecipeEngine.generate(selected: RecipeMenu.jeyuk.defaultIngredients, quantities: [:], preferences: prefs, menu: .jeyuk))
        prefs = Preferences(); prefs.excludeSeafood = true
        XCTAssertThrowsError(try RecipeEngine.generate(selected: RecipeMenu.anchovyStir.defaultIngredients, quantities: [:], preferences: prefs, menu: .anchovyStir))
    }
    func testNewIngredientsDoNotLeakIntoOriginalStews() {
        XCTAssertFalse(RecipeMenu.doenjang.allows(Catalog.item("egg")!))
        XCTAssertFalse(RecipeMenu.kimchi.allows(Catalog.item("riceCooked")!))
    }
}
