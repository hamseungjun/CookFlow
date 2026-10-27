import Foundation

/// Keep recipe content, but make cooking checkpoints match meaningful cooking phases.
public enum CookingFlow {
    public static func rebindKitchen(_ original: Recipe, to profile: KitchenProfile) -> Recipe {
        var recipe = original
        let old = original.kitchen
        func remap(_ text: String) -> String {
            var value = text
            for (index, level) in HeatLevel.allCases.enumerated().sorted(by: { old.setting($0.element).count > old.setting($1.element).count }) {
                value = value.replacingOccurrences(of: old.setting(level), with: "__BOUND_HEAT_\(index)__")
            }
            for (index, level) in HeatLevel.allCases.enumerated() { value = value.replacingOccurrences(of: "__BOUND_HEAT_\(index)__", with: profile.setting(level)) }
            return value
        }
        recipe.kitchen = profile
        for index in recipe.steps.indices {
            recipe.steps[index].deviceSetting = profile.setting(recipe.steps[index].heatTo)
            recipe.steps[index].instruction = remap(recipe.steps[index].instruction)
            recipe.steps[index].flowInstructions = recipe.steps[index].flowInstructions?.map(remap)
        }
        refreshNarration(&recipe)
        return recipe
    }
    public static func prepare(_ original: Recipe, kitchen: KitchenProfile? = nil) -> Recipe {
        var recipe = original
        let profile = kitchen ?? recipe.kitchen
        func remap(_ instruction: String) -> String {
            var text = instruction
            for (index, level) in HeatLevel.allCases.enumerated().sorted(by: { original.kitchen.setting($0.element).count > original.kitchen.setting($1.element).count }) {
                text = text.replacingOccurrences(of: original.kitchen.setting(level), with: "__HEAT_\(index)__")
            }
            for (index, level) in HeatLevel.allCases.enumerated() { text = text.replacingOccurrences(of: "__HEAT_\(index)__", with: profile.setting(level)) }
            return clean(text)
        }
        let mapped = recipe.steps.map { step -> CookingStep in
            var result = step
            if let instructions = step.flowInstructions {
                result.flowInstructions = instructions.map(remap)
                result.instruction = (result.flowInstructions ?? []).joined(separator: "\n")
                result.spokenInstruction = CookingNarration.text(for: result, kitchen: profile)
            } else if step.actionType == .heat && step.durationSeconds == 0 {
                result.instruction = step.heatTo == .off ? "가열기를 꺼주세요." : "\(profile.burner)를 \(profile.setting(step.heatTo))로 맞춰주세요."
            } else { result.instruction = remap(step.instruction) }
            result.deviceSetting = profile.setting(result.heatTo)
            return result
        }
        if recipe.flowVersion != nil { recipe.kitchen = profile; recipe.steps = mapped; addInitialPreheat(&recipe); simplifyPreheat(&recipe); refreshNarration(&recipe); return recipe }
        var pending: [CookingStep] = []
        var groups: [CookingStep] = []
        func flush() {
            guard let first = pending.first, let last = pending.last else { return }
            var stage = last
            stage.id = first.id
            stage.heatFrom = first.heatFrom
            stage.flowInstructions = pending.map { step in
                let text = clean(step.instruction)
                return text
            }
            // Only cooking waits get a timer. Ten-second button/placement timers become instructions.
            stage.durationSeconds = usesTimer(last) ? last.durationSeconds : 0
            stage.title = stage.durationSeconds > 0 || last.actionType == .simmer || last.actionType == .stir ? last.title : last.actionType == .finish ? "간 보고, 불 끄고 완성" : "재료 넣기"
            if last.title == "끓음 확인" { stage.title = "육수 끓이기" }
            if last.title == "채소 끓이기" { stage.title = "채소 넣고 익히기" }
            if last.title == "마무리 가열" { stage.title = "두부·마무리 재료 넣고 끓이기" }
            if stage.durationSeconds == 0 && last.actionType != .finish && pending.contains(where: { $0.title == "된장 풀기" }) { stage.title = "된장 풀고 채소 넣기" }
            var seen = Set<String>()
            stage.requiredItems = pending.flatMap(\.requiredItems).filter { seen.insert($0.id).inserted }
            stage.instruction = (stage.flowInstructions ?? []).joined(separator: "\n")
            stage.timerStartEvent = stage.requiredItems.isEmpty ? "화력 설정 확인 후 시작" : "재료 투입 확인 후 시작"
            stage.completionCondition = last.completionCondition.replacingOccurrences(of: "타이머와 실제 끓음을 모두 확인해주세요.", with: "물이 아직 끓지 않으면 시간을 추가해주세요.")
            stage.spokenInstruction = CookingNarration.text(for: stage, kitchen: profile)
            groups.append(stage); pending.removeAll()
        }
        for step in mapped {
            if step.actionType == .placement || (step.actionType == .check && step.instruction.hasPrefix("계량한 재료와")) { continue }
            pending.append(step)
            if step.actionType == .simmer || usesTimer(step) { flush() }
        }
        flush()
        recipe.kitchen = profile; recipe.steps = groups; recipe.flowVersion = 3
        addInitialPreheat(&recipe)
        simplifyPreheat(&recipe)
        refreshNarration(&recipe)
        return recipe
    }
    private static func addInitialPreheat(_ recipe: inout Recipe) {
        // Preheat only an initial oil-based fry. Boiling, cold-oil blooming, and no-heat recipes retain their order.
        guard var first = recipe.steps.first, first.actionType == .stir, first.heatTo != .low,
              first.requiredItems.contains(where: { $0.id == "oil" }),
              !(first.flowInstructions ?? [first.instruction]).contains(where: { $0.contains("예열") || $0.contains("기름을 20초") }) else { return }
        let kitchen = recipe.kitchen
        let instructions = ["식용유를 두르고 2분간 예열해주세요."]
        var preheat = CookingStep(actionType: .heat, title: "팬·냄비 예열", instruction: instructions.joined(separator: "\n"), heatFrom: .off, heatTo: .medium, deviceSetting: kitchen.setting(.medium), heatGoal: "볶기 전 예열", durationSeconds: 120, requiredItems: [], completionCondition: "불을 맞춘 뒤 예열 타이머 시작", safetyNotice: "")
        preheat.flowInstructions = instructions; preheat.timerStartEvent = "화력 설정 확인 후 시작"
        first.heatFrom = .medium
        first.flowInstructions = (first.flowInstructions ?? [first.instruction]).map { text in
            text.contains("식용유") && text.contains("넣") ? "아직 기름을 두르지 않았다면 " + text : text
        }
        first.instruction = (first.flowInstructions ?? []).joined(separator: "\n")
        recipe.steps[0] = first
        recipe.steps.insert(preheat, at: 0)
        recipe.flowVersion = 3
    }
    private static func simplifyPreheat(_ recipe: inout Recipe) {
        guard recipe.steps.count > 1, recipe.steps[0].title == "팬·냄비 예열" else { return }
        let oil = recipe.steps[1].requiredItems.filter { $0.id == "oil" }
        guard !oil.isEmpty else { return }
        recipe.steps[0].requiredItems = oil
        recipe.steps[0].flowInstructions = ["식용유를 두르고 2분간 예열해주세요."]
        recipe.steps[0].instruction = "식용유를 두르고 2분간 예열해주세요."
        recipe.steps[0].timerStartEvent = "재료 투입 확인 후 시작"
        recipe.steps[0].safetyNotice = ""
        recipe.steps[1].requiredItems.removeAll { $0.id == "oil" }
        let remainingNames = recipe.steps[1].requiredItems.map { $0.ingredient.name }
        let instructions = (recipe.steps[1].flowInstructions ?? [recipe.steps[1].instruction]).compactMap { text -> String? in
            let body = text.replacingOccurrences(of: "아직 기름을 두르지 않았다면 ", with: "")
            if body.contains("식용유"), !remainingNames.contains(where: body.contains) { return nil }
            return body.replacingOccurrences(of: #"(?:식용유|기름)\s*(?:약\s*)?(?:[0-9½¼¾⅓⅔.]+\s*(?:큰술|작은술|g|ml)\s*)?[을를]?\s*(?:넣고|두르고|넣어주세요[.!]?|둘러주세요[.!]?)\s*"#, with: "", options: .regularExpression)
        }
        recipe.steps[1].flowInstructions = instructions
        recipe.steps[1].instruction = instructions.joined(separator: "\n")
    }
    private static func refreshNarration(_ recipe: inout Recipe) {
        let snapshot = recipe
        for index in recipe.steps.indices {
            recipe.steps[index].spokenInstruction = CookingNarration.text(for: recipe.steps[index], recipe: snapshot)
        }
    }
    static func usesTimer(_ step: CookingStep) -> Bool { step.durationSeconds > 0 && ([.stir, .simmer].contains(step.actionType) || step.durationSeconds >= 60) }
    static func clean(_ text: String) -> String {
        let source = text.replacingOccurrences(of: "빈 용기 예열을 금지하는 코팅 용기는 기름을 먼저 두르고 제조사 사용법을 따라주세요.", with: "")
        var result = source.replacingOccurrences(of: "\n시작을 눌러 [^\n]*타이머를 실행하고, 실제 상태가 부족하면 연장해주세요.", with: "", options: .regularExpression)
        for phrase in ["시작을 눌러 타이머를 실행해주세요.", "시작을 눌러주세요.", "변경한 뒤 완료를 눌러주세요.", "실제 전원이 꺼졌는지 확인한 뒤 완료를 눌러주세요."] { result = result.replacingOccurrences(of: phrase, with: "") }
        for (phrase, replacement) in ["확인한 뒤 완료를 눌러주세요.": "확인해주세요.", "넣은 뒤 완료를 눌러주세요.": "", "부은 뒤 완료를 눌러주세요.": "", "꺼낸 뒤 완료를 눌러주세요.": "", "간이 맞으면 완료를 눌러주세요.": "간이 맞는지 봐주세요.", "완료를 눌러 평가를 남겨주세요.": "요리가 완성됐어요."] {
            result = result.replacingOccurrences(of: phrase, with: replacement)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum CookingNarration {
    private static func repeatedIngredients(in recipe: Recipe) -> Set<String> {
        Set(recipe.items.filter { item in
            recipe.steps.flatMap { $0.flowInstructions ?? [$0.instruction] }.filter {
                $0.range(of: NSRegularExpression.escapedPattern(for: item.ingredient.name) + #"\s+(?:약\s*)?[0-9½¼¾⅓⅔]+"#, options: .regularExpression) != nil && ($0.contains("넣") || $0.contains("붓") || $0.contains("부어"))
            }.count > 1
        }.map(\.id))
    }
    public static func text(for step: CookingStep, recipe: Recipe) -> String {
        text(for: step, kitchen: recipe.kitchen, repeated: repeatedIngredients(in: recipe))
    }
    /// Screen rows share the same essential actions as speech, without speaking list markers.
    public static func actions(for step: CookingStep, recipe: Recipe) -> [String] {
        let directions = text(for: step, kitchen: recipe.kitchen, repeated: repeatedIngredients(in: recipe), includeControls: false)
        var seen = Set<String>()
        return statements(directions).filter { seen.insert($0).inserted }
    }
    private static func statements(_ text: String) -> [String] {
        let unmarked = text.components(separatedBy: .newlines).map {
            $0.replacingOccurrences(of: #"^\s*(?:[-•]|[0-9]+[.)])\s+"#, with: "", options: .regularExpression)
        }.joined(separator: "\n")
        return unmarked.replacingOccurrences(of: #"(?<=[.!?])\s+"#, with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    public static func text(for step: CookingStep, kitchen: KitchenProfile) -> String {
        text(for: step, kitchen: kitchen, repeated: [])
    }

    private static func objectParticle(_ name: String) -> String {
        guard let scalar = name.unicodeScalars.last, (0xAC00...0xD7A3).contains(scalar.value) else { return "를" }
        return (scalar.value - 0xAC00) % 28 == 0 ? "를" : "을"
    }

    private static func text(for step: CookingStep, kitchen: KitchenProfile, repeated: Set<String>, includeControls: Bool = true) -> String {
        let instructions = step.flowInstructions ?? [step.instruction]
        let heat = kitchen.spokenSetting(step.heatTo)
        let directions = instructions.compactMap { text -> String? in
            let body = text.components(separatedBy: "\n이번 조리 계량:").first?.components(separatedBy: "\n우리 주방 설정:").first ?? text
            if body.hasPrefix("계량한 재료와") || body == "\(kitchen.burner)를 \(kitchen.setting(step.heatTo))로 맞춰주세요." { return nil }
            let useful = statements(CookingFlow.clean(body)).filter { sentence in
                !["흔들리지", "안정적으로 놓", "중앙에 놓", "화구 중앙", "조리 도구", "국자, 냄비", "담을 여유", "손질된 채소", "계량한 재료와"].contains(where: sentence.contains)
            }
            var sentence = useful.joined(separator: ". ")
            guard !sentence.isEmpty else { return nil }
            // Preparation has already measured and cut these ingredients. Keep split portions explicit.
            let portionMarkers = ["절반", "나머지", "반만", "일부", "조금씩", "나눠", "남겨"]
            if !portionMarkers.contains(where: sentence.contains) {
                for item in step.requiredItems where item.ingredient.category == .fresh && !repeated.contains(item.id) {
                    let name = NSRegularExpression.escapedPattern(for: item.ingredient.name)
                    let quantity = #"(?:약\s*)?[0-9½¼¾⅓⅔⅛⅜⅝⅞]+(?:[./~–-][0-9]+)?\s*(?:모|봉|개|대|장|g|kg|그램|컵|큰술|작은술)(?:\s*\([^)]*\))?"#
                    sentence = sentence.replacingOccurrences(of: "\(name)\\s+\(quantity)([을를])", with: item.ingredient.name + objectParticle(item.ingredient.name), options: .regularExpression)
                    let prefix = item.ingredient.cut.isEmpty ? "계량한 " : item.ingredient.cut + "으로 준비한 "
                    sentence = sentence.replacingOccurrences(of: prefix + item.ingredient.name, with: item.ingredient.name)
                    sentence = sentence.replacingOccurrences(of: "준비한 " + item.ingredient.name, with: item.ingredient.name)
                }
            }
            sentence = sentence.replacingOccurrences(of: "계량한 ", with: "")
            for item in step.requiredItems where item.ingredient.category == .seasoning {
                sentence = sentence.replacingOccurrences(of: item.householdQuantity, with: item.householdQuantity.components(separatedBy: " (").first ?? item.householdQuantity)
            }
            if ["넣", "붓", "부어"].contains(where: sentence.contains) {
                for item in step.requiredItems where item.ingredient.category == .seasoning {
                    let name = NSRegularExpression.escapedPattern(for: item.ingredient.name)
                    let amount = item.householdQuantity.components(separatedBy: " (").first ?? item.householdQuantity
                    let measured = sentence.range(of: name + #"\s+(?:약\s*)?[0-9½¼¾⅓⅔]"#, options: .regularExpression) != nil
                    if !measured {
                        if sentence.range(of: name + "[을를]", options: .regularExpression) != nil {
                            sentence = sentence.replacingOccurrences(of: name + "[을를]", with: item.ingredient.name + " " + amount + objectParticle(amount), options: .regularExpression)
                        } else {
                            sentence = sentence.replacingOccurrences(of: name + #"(?![을를]|\s+(?:약\s*)?[0-9½¼¾⅓⅔])"#, with: item.ingredient.name + " " + amount, options: .regularExpression)
                        }
                    }
                }
            }
            return sentence.replacingOccurrences(of: kitchen.setting(step.heatTo) + "에서 ", with: "").replacingOccurrences(of: "분량에 맞는 냄비", with: "냄비")
        }.joined(separator: ". ")
        if !includeControls { return directions.replacingOccurrences(of: "..", with: ".") }
        // Amounts are already attached to the actual ingredient-addition actions.
        let quantity = ""
        let timer = step.durationSeconds > 0 ? (step.timerStartEvent == "재료 투입 확인 후 시작" ? " 재료를 넣었으면 알려주세요." : step.timerStartEvent == "화력 설정 확인 후 시작" ? " 불을 맞췄으면 알려주세요." : " 준비됐으면 알려주세요.") : ""
        let heatFirst = step.actionType == .stir || (step.actionType == .heat && step.durationSeconds > 0) || step.heatFrom != .off
        let result = (step.actionType == .finish ? "이제 마무리해볼게요. " : heatFirst ? "\(heat). " : "") + quantity + directions + (step.actionType == .finish || heatFirst ? "" : " \(heat).") + timer
        return result.replacingOccurrences(of: "..", with: ".")
    }
}
