import Foundation

public enum RecipeError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
public enum RecipeEngine {
    public static func generate(kitchen: KitchenProfile? = nil, selected: Set<String>, quantities: [String: Double], preferences: Preferences, menu: RecipeMenu = .doenjang) throws -> Recipe {
        if !menu.isOriginalStew || (HomeMealCatalog.templates[menu.rawValue]?.sourceStatus != nil && selected == menu.defaultIngredients) { return try HomeMealCatalog.generate(menu: menu, kitchen: kitchen, selected: selected, quantities: quantities, preferences: preferences) }
        let kitchen = kitchen ?? .generalGuidance()
        let errors = kitchen.validationErrors()
        guard errors.isEmpty else { throw RecipeError.invalid(errors.joined(separator: "\n")) }
        guard (1...4).contains(preferences.servings) else { throw RecipeError.invalid("인분은 1~4인분으로 선택해주세요.") }
        guard menu != .doenjang || selected.contains("doenjang") || selected.contains("tojang") else { throw RecipeError.invalid("된장 또는 토장이 필요합니다. 조미료 탭에서 선택해주세요.") }
        guard menu.essentialIngredients.isSubset(of: selected) else { throw RecipeError.invalid(menu == .kimchi ? "김치찌개에는 김치를 선택해주세요." : "순두부찌개에는 순두부를 선택해주세요.") }
        guard selected.allSatisfy({ Catalog.item($0) != nil }) else { throw RecipeError.invalid("지원하지 않는 재료가 있습니다.") }
        let scale = Double(preferences.servings) / 2
        let selectedItems = Catalog.items.filter { selected.contains($0.id) }
        guard selectedItems.allSatisfy({ menu.allows($0) }) else { throw RecipeError.invalid("선택한 메뉴에 맞는 재료를 선택해주세요.") }
        if preferences.excludeMeat && selectedItems.contains(where: { $0.group == "meat" }) { throw RecipeError.invalid("육류 제외 설정과 선택 재료가 충돌합니다.") }
        if preferences.excludeSeafood && selectedItems.contains(where: { $0.group == "seafood" }) { throw RecipeError.invalid("해산물 제외 설정과 선택 재료가 충돌합니다.") }
        if preferences.saute && (!selected.contains("oil") || !selectedItems.contains(where: { ["onion", "garlic"].contains($0.id) })) { throw RecipeError.invalid("볶는 방식에는 식용유와 양파 또는 마늘이 필요합니다.") }
        let pasteCount = Double(selectedItems.filter { $0.group == "paste" }.count)
        var warnings: [String] = ["화력과 시간은 초기 추정값입니다. 실제 끓음과 재료 상태를 직접 확인해주세요."]
        var items: [RecipeItem] = []
        for ingredient in selectedItems {
            if ingredient.group == "oil" && !preferences.saute { continue }
            var amount = (menu == .sundubu && ingredient.id == "softTofu" ? 350 : ingredient.baseAmount) * scale
            if ingredient.group == "paste" { amount *= [0.8, 1.0, 1.1, 1.2][max(0, min(3, preferences.salt))] / pasteCount }
            if ["chili", "redChili", "chiliPowder", "gochujang"].contains(ingredient.id) { amount *= [0.25, 1.0, 1.3, 1.6][max(0, min(3, preferences.spice))] }
            if ingredient.group == "stockLiquid" { amount = (menu == .kimchi ? 500.0 : menu == .sundubu ? 300.0 : 350.0) * scale }
            amount = ingredient.unit == "개" ? max(1, amount.rounded(.up)) : (amount * 10).rounded() / 10
            if let available = quantities[ingredient.id] {
                guard available.isFinite && available > 0 else { throw RecipeError.invalid("\(ingredient.name) 보유량은 0보다 큰 값이어야 합니다.") }
                if available < amount {
                    if ingredient.group == "paste" { throw RecipeError.invalid("\(ingredient.name)이 부족합니다. 최소 \(KitchenProfile.number(amount))g을 준비하거나 인분을 줄여주세요.") }
                    warnings.append("\(ingredient.name) 보유량에 맞춰 \(KitchenProfile.number(available))\(ingredient.unit)으로 조정했습니다.")
                    amount = available
                }
            }
            items.append(.init(ingredient: ingredient, amount: amount))
        }
        let stockOptions = items.filter { ["stock", "stockLiquid"].contains($0.ingredient.group) }
        guard stockOptions.count <= 1 else { throw RecipeError.invalid("육수 재료는 한 가지만 선택해주세요. 중복 사용하면 간이 강해질 수 있습니다.") }
        if selected.contains("ssamjang") { warnings.append("쌈장은 된장 대체가 아닌 추가 양념입니다. 당분과 염분을 확인해주세요.") }
        let liquid = Int(((menu == .kimchi ? 500.0 : menu == .sundubu ? 300.0 : 350.0) * scale * (preferences.richness == "맑음" ? 1.2 : preferences.richness == "진함" ? 0.85 : 1)).rounded())
        let suppliedStock = items.first { $0.ingredient.group == "stockLiquid" }.map { Int($0.amount) } ?? 0
        let water = max(0, liquid - suppliedStock)
        warnings.append("분량에 맞는 냄비를 준비하고, 국물과 재료를 넣은 뒤 넘치지 않도록 충분한 여유를 남겨주세요.")
        if kitchen.usesGeneralGuidance == true { warnings.append("주방 등록 없이 약불·중불·강불로 안내합니다. 기기 숫자나 다이얼 위치 대신 실제 끓음 상태를 보며 조절해주세요.") }
        var steps: [CookingStep] = []
        var heat: HeatLevel = .off
        func add(_ action: ActionType, _ title: String, _ text: String, duration: Int = 0, required: [RecipeItem] = [], goal: String = "", condition: String = "동작을 마친 뒤 완료를 확인해주세요.", safety: String = "뜨거운 냄비와 증기에 손이 닿지 않도록 주의해주세요.") {
            steps.append(CookingStep(actionType: action, title: title, instruction: text, heatFrom: heat, heatTo: heat, deviceSetting: kitchen.setting(heat), heatGoal: goal, durationSeconds: duration, requiredItems: required, completionCondition: condition, safetyNotice: safety))
        }
        func change(_ target: HeatLevel) {
            guard target != heat else { return }
            let from = heat
            let text = target == .off ? "\(kitchen.heatingName)의 \(kitchen.burner) 화력을 \(kitchen.setting(from))에서 전원 OFF로 변경해주세요. 실제 전원이 꺼졌는지 확인한 뒤 완료를 눌러주세요." : "\(kitchen.heatingName)의 \(kitchen.burner) 화력을 \(kitchen.setting(from))에서 \(kitchen.setting(target))로 변경해주세요. 변경한 뒤 완료를 눌러주세요."
            heat = target
            steps.append(.init(actionType: .heat, title: target == .off ? "가열 종료" : "\(target.label)로 설정", instruction: text, heatFrom: from, heatTo: target, deviceSetting: kitchen.setting(target), heatGoal: target == .off ? "가열기 전원 꺼짐" : "넘침·연기 없이 가열", durationSeconds: 0, requiredItems: [], completionCondition: "실제 화력 설정을 직접 확인해주세요.", safetyNotice: "앱은 가열기를 제어하지 않습니다. 넘치거나 연기가 나면 즉시 전원을 끄세요."))
        }
        func put(_ item: RecipeItem) {
            add(.add, "\(item.ingredient.name) 넣기", "\(item.ingredient.cut.isEmpty ? "계량한" : item.ingredient.cut + "으로 준비한") \(item.ingredient.name) \(HouseholdMeasure.object(item)) 냄비에 넣어주세요. 넣은 뒤 완료를 눌러주세요.", required: [item])
        }
        add(.check, "조리 준비 확인", "계량한 재료와 물, 국자, 냄비를 준비해주세요. 가열기 전원이 꺼진 것을 확인한 뒤 완료를 눌러주세요.")
        add(.placement, "냄비 배치", "분량에 맞는 냄비를 \(kitchen.burner) 중앙에 놓아주세요. 흔들리지 않고, 국물과 재료를 담을 여유가 있는지 확인해주세요.")
        let aromatics = items.filter { ["garlic", "onion"].contains($0.id) }
        if preferences.saute {
            // Put oil in a cold pan; avoid empty-pan heating for coated cookware.
            if let oil = items.first(where: { $0.id == "oil" }) { put(oil) }
            change(.low)
            add(.simmer, "기름 데우기", "\(kitchen.setting(heat))에서 기름을 20초 동안 데워주세요. 시작을 눌러 타이머를 실행해주세요.", duration: 20, goal: "연기가 나지 않는 상태", safety: "기름에서 연기가 나면 즉시 전원을 끄고 식혀주세요.")
            aromatics.forEach(put)
            add(.stir, "향채 볶기", "\(kitchen.setting(heat))에서 양파 또는 마늘을 40초 동안 바닥을 따라 계속 저어주세요. 시작을 눌러주세요.", duration: 40)
            change(.off)
        }
        if water > 0 { add(.add, "물 계량해 붓기", "물 \(HouseholdMeasure.water(water))를 냄비에 천천히 부어주세요. 부은 뒤 완료를 눌러주세요.", safety: "볶은 냄비에 물을 넣을 때 튐과 증기에 주의해주세요.") }
        items.filter { ["stock", "stockLiquid"].contains($0.ingredient.group) }.forEach(put)
        change(kitchen.calibrationSeconds == nil ? .mediumHigh : .medium)
        let boil = kitchen.calibrationSeconds.map { max(60, Int(Double($0) * Double(max(liquid, suppliedStock)) / Double(kitchen.calibrationWater))) } ?? (150 + preferences.servings * 30)
        add(.simmer, "끓음 확인", "\(kitchen.setting(heat))에서 \(time(boil)) 동안 가열해주세요. 시작을 눌러주세요. 시간이 끝나면 물이 실제로 끓는지 직접 확인해주세요. 끓지 않으면 30초씩 연장해주세요.", duration: boil, goal: "표면에 기포가 지속적으로 올라옴", condition: "타이머와 실제 끓음을 모두 확인해주세요.")
        if let kelp = items.first(where: { $0.id == "kelp" }) { add(.remove, "다시마 꺼내기", "넣었던 다시마 \(kelp.quantityText)을 집게로 꺼내주세요. 꺼낸 뒤 완료를 눌러주세요.", required: [kelp]) }
        if menu == .doenjang {
            items.filter { $0.ingredient.group == "paste" }.forEach(put)
            add(.stir, "된장 풀기", "\(kitchen.setting(heat))에서 국자로 된장 덩어리를 30초 동안 풀어주세요. 시작을 눌러주세요.", duration: 30)
        } else if menu == .kimchi {
            items.filter { $0.id == "kimchi" }.forEach(put)
        }
        let hard = items.filter { $0.ingredient.group == "hard" }
        let proteins = items.filter { ["meat", "seafood"].contains($0.ingredient.group) }
        (hard + proteins).forEach(put)
        if !hard.isEmpty || !proteins.isEmpty {
            let duration = proteins.isEmpty ? 300 : 420
            add(.simmer, "먼저 넣은 재료 익히기", "\(kitchen.setting(heat))에서 \(time(duration)) 동안 끓여주세요. 시작을 눌러주세요. 넘치면 가열기 전원을 OFF로 변경하고 조리를 종료해주세요.", duration: duration, goal: "끓음 유지", condition: proteins.isEmpty ? "감자·무를 찔러 단단한 속이 없는지 확인해주세요." : "육류는 중심온도 75°C에서 1분 이상, 해산물은 중심온도 85°C에서 1분 이상을 확인해주세요. 확인이 어려우면 추가 가열하고 직접 익힘을 확인해주세요.", safety: "시간만으로 익힘을 보증할 수 없습니다. 식품용 온도계로 확인해주세요.")
        }
        if menu == .kimchi {
            change(.medium)
            add(.simmer, "김치 충분히 끓이기", "\(kitchen.setting(heat))에서 김치가 부드러워지도록 10분 동안 끓여주세요. 시작을 눌러주세요. 국물이 줄면 확인 후 물을 조금씩 보충해주세요.", duration: 600, condition: "김치가 부드럽고 고기·해산물이 충분히 익었는지 직접 확인해주세요.")
        }
        items.filter { $0.ingredient.group == "vegetable" && !(preferences.saute && ["onion", "garlic"].contains($0.id)) }.forEach(put)
        items.filter { $0.ingredient.group == "extra" }.forEach(put)
        change(.medium)
        add(.simmer, "채소 끓이기", "\(kitchen.setting(heat))에서 3분 동안 끓여주세요. 시작을 눌러주세요. 뚜껑은 열어두고 넘침을 확인해주세요.", duration: 180, goal: "넘치지 않는 지속적인 끓음", condition: "채소를 찔러 원하는 부드러움인지 확인해주세요.")
        items.filter { $0.ingredient.group == "finish" }.forEach(put)
        change(.mediumLow)
        add(.simmer, "마무리 가열", "\(kitchen.setting(heat))에서 2분 동안 끓여주세요. 시작을 눌러주세요.", duration: 120, goal: "부드러운 끓음", condition: "재료가 충분히 익었는지 직접 확인해주세요.")
        add(.taste, "맛 확인", "국물 5ml를 작은 그릇에 덜고 20초 이상 식힌 뒤 맛을 확인해주세요. 간이 맞으면 완료를 눌러주세요.", safety: "뜨거운 국물을 바로 입에 넣지 마세요.")
        for item in items where item.ingredient.group == "adjust" { put(item) }
        if items.contains(where: { $0.ingredient.group == "adjust" }) { add(.stir, "마지막 양념 섞기", "\(kitchen.setting(heat))에서 20초 동안 국자로 저어주세요. 시작을 눌러주세요.", duration: 20) }
        change(.off)
        add(.finish, "완성 확인", "가열기 전원이 꺼진 것을 다시 확인해주세요. 냄비 손잡이를 맨손으로 잡지 마세요. 완료를 눌러 평가를 남겨주세요.", condition: "가열기 전원 OFF를 직접 확인해주세요.")
        var recipe = Recipe(kitchen: kitchen, preferences: preferences, items: items, waterML: water, steps: steps, warnings: warnings)
        recipe.menu = menu
        recipe.warnings.append(HouseholdMeasure.guide)
        try validate(recipe, selected: selected)
        return recipe
    }
    public static func validate(_ recipe: Recipe, selected: Set<String>) throws {
        guard recipe.items.allSatisfy({ selected.contains($0.id) && $0.amount > 0 && $0.amount.isFinite }), recipe.steps.allSatisfy({ $0.requiredItems.allSatisfy { selected.contains($0.id) } && $0.durationSeconds >= 0 && $0.instruction == $0.speechText }) else { throw RecipeError.invalid("레시피 검증에 실패했습니다.") }
    }
    public static func time(_ seconds: Int) -> String { seconds >= 60 ? "\(seconds / 60)분 \(seconds % 60)초" : "\(seconds)초" }
}
