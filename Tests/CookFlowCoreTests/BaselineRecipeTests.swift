import XCTest
@testable import CookFlowCore

final class BaselineRecipeTests: XCTestCase {
    func testAllUnchangedMenusUseBaselineWithoutAI() throws {
        for menu in RecipeMenu.allCases {
            let selection = RecipeCustomization(menu: menu, selected: menu.defaultIngredients)
            XCTAssertFalse(selection.requiresAI, menu.title)
            XCTAssertTrue(selection.added.isEmpty)
            XCTAssertTrue(selection.removed.isEmpty)
            let recipe = try RecipeEngine.generate(selected: menu.defaultIngredients, quantities: [:], preferences: .init(), menu: menu)
            XCTAssertEqual(recipe.recipeOrigin, .preset)
        }
    }
    func testAddingRemovingAndRestoringIngredientsRoutesCorrectly() {
        for menu in RecipeMenu.allCases {
            let extra = Catalog.items.first { !menu.defaultIngredients.contains($0.id) }!.id
            let added = RecipeCustomization(menu: menu, selected: menu.defaultIngredients.union([extra]))
            XCTAssertTrue(added.requiresAI)
            XCTAssertEqual(added.added, [extra])
            let removedID = menu.defaultIngredients.sorted().first!
            let removed = RecipeCustomization(menu: menu, selected: menu.defaultIngredients.subtracting([removedID]))
            XCTAssertTrue(removed.requiresAI)
            XCTAssertEqual(removed.removed, [removedID])
            let restored = RecipeCustomization(menu: menu, selected: removed.selected.union([removedID]))
            XCTAssertFalse(restored.requiresAI)
        }
    }
    func testActualAIAdditionAndRemovalRunsThroughCookingFlow() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/baseline-customized-ai.json")
        let draft = try JSONDecoder().decode(VideoRecipeDraft.self, from: Data(contentsOf: url))
        let generated = try draft.generatedRecipe(kitchen: nil, preferences: .init())
        XCTAssertEqual(Set(generated.items.map { $0.ingredient.name }).subtracting(["물"]), ["두부", "애호박", "대파", "된장", "버섯"])
        XCTAssertFalse(generated.steps.contains { $0.instruction.contains("양파") })
        var session = CookingSession(recipe: CookingFlow.prepare(generated))
        try SessionEngine.apply(.approveAllPreparation, to: &session)
        try SessionEngine.apply(.beginCooking, to: &session)
        while let step = session.currentStep {
            if step.durationSeconds > 0 {
                try SessionEngine.apply(.startTimer, to: &session)
                try SessionEngine.apply(.advanceAfterTimer, to: &session, at: session.targetEndAt!)
            } else { try SessionEngine.apply(.done, to: &session) }
        }
        XCTAssertEqual(session.state, .completed)
    }

}
