import XCTest
@testable import CookFlowCore

final class CountdownCueTests: XCTestCase {
    func testTenAndFinalFiveOnlyOnce() {
        var cue = CountdownCue()
        for second in stride(from: 12, through: 0, by: -1) {
            XCTAssertEqual(cue.update(id: "timer", remaining: second), second == 10 || second <= 5)
            XCTAssertFalse(cue.update(id: "timer", remaining: second))
        }
    }
    func testRestoredTimerDoesNotReplayOldCueAndNewDeadlineResets() {
        var cue = CountdownCue()
        XCTAssertFalse(cue.update(id: "old", remaining: 0))
        XCTAssertFalse(cue.update(id: "new", remaining: 6))
        XCTAssertTrue(cue.update(id: "new", remaining: 5))
        cue.retain(ids: [])
        XCTAssertFalse(cue.update(id: "new", remaining: 5))
    }
}
