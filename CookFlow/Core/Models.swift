import Foundation

public enum HeatingType: String, Codable, CaseIterable, Identifiable {
    case induction = "인덕션", radiant = "하이라이트", gas = "가스레인지", other = "기타"
    public var id: String { rawValue }
}
public enum ControlType: String, Codable, CaseIterable, Identifiable {
    case numbered = "숫자 버튼", slider = "터치 슬라이더", dial = "다이얼", knob = "손잡이"
    public var id: String { rawValue }
    public var isNumeric: Bool { self == .numbered || self == .slider }
}
public enum HeatLevel: String, Codable, CaseIterable {
    case off, low, mediumLow, medium, mediumHigh, high
    public var label: String {
        switch self { case .off: return "전원 OFF"; case .low: return "약불"; case .mediumLow: return "중약불"; case .medium: return "중불"; case .mediumHigh: return "중강불"; case .high: return "강불" }
    }
}
public struct KitchenProfile: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var usesGeneralGuidance: Bool? = nil
    public var name = "우리 집 주방"
    public var heatingType: HeatingType = .induction
    public var controlType: ControlType = .numbered
    public var minimum: Double = 1
    public var maximum: Double = 9
    public var halfSteps = false
    public var boost = false
    public var burner = "왼쪽 화구"
    public var numericMap: [String: Double] = ["low": 2, "mediumLow": 4, "medium": 6, "mediumHigh": 8, "high": 9]
    public var dialMap: [String: String] = ["low": "첫 번째 눈금", "mediumLow": "첫 번째와 두 번째 눈금 사이", "medium": "두 번째 눈금", "mediumHigh": "두 번째와 세 번째 눈금 사이", "high": "세 번째 눈금"]
    public var dialConfiguration: DialConfiguration? = nil
    // Legacy cookware values remain decodable for saved profiles and recipes.
    public var material = "스테인리스"
    public var diameter: Double = 20
    public var capacity: Double = 2000
    public var hasLid = true
    public var calibrationSeconds: Int? = nil
    public var calibrationWater: Int = 500
    public var calibrationSetting = "중불"
    public init() {}
    public static func generalGuidance() -> KitchenProfile {
        var profile = KitchenProfile()
        profile.usesGeneralGuidance = true
        profile.name = "기본 요리 안내"
        profile.burner = "화구"
        profile.heatingType = .other
        return profile
    }
    public var heatingName: String { usesGeneralGuidance == true ? "가열기" : heatingType.rawValue }
    public func setting(_ level: HeatLevel) -> String {
        guard level != .off else { return "전원 OFF" }
        if usesGeneralGuidance == true { return level.label }
        if controlType.isNumeric {
            let value = numericMap[level.rawValue] ?? minimum
            return "\(Self.number(value))단계"
        }
        if let dialConfiguration {
            return "다이얼 " + DialConfiguration.clockLabel(dialConfiguration.angle(for: level))
        }
        return dialMap[level.rawValue] ?? "등록 필요"
    }
    public func spokenSetting(_ level: HeatLevel) -> String {
        if level == .off { return "불은 꺼둔 상태예요" }
        if usesGeneralGuidance == true { return "불은 \(level.label)로 맞춰주세요" }
        return "\(setting(level)), \(level.label)로 맞춰주세요"
    }
    public func validationErrors() -> [String] {
        var result: [String] = []
        if !minimum.isFinite || !maximum.isFinite || numericMap.values.contains(where: { !$0.isFinite }) { return ["주방 수치는 유효한 숫자로 입력해주세요."] }
        if let seconds = calibrationSeconds, !(10...3600).contains(seconds) || calibrationWater <= 0 { result.append("보정 수량과 시간을 확인해주세요.") }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append("주방 이름을 입력해주세요.") }
        if heatingType == .gas && controlType.isNumeric { result.append("가스레인지는 실제 눈금 기준으로 다이얼 또는 손잡이를 선택해주세요.") }
        if controlType.isNumeric {
            if minimum >= maximum { result.append("최소 단계는 최대 단계보다 작아야 합니다.") }
            for level in HeatLevel.allCases where level != .off {
                let value = numericMap[level.rawValue] ?? -1
                if value <= 0 { result.append("0단계는 전원 OFF입니다. 조리 화력은 0보다 크게 지정해주세요.") }
                if value < minimum || value > maximum { result.append("\(level.label) 설정값이 기기 범위를 벗어납니다.") }
                if !halfSteps && value.rounded() != value { result.append("소수 단계 지원을 켜거나 정수로 입력해주세요.") }
                if halfSteps && (value * 2).rounded() != value * 2 { result.append("화력은 0.5단계 단위로 입력해주세요.") }
            }
            let values = HeatLevel.allCases.filter { $0 != .off }.map { numericMap[$0.rawValue] ?? 0 }
            if zip(values, values.dropFirst()).contains(where: { $0 > $1 }) { result.append("약불부터 강불까지 설정값이 순서대로 증가해야 합니다.") }
        } else if let dialConfiguration {
            result.append(contentsOf: dialConfiguration.validationErrors)
        } else if HeatLevel.allCases.filter({ $0 != .off }).contains(where: { (dialMap[$0.rawValue] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }) {
            result.append("모든 화력의 눈금 또는 방향을 입력해주세요.")
        }
        return Array(Set(result)).sorted()
    }
    public static func number(_ value: Double) -> String { guard value.isFinite, abs(value) < 1_000_000_000 else { return "확인 필요" }; return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
}
public enum IngredientCategory: String, Codable, CaseIterable { case fresh = "식재료", seasoning = "조미료·양념" }
public struct Ingredient: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let category: IngredientCategory
    public let unit: String
    public let baseAmount: Double // 2 servings
    public let cut: String
    public let group: String
    public init(_ id: String, _ name: String, _ category: IngredientCategory, _ unit: String, _ amount: Double, _ cut: String = "", _ group: String = "") {
        self.id = id; self.name = name; self.category = category; self.unit = unit; self.baseAmount = amount; self.cut = cut; self.group = group
    }
}
public enum PreparationShape: String { case julienne, dice, half_moon, slice, chopped, whole, beaten, unclear }
public enum PreparationGuide {
    public static func shape(_ cut: String) -> PreparationShape {
        if cut.contains("풀어") || cut.contains("풀기") || cut.contains("휘저") || cut.contains("휘젓") { return .beaten }
        if cut.contains("봉지") || cut.contains("통째") { return .whole }
        if cut.contains("다지") || cut.contains("다진") || cut.contains("다져") { return .chopped }
        if cut.contains("깍둑") || cut.contains("깍뚝") || cut.contains("큐브") || cut.contains("조각") || cut.contains("덩어리") || cut.contains("토막") { return .dice }
        if cut.contains("채썰") || cut.contains("채 썰") { return .julienne }
        if cut.contains("반달") { return .half_moon }
        if cut.contains("송송") || cut.contains("어슷") || cut.contains("슬라이스") || cut.contains("편썰") || cut.contains("썰기") { return .slice }
        return .unclear
    }
    public static func instruction(name: String, cut: String) -> String {
        let particle: String
        if let scalar = name.unicodeScalars.last, (0xAC00...0xD7A3).contains(scalar.value) { particle = (scalar.value - 0xAC00) % 28 == 0 ? "를" : "을" } else { particle = "를" }
        let object = name + particle
        if cut.contains("그대로") { return object + " 그대로 준비해주세요." }
        if cut.contains("봉지") { return object + " 봉지째 준비해주세요. 조리할 때 숟가락으로 떠 넣어요." }
        if cut.contains("송송") { return object + " 송송 썰어주세요." }
        if cut.contains("어슷") { return object + " 어슷썰어주세요." }
        switch shape(cut) {
        case .beaten: return object + " 볼에 깨 넣고 잘 풀어주세요."
        case .chopped: return object + " 다져주세요."
        case .dice: return object + " 깍둑썰어주세요."
        case .julienne: return object + " 채썰어주세요."
        case .half_moon: return object + " 반달 모양으로 썰어주세요."
        case .slice: return object + " 썰어주세요."
        case .whole: return object + " 통째로 준비해주세요."
        case .unclear:
            let cleaned = cut.replacingOccurrences(of: #"(?:약\s*)?[0-9０-９]+(?:[.,][0-9０-９]+)?(?:\s*[~〜–—-]\s*[0-9０-９]+(?:[.,][0-9０-９]+)?)?\s*(?:cm|mm|㎝|㎜|센티미터|밀리미터|센치)(?:\s*(?:이하|이상|정도|두께))?"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? object + " 준비해주세요." : object + " · " + cleaned
        }
    }
}
public enum Catalog {
    public static let items: [Ingredient] = [
        .init("thinBeef", "우삼겹", .fresh, "g", 180, "얇은 고기를 준비" , "meat"),
        .init("mungSprout", "숙주", .fresh, "g", 300, "헹구고 물기 빼기" , "vegetable"),
        .init("spam", "스팸", .fresh, "g", 160, "먹기 좋은 크기로 썰기" , "meat"),
        .init("sausage", "소시지", .fresh, "g", 300, "칼집 내기" , "meat"),
        .init("mincedPork", "돼지고기 다짐육", .fresh, "g", 200, "다짐육을 준비" , "meat"),
        .init("wholeGarlic", "통마늘", .fresh, "g", 30, "얇게 편썰기" , "vegetable"),
        .init("pasta", "파스타면", .fresh, "g", 200, "건면 계량하기" , "pasta"),
        .init("burrata", "부라타", .fresh, "개", 1, "포장을 열고 물기 빼기" , "finish"),
        .init("milk", "우유", .fresh, "ml", 160, "" , "dairy"),
        .init("cream", "생크림", .fresh, "ml", 160, "" , "dairy"),
        .init("oysterSauce", "굴소스", .seasoning, "ml", 15, "" , "seasoning"),
        .init("cookingWine", "맛술", .seasoning, "ml", 30, "" , "seasoning"),
        .init("ketchup", "케첩", .seasoning, "ml", 60, "" , "seasoning"),
        .init("butter", "버터", .seasoning, "g", 10, "" , "oil"),
        .init("doubanjiang", "두반장", .seasoning, "g", 36, "" , "seasoning"),
        .init("starch", "전분", .seasoning, "g", 10, "" , "seasoning"),
        .init("oliveOil", "올리브오일", .seasoning, "ml", 40, "" , "oil"),
        .init("peperoncino", "페퍼론치노", .seasoning, "개", 4, "" , "seasoning"),
        .init("tomatoPuree", "토마토 퓨레", .seasoning, "g", 360, "" , "seasoning"),
        .init("egg", "달걀", .fresh, "개", 2, "깨끗한 그릇에 깨서 껍데기 제거" , "egg"),
        .init("chicken", "닭고기", .fresh, "g", 600, "토막 닭의 표면 물기 제거" , "meat"),
        .init("squid", "오징어", .fresh, "g", 300, "손질 후 1cm 폭으로 썰기" , "seafood"),
        .init("carrot", "당근", .fresh, "g", 80, "0.5cm 두께로 썰기" , "vegetable"),
        .init("beanSprout", "콩나물", .fresh, "g", 200, "흐르는 물에 헹구고 물기 빼기" , "vegetable"),
        .init("spinach", "시금치", .fresh, "g", 200, "깨끗이 씻고 뿌리 끝 정리하기" , "vegetable"),
        .init("cucumber", "오이", .fresh, "g", 200, "0.5cm 두께로 썰기" , "vegetable"),
        .init("seaweed", "마른 미역", .fresh, "g", 8, "불린 뒤 헹구고 3cm 길이로 자르기" , "vegetable"),
        .init("driedAnchovy", "볶음용 멸치", .fresh, "g", 80, "잔멸치를 준비하고 이물질 직접 확인" , "seafood"),
        .init("riceCooked", "익힌 밥", .fresh, "g", 400, "갓 지었거나 냉장 보관한 밥 준비" , "rice"),
        .init("tunaCan", "참치캔", .fresh, "g", 100, "캔을 열어 기름이나 물을 빼기" , "seafood"),
        .init("sesameOil", "참기름", .seasoning, "ml", 5, "" , "oil"),
        .init("sesame", "참깨", .seasoning, "g", 3, "" , "seasoning"),
        .init("vinegar", "식초", .seasoning, "ml", 15, "" , "seasoning"),
        .init("mayonnaise", "마요네즈", .seasoning, "g", 20, "" , "seasoning"),

        .init("kimchi", "김치", .fresh, "g", 250, "2~3cm 조각" , "kimchi"),
        .init("tofu", "두부", .fresh, "g", 150, "1.5~2cm 깍둑" , "finish"),
        .init("softTofu", "순두부", .fresh, "g", 180, "4cm 덩어리" , "finish"),
        .init("zucchini", "애호박", .fresh, "g", 80, "0.5~0.8cm 반달" , "vegetable"),
        .init("potato", "감자", .fresh, "g", 100, "1~1.5cm 조각" , "hard"),
        .init("onion", "양파", .fresh, "g", 50, "1.5~2cm 조각" , "vegetable"),
        .init("scallion", "대파", .fresh, "g", 20, "0.5cm 송송" , "finish"),
        .init("radish", "무", .fresh, "g", 80, "0.5cm 나박" , "hard"),
        .init("chili", "청양고추", .fresh, "g", 8, "0.3cm 송송" , "finish"),
        .init("redChili", "홍고추", .fresh, "g", 8, "0.3cm 송송" , "finish"),
        .init("garlic", "마늘", .fresh, "g", 5, "0.3cm 이하 다지기" , "vegetable"),
        .init("mushroom", "버섯", .fresh, "g", 60, "0.5cm 슬라이스" , "vegetable"),
        .init("cabbage", "배추", .fresh, "g", 70, "2cm 조각" , "vegetable"),
        .init("beef", "소고기", .fresh, "g", 100, "1cm 두께 이하 조각" , "meat"),
        .init("pork", "돼지고기", .fresh, "g", 100, "1cm 두께 이하 조각" , "meat"),
        .init("clam", "바지락", .fresh, "g", 150, "해감 후 껍데기 세척" , "seafood"),
        .init("shrimp", "새우", .fresh, "g", 100, "껍질·내장 제거" , "seafood"),
        .init("doenjang", "된장", .seasoning, "g", 30, "" , "paste"),
        .init("tojang", "토장", .seasoning, "g", 30, "" , "paste"),
        .init("ssamjang", "쌈장", .seasoning, "g", 5, "" , "extra"),
        .init("gochujang", "고추장", .seasoning, "g", 5, "" , "extra"),
        .init("salt", "소금", .seasoning, "g", 0.5, "" , "adjust"),
        .init("sugar", "설탕", .seasoning, "g", 1, "" , "adjust"),
        .init("chiliPowder", "고춧가루", .seasoning, "g", 2, "" , "extra"),
        .init("pepper", "후추", .seasoning, "g", 0.2, "" , "adjust"),
        .init("soySauce", "진간장", .seasoning, "ml", 2, "" , "adjust"),
        .init("soupSoy", "국간장", .seasoning, "ml", 2, "" , "adjust"),
        .init("fishSauce", "멸치액젓", .seasoning, "ml", 2, "" , "adjust"),
        .init("shrimpPaste", "새우젓", .seasoning, "g", 2, "" , "adjust"),
        .init("stockCoin", "코인육수", .seasoning, "개", 1, "" , "stock"),
        .init("anchovyStock", "멸치육수", .seasoning, "ml", 350, "" , "stockLiquid"),
        .init("kelp", "다시마", .seasoning, "g", 2, "" , "stock"),
        .init("chickenStock", "치킨스톡", .seasoning, "g", 2, "" , "stock"),
        .init("oil", "식용유", .seasoning, "ml", 5, "" , "oil")
    ]
    public static func item(_ id: String) -> Ingredient? { items.first { $0.id == id } }
}
public struct Preferences: Codable, Equatable {
    public var servings = 1
    public var spice = 1
    public var salt = 1
    public var richness = "보통"
    public var excludeMeat = false
    public var excludeSeafood = false
    public var saute = false
    public init() {}
}
public struct RecipeItem: Codable, Identifiable, Equatable {
    public var id: String { ingredient.id }
    public let ingredient: Ingredient
    public let amount: Double
    public var quantityText: String { "\(KitchenProfile.number(amount))\(ingredient.unit)" }
    public var householdQuantity: String { HouseholdMeasure.ingredient(self) }
    public var preparationInstruction: String { PreparationGuide.instruction(name: ingredient.name, cut: ingredient.cut) }
    public var preparationShape: PreparationShape { PreparationGuide.shape(ingredient.cut) }
    public var measureText: String {
        if ingredient.group == "paste" { return "약 \(KitchenProfile.number(amount / 18))큰술 (15ml 계량 큰술 기준, 제품 밀도에 따라 차이)" }
        if ingredient.unit == "ml" && amount <= 30 { return "\(KitchenProfile.number(amount / 15))큰술 · 1큰술 = 15ml" }
        return preparationInstruction
    }
}
public enum ActionType: String, Codable { case check, placement, heat, add, stir, simmer, remove, taste, finish }
public struct CookingStep: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var actionType: ActionType
    public var title: String
    public var instruction: String
    public var heatFrom: HeatLevel
    public var heatTo: HeatLevel
    public var deviceSetting: String
    public var heatGoal: String
    public var durationSeconds: Int
    public var timerStartEvent: String = "사용자가 시작을 확인한 시점"
    public var requiredItems: [RecipeItem]
    public var completionCondition: String
    public var safetyNotice: String
    public var flowInstructions: [String]? = nil
    public var spokenInstruction: String? = nil
    public var speechText: String { spokenInstruction ?? instruction }
}
public enum RecipeOrigin: String, Codable, CaseIterable { case ai, youtube, preset
    public var label: String { switch self { case .ai: return "AI 맞춤"; case .youtube: return "유튜브"; case .preset: return "기본 집밥" } }
}
public struct SavedRecipe: Codable, Identifiable {
    public var recipe: Recipe
    public var favorite = false
    public var savedAt = Date()
    public var id: UUID { recipe.id }
    public init(recipe: Recipe) { self.recipe = recipe }
}
public struct Recipe: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var createdAt = Date()
    public var menu: RecipeMenu? = nil
    public var importedTitle: String? = nil
    public var sourceVideoURL: String? = nil
    public var origin: RecipeOrigin? = nil
    public var flowVersion: Int? = nil
    public var recipeOrigin: RecipeOrigin { origin ?? (sourceVideoURL == nil ? .preset : .youtube) }
    public var title: String { importedTitle ?? (menu ?? .doenjang).title }
    public var waterMeasure: String { HouseholdMeasure.water(waterML) }
    public var templateVersion = "1.3-native-1"
    public var kitchen: KitchenProfile
    public var preferences: Preferences
    public var items: [RecipeItem]
    public var waterML: Int
    public var steps: [CookingStep]
    public var warnings: [String]
    public var revisions: [RecipeRevision] = []
    public var estimatedSeconds: Int { steps.reduce(0) { $0 + $1.durationSeconds } + steps.filter { $0.durationSeconds == 0 }.count * 25 }
}
public enum SessionState: String, Codable { case draft, confirmed, preparing, ready, cooking, paused, completed, saved, cancelled }
public enum StepPhase: String, Codable { case ready, active, awaitingConfirmation, done }
public struct StepEvent: Codable, Identifiable {
    public var id = UUID()
    public var at: Date
    public var stepID: UUID?
    public var type: String
    public var detail: String
    public var label: String {
        switch type {
        case "PREP_ALL_APPROVED": return "사용자 준비 완료"
        case "PREP_USER_APPROVED": return "손질 직접 확인"
        case "BEGIN_COOKING": return "조리 시작"
        case "START_TIMER": return "타이머 시작"
        case "TIMER_EXPIRED": return "타이머 종료 · 확인 대기"
        case "AUTO_ADVANCE": return "시간 종료 · 다음 단계 안내"
        case "PREVIOUS_STEP": return "이전 단계로 돌아가기"
        case "USER_DONE": return "요리 단계 완료"
        case "USER_DONE_EARLY": return "실제 익힘 확인 후 먼저 완료"
        case "PAUSE": return "일시정지"
        case "RESUME": return "조리 재개"
        case "ADD_TIME": return "시간 추가"
        case "CANCEL": return "조리 종료"
        case "REVISE_RECIPE": return "남은 재료 수정"
        case "AUX_TIMER_START": return "보조 타이머 시작"
        case "AUX_TIMER_DONE": return "보조 타이머 종료"
        case "AUX_TIMER_REMOVE": return "보조 타이머 삭제"
        default: return "조리 기록"
        }
    }
}
public struct Review: Codable {
    public var taste = 4
    public var salt = 1
    public var spice = 1
    public var notes = ""
    public init() {}
}
public enum PrepStatus: String, Codable {
    case pending, approved
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = ["approved", "pass", "userConfirm"].contains(value) ? .approved : .pending
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
public struct PreparationCheck: Codable, Identifiable {
    public var id: String
    public var status: PrepStatus = .pending
    public var feedback = "손질 모양과 준비 수량을 확인해주세요."
    public var confidence: Double? = nil
}
public struct CookingSession: Codable, Identifiable {
    public var id = UUID()
    public var recipe: Recipe
    public var state: SessionState = .preparing
    public var phase: StepPhase = .ready
    public var stepIndex = 0
    public var targetEndAt: Date? = nil
    public var pausedSeconds: Double? = nil
    public var startedAt: Date? = nil
    public var completedAt: Date? = nil
    public var events: [StepEvent] = []
    public var auxiliaryTimers: [AuxiliaryTimer] = []
    public var processedKeys: Set<String> = []
    public var checks: [PreparationCheck]
    public var review = Review()
    public var currentStep: CookingStep? { recipe.steps.indices.contains(stepIndex) ? recipe.steps[stepIndex] : nil }
    public var elapsedSeconds: Int { guard let start = startedAt else { return 0 }; return max(0, Int((completedAt ?? Date()).timeIntervalSince(start))) }
    public init(recipe: Recipe) {
        self.recipe = recipe
        self.checks = recipe.items.filter { $0.ingredient.category == .fresh }.map { PreparationCheck(id: $0.id) }
    }
    public func remaining(at date: Date = Date()) -> Int {
        if let pausedSeconds { return max(0, Int(ceil(pausedSeconds))) }
        guard let end = targetEndAt else { return currentStep?.durationSeconds ?? 0 }
        return max(0, Int(ceil(end.timeIntervalSince(date))))
    }
}

public struct AuxiliaryTimer: Codable, Identifiable {
    public var id = UUID()
    public var label: String
    public var targetEndAt: Date?
    public var pausedSeconds: Double?
    public var announced = false
    public func remaining(at now: Date = Date()) -> Int {
        if let pausedSeconds { return max(0, Int(ceil(pausedSeconds))) }
        return max(0, Int(ceil((targetEndAt ?? now).timeIntervalSince(now))))
    }
}
public struct RecipeRevision: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var at = Date()
    public var before: [RecipeItem]
    public var after: [RecipeItem]
    public var oldWaterML: Int
    public var newWaterML: Int
    public var note: String
}
