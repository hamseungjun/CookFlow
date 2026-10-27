import Foundation

public enum RecipeRevisionEngine {
    /// Edit only actions that the user has not started. Completed records remain byte-for-byte unchanged.
    public static func revise(_ session: inout CookingSession, amounts: [String: Double], remove: Set<String>, waterML: Int?, note: String) throws {
        guard [.cooking, .paused].contains(session.state), session.phase == .ready else { throw RecipeError.invalid("현재 동작을 시작하기 전 또는 완료한 뒤 수정해주세요. 실행 중인 동작은 바꾸지 않습니다.") }
        let original = session.recipe
        guard original.flowVersion == nil else { throw RecipeError.invalid("묶음 조리의 계량은 시작 전에 레시피에서 확인해주세요.") }
        guard original.recipeOrigin == .preset else { throw RecipeError.invalid("영상 레시피의 계량은 실행 전 검토 화면에서 변경해주세요. 조리 중에는 원본 안내를 유지합니다.") }
        let completed = Array(original.steps.prefix(session.stepIndex))
        let locked = Set(completed.filter { $0.actionType == .add }.flatMap { $0.requiredItems.map(\.id) })
        let editable = Set(original.steps.dropFirst(session.stepIndex).filter { $0.actionType == .add }.flatMap { $0.requiredItems.map(\.id) }).subtracting(locked)
        let requested = Set(amounts.keys).union(remove)
        guard requested.isSubset(of: editable) else { throw RecipeError.invalid("이미 투입했거나 선택하지 않은 재료는 변경할 수 없습니다.") }
        guard remove.allSatisfy({ id in original.items.first(where: { $0.id == id })?.ingredient.category == .fresh }) else { throw RecipeError.invalid("양념·기름·육수는 조리 방식의 필수 조건이므로 제거할 수 없습니다.") }
        guard remove.isDisjoint(with: (original.menu ?? .doenjang).essentialIngredients) else { throw RecipeError.invalid("이 메뉴의 필수 재료는 제외할 수 없습니다.") }
        if original.preferences.saute {
            let aromatics = original.items.filter { ["onion", "garlic"].contains($0.id) }
            guard aromatics.contains(where: { !remove.contains($0.id) }) else { throw RecipeError.invalid("볶는 방식의 양파 또는 마늘을 유지해주세요.") }
        }
        var items: [RecipeItem] = []
        for item in original.items where !remove.contains(item.id) {
            let newAmount = amounts[item.id] ?? item.amount
            // Decreasing a future amount does not shorten cooking or exceed pantry/cookware bounds.
            guard newAmount.isFinite, newAmount > 0, newAmount <= item.amount else { throw RecipeError.invalid("\(item.ingredient.name)은 0 초과~\(item.quantityText) 범위에서 줄일 수 있습니다. 늘리려면 새 레시피를 생성해주세요.") }
            let initialAmount = original.revisions.first?.before.first { $0.id == item.id }?.amount ?? item.amount
            if item.ingredient.group == "paste", newAmount < initialAmount * 0.5 { throw RecipeError.invalid("된장·토장은 기존 분량의 절반 이상 유지해주세요.") }
            if item.ingredient.group == "oil", newAmount < item.amount { throw RecipeError.invalid("볶는 방식의 기름 분량은 유지해주세요.") }
            items.append(.init(ingredient: item.ingredient, amount: newAmount))
        }
        let waterAdded = completed.contains { $0.title == "물 계량해 붓기" }
        let water = waterML ?? original.waterML
        guard waterML == nil || (!waterAdded && water >= Int(Double(original.revisions.first?.oldWaterML ?? original.waterML) * 0.8) && water <= original.waterML) else { throw RecipeError.invalid("물은 투입 전 기존 분량의 80~100% 범위에서만 변경할 수 있습니다.") }
        var remaining: [CookingStep] = []
        for var step in original.steps.dropFirst(session.stepIndex) {
            if step.actionType == .add, let item = step.requiredItems.first {
                if remove.contains(item.id) { continue }
                if let replacement = items.first(where: { $0.id == item.id }) {
                    step.instruction = step.instruction.replacingOccurrences(of: item.householdQuantity, with: replacement.householdQuantity).replacingOccurrences(of: item.quantityText, with: replacement.quantityText)
                    step.requiredItems = [replacement]
                }
            }
            if step.title == "물 계량해 붓기" { step.instruction = step.instruction.replacingOccurrences(of: original.waterMeasure, with: HouseholdMeasure.water(water)).replacingOccurrences(of: "\(original.waterML)ml", with: "\(water)ml") }
            remaining.append(step)
        }
        guard !remaining.isEmpty else { throw RecipeError.invalid("수정 후 실행할 단계가 없습니다.") }
        session.recipe.items = items
        session.recipe.waterML = water
        session.recipe.steps = completed + remaining
        session.recipe.revisions.append(.init(before: original.items, after: items, oldWaterML: original.waterML, newWaterML: water, note: note))
        session.events.append(.init(at: Date(), stepID: session.currentStep?.id, type: "REVISE_RECIPE", detail: "아직 시작하지 않은 재료 투입만 수정"))
    }
}
