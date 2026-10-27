import Foundation

// Run the base acceptance suite on Macs with only Command Line Tools. The full suite, including home meals and video import, runs with swift test.
class XCTestCase {}
var assertionFailures = 0
func fail(_ message: String, file: StaticString, line: UInt) { assertionFailures += 1; print("FAIL \(file):\(line) \(message)") }
func XCTAssertTrue(_ condition: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) { do { if try !condition() { fail("Expected true", file: file, line: line) } } catch { fail("Unexpected error: \(error)", file: file, line: line) } }
func XCTAssertFalse(_ condition: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) { do { if try condition() { fail("Expected false", file: file, line: line) } } catch { fail("Unexpected error: \(error)", file: file, line: line) } }
func XCTAssertEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { let a = try left(); let b = try right(); if a != b { fail("\(a) != \(b)", file: file, line: line) } } catch { fail("Unexpected error: \(error)", file: file, line: line) } }
func XCTAssertLessThan<T: Comparable>(_ left: @autoclosure () -> T, _ right: @autoclosure () -> T, file: StaticString = #filePath, line: UInt = #line) { if left() >= right() { fail("Expected less than", file: file, line: line) } }
func XCTAssertThrowsError<T>(_ body: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try body(); fail("Expected error", file: file, line: line) } catch {} }
func XCTAssertNoThrow<T>(_ body: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try body() } catch { fail("Unexpected error: \(error)", file: file, line: line) } }
func XCTAssertNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) { if value() != nil { fail("Expected nil", file: file, line: line) } }
func XCTAssertNotNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) { if value() == nil { fail("Expected non-nil", file: file, line: line) } }

enum StandaloneAssertionError: Error { case missingValue }
func XCTUnwrap<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let result = try value() else { throw StandaloneAssertionError.missingValue }
    return result
}
func XCTAssertGreaterThan<T: Comparable>(_ left: @autoclosure () -> T, _ right: @autoclosure () -> T, file: StaticString = #filePath, line: UInt = #line) { if left() <= right() { fail("Expected greater than", file: file, line: line) } }

@main struct TestRunner {
    static func main() {
        let suite = CookFlowCoreTests()
        let tests: [(String, () throws -> Void)] = [
            ("선택 재료만 사용", suite.testOnlySelectedIngredientsUsed),
            ("필수 된장 검사", suite.testPasteRequiredAndStockOptional),
            ("인분과 시간 계산", suite.testServingsScaleAmountsButNotTimeLinearly),
            ("가스 다이얼 안내", suite.testDialGasUsesUserPositions),
            ("화력 범위 검사", suite.testInvalidHeatMappingRejected),
            ("화력 범위 복원과 단계 구분", suite.testNumericHeatRangesRecoverAfterRoundingAndKeepDistinctLevels),
            ("주방 등록 없이 일반 화력 조리", suite.testCookingWithoutKitchenUsesGeneralHeatAndSurvivesReplay),
            ("세 메뉴 조리 완료와 저장", suite.testThreeMenusHaveDistinctStepsAndComplete),
            ("메뉴별 필수 재료", suite.testNewMenusRequireTheirMainIngredientAndCannotRemoveIt),
            ("생활 계량과 장보기 링크", suite.testHouseholdMeasuresAndShoppingLinks),
            ("OFF부터 시계방향 다이얼", suite.testClockwiseOffDialKeepsHeatingPositionsAwayFromOff),
            ("물 컵 계량 수정", suite.testWaterRevisionUpdatesCupAndRawMeasurements),
            ("양념 재고 검사", suite.testInsufficientPasteRejected),
            ("냄비 등록 없이 기존 프로필 사용", suite.testLegacyCookwareDoesNotBlockRegistrationOrRecipes),
            ("보유량에 맞춘 분량", suite.testAvailableFreshAmountRespected),
            ("제외 재료 검사", suite.testDietConflictsRejected),
            ("볶기 조건과 원자적 동작", suite.testSautePrerequisitesAndAtomicActions),
            ("손질 확인 전 조리 차단", suite.testPreparationCannotBeSkipped),
            ("타이머 종료 후 확인 대기", suite.testTimerExpiryDoesNotAdvanceAndPrematureDoneRejected),
            ("일시정지·복원·연장", suite.testPauseResumeAndExtendPreserveAbsoluteTime),
            ("중복 완료 방지", suite.testDuplicateEventDoesNotSkipStep),
            ("저장 후 타이머 복원", suite.testPersistenceRestoresTimerAndSnapshot),
            ("조리 전체 여정", suite.testCompleteJourneyWithExplicitConfirmations),
            ("취소 후 실행 차단", suite.testCancelStopsTimer),
            ("음성과 화면 동일 수치", suite.testSpeechAndScreenShareExactSource),
            ("만료 후 타이머 연장", suite.testExpiredTimerCanBeExtendedWithoutAdvancing),
            ("미완료 재료만 수정하고 이전 동작 보존", suite.testRevisionsPreserveCompletedActionsAndRemoveOnlyFutureItems),
            ("투입된 재료와 실행 중 단계 수정 차단", suite.testCannotReviseAlreadyAddedItemsOrActiveTimer),
            ("동시 보조 타이머 저장·일시정지·복원", suite.testAuxiliaryTimersRestoreAndPauseTogether),
            ("다이얼 회전 방향과 강약 반전", suite.testVisualDialSupportsBothDirectionsAndReverseStrength),
            ("슬라이더 범위 변경과 화력 순서", suite.testNumericRangeRescaleAndHeatDragPreserveValidOrder),
            ("다이얼 범위와 기존 프로필 호환", suite.testDialDragClampsSweepAndLegacyProfileDecodes)
        ]
        for (name, test) in tests {
            let before = assertionFailures
            do { try test() } catch { assertionFailures += 1; print("FAIL \(name): \(error)") }
            if assertionFailures == before { print("PASS \(name)") }
        }
        print("\(tests.count) scenarios, \(assertionFailures) failures")
        if assertionFailures > 0 { exit(1) }
    }
}
