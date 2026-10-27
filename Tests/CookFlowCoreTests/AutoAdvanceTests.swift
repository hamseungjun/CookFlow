import XCTest
@testable import CookFlowCore

final class AutoAdvanceTests: XCTestCase {
    private func active() throws -> CookingSession {
        var s = CookingSession(recipe: CookingFlow.prepare(try RecipeEngine.generate(kitchen: nil, selected: RecipeMenu.doenjang.defaultIngredients, quantities: [:], preferences: Preferences(), menu: .doenjang)))
        try SessionEngine.apply(.approveAllPreparation, to: &s)
        try SessionEngine.apply(.beginCooking, to: &s)
        try SessionEngine.apply(.startTimer, to: &s)
        return s
    }
    func testExpiryAdvancesOnceButDoesNotStartNextTimer() throws {
        var s = try active(); let end = s.targetEndAt!
        XCTAssertFalse(try SessionEngine.apply(.advanceAfterTimer, to: &s, at: end.addingTimeInterval(-1)))
        XCTAssertTrue(try SessionEngine.apply(.advanceAfterTimer, to: &s, key: "expiry", at: end))
        XCTAssertEqual(s.stepIndex, 1); XCTAssertEqual(s.phase, .ready); XCTAssertNil(s.targetEndAt)
        XCTAssertFalse(try SessionEngine.apply(.advanceAfterTimer, to: &s, key: "expiry", at: end))
    }
    func testReturnAllowsExtraTimeAndDoesNotRestartWholeStage() throws {
        var s = try active(); let end = s.targetEndAt!
        try SessionEngine.apply(.advanceAfterTimer, to: &s, at: end)
        try SessionEngine.apply(.previous, to: &s, at: end)
        XCTAssertEqual(s.stepIndex, 0); XCTAssertEqual(s.remaining(at: end), 0)
        try SessionEngine.apply(.addTime(30), to: &s, at: end)
        XCTAssertEqual(s.remaining(at: end), 30)
        try SessionEngine.apply(.advanceAfterTimer, to: &s, at: end.addingTimeInterval(30))
        XCTAssertEqual(s.stepIndex, 1)
    }
    func testPausedTimerNeverAdvances() throws {
        var s = try active(); let end = s.targetEndAt!
        try SessionEngine.apply(.pause, to: &s, at: end.addingTimeInterval(-5))
        XCTAssertFalse(try SessionEngine.apply(.advanceAfterTimer, to: &s, at: end))
        XCTAssertEqual(s.stepIndex, 0)
    }
}
