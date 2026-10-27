import Foundation

public enum YouTubeLink {
    public static func canonical(_ text: String) throws -> URL {
        guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), c.scheme == "https", c.user == nil, c.password == nil, c.port == nil, let host = c.host?.lowercased() else { throw RecipeError.invalid("유튜브 영상 링크를 입력해주세요.") }
        let parts = c.path.split(separator: "/").map(String.init)
        let id: String?
        if host == "youtu.be", parts.count == 1 { id = parts.first }
        else if ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(host) {
            if c.path == "/watch" { id = c.queryItems?.first(where: { $0.name == "v" })?.value }
            else if parts.count == 2, ["shorts", "embed", "live"].contains(parts[0]) { id = parts[1] }
            else { id = nil }
        } else { id = nil }
        guard let id, id.count == 11, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { throw RecipeError.invalid("개별 유튜브 영상의 공유 링크를 입력해주세요.") }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }
}
public struct VideoRecipeDraft: Codable {
    public struct Completion: Codable, Equatable { public var field: String; public var label: String; public var value: String; public var reason: String }
    public var ai_completions: [Completion]? = nil
    public var source_uncertainties: [String]? = nil
    public var completionNotes: [String] { (ai_completions ?? []).map { "AI 보완 · \($0.label): \($0.value)" } }
    public func isAIFilled(_ field: String) -> Bool { ai_completions?.contains { $0.field == field } ?? false }

    public struct Item: Codable { public var id: String; public var name: String; public var amount: Double; public var unit: String; public var fresh: Bool; public var cut: String }
    public struct Step: Codable { public var action: ActionType; public var title: String; public var instruction: String; public var seconds: Int; public var heat: HeatLevel?; public var ingredientIDs: [String] }
    public var title: String
    public var servings: Int
    public var waterML: Int
    public var ingredients: [Item]
    public var steps: [Step]
    public var uncertainties: [String]
    public func recipe(source: String, kitchen: KitchenProfile?, preferences: Preferences) throws -> Recipe {
        let url = try YouTubeLink.canonical(source)
        return try build(sourceURL: url.absoluteString, kitchen: kitchen, preferences: preferences)
    }
    public func generatedRecipe(kitchen: KitchenProfile?, preferences: Preferences) throws -> Recipe {
        guard servings == preferences.servings else { throw RecipeError.invalid("요청한 인분과 AI 결과가 다릅니다. 다시 만들어주세요.") }
        var checked = self
        for index in checked.ingredients.indices {
            if let known = Catalog.items.first(where: { $0.name == checked.ingredients[index].name }) {
                if preferences.excludeMeat && known.group == "meat" || preferences.excludeSeafood && known.group == "seafood" {
                    throw RecipeError.invalid("제외한 재료가 AI 결과에 포함됐습니다. 재료 목록에서 빼고 다시 만들어주세요.")
                }
            }
        }
        var result = try checked.build(sourceURL: nil, kitchen: kitchen, preferences: preferences)
        result.origin = .ai; result.preferences = preferences
        result.warnings = uncertainties + ["AI가 선택한 재료와 취향으로 만든 레시피입니다. 계량과 익힘을 확인해주세요."]
        return result
    }
    private func build(sourceURL: String?, kitchen: KitchenProfile?, preferences: Preferences) throws -> Recipe {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, (1...12).contains(servings), (0...10000).contains(waterML), !ingredients.isEmpty, ingredients.count <= 80, !steps.isEmpty, steps.count <= 100 else { throw RecipeError.invalid("인분·재료·조리 순서를 확인할 수 없습니다. 요청할 재료를 바꾸거나 내용을 다시 확인해주세요.") }
        let ids = ingredients.map(\.id)
        guard Set(ids).count == ids.count, ingredients.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && !$0.unit.isEmpty && $0.amount.isFinite && $0.amount > 0 && $0.amount <= 100000 }) else { throw RecipeError.invalid("재료 계량이 빠져 있습니다. 모든 재료에 분량이 필요합니다.") }
        guard steps.allSatisfy({ !$0.title.isEmpty && !$0.instruction.isEmpty && (0...21600).contains($0.seconds) && Set($0.ingredientIDs).isSubset(of: Set(ids)) && ($0.action != .heat || $0.heat != nil) }) else { throw RecipeError.invalid("화력·시간·재료 연결을 확인할 수 없는 단계가 있습니다.") }
        let items = ingredients.map { item in RecipeItem(ingredient: Ingredient(item.id, item.name, item.fresh ? .fresh : .seasoning, item.unit, item.amount, item.cut, "video"), amount: item.amount) }
        let profile = kitchen ?? .generalGuidance()
        var heat: HeatLevel = .off
        var actions: [CookingStep] = []
        for step in steps {
            let next = step.heat ?? heat
            let needsHeat = step.action == .simmer || ["볶", "끓", "굽", "튀", "가열"].contains { step.title.contains($0) }
            guard !needsHeat || next != .off else { throw RecipeError.invalid("‘\(step.title)’의 화력이 정해지지 않았습니다. 검토 화면에서 사용할 화력을 선택해주세요.") }
            let mapped = profile.setting(next)
            if next != heat && step.action != .heat {
                actions.append(CookingStep(actionType: .heat, title: "화력 조절 · \(next.label)", instruction: "다음 단계에 맞춰 \(mapped)로 조절해주세요. 가열 상태를 직접 확인해주세요.", heatFrom: heat, heatTo: next, deviceSetting: mapped, heatGoal: next.label, durationSeconds: 0, requiredItems: [], completionCondition: "화력 변경 확인", safetyNotice: "가열기는 직접 조절합니다."))
                heat = next
            }
            let required = items.filter { step.ingredientIDs.contains($0.id) }
            let quantities = required.map { "\($0.ingredient.name) \($0.householdQuantity)" }.joined(separator: " · ")
            let instruction = step.instruction + (step.action == .heat ? "\n우리 주방 설정: \(mapped)" : "") + (!quantities.isEmpty ? "\n이번 조리 계량: \(quantities)" : "")
            actions.append(CookingStep(actionType: step.action, title: step.title, instruction: instruction, heatFrom: heat, heatTo: next, deviceSetting: mapped, heatGoal: next.label, durationSeconds: step.seconds, requiredItems: required, completionCondition: "상태를 확인하고 완료를 눌러주세요.", safetyNotice: "안내 시간은 참고값입니다. 실제 익힘과 가열 상태를 확인해주세요."))
            heat = next
        }
        actions.append(CookingStep(actionType: .finish, title: "가열기 끄고 마무리", instruction: "가열기를 OFF로 바꾸고 음식의 익힘을 직접 확인해주세요.", heatFrom: heat, heatTo: .off, deviceSetting: "OFF", heatGoal: "조리 마무리", durationSeconds: 0, requiredItems: [], completionCondition: "가열기 OFF 확인", safetyNotice: "뜨거운 용기와 화구를 조심해주세요."))
        var prefs = Preferences(); prefs.servings = servings
        let measuredWater = ingredients.first { $0.name == "물" && $0.unit == "ml" }.map { Int($0.amount) } ?? waterML
        var result = Recipe(kitchen: profile, preferences: prefs, items: items, waterML: measuredWater, steps: actions, warnings: uncertainties + completionNotes + ["AI가 영상에서 추출한 레시피입니다. 재료·계량·순서를 원본과 비교해주세요.", "기본 계량은 1인분입니다. 조리 단계의 ‘이번 조리 계량’을 확인해주세요."])
        result.importedTitle = title; result.sourceVideoURL = sourceURL
        return result
    }
}
