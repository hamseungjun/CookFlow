import Foundation

public enum RecipeMenu: String, Codable, CaseIterable, Identifiable {
    case doenjang, kimchi, sundubu
    case miyeok, beefRadish, eggSoup, beanSproutSoup, bulgogi, jeyuk, dakbokkeum, braisedTofu, potatoStew, kimchiBraisedPork, soyChicken, spicySquid, eggRoll, steamedEgg, stirPotato, stirZucchini, stirMushroom, spinachNamul, beanSproutNamul, cucumberMuchim, tofuPan, anchovyStir, kimchiFriedRice, eggFriedRice, soyEggRice, bibimbap, tunaRice
    case beefSundubu, spamStew, porkBulgogi, beefBeanSprout, sausageVegetables, omeletRice, porkDonburi, mapoTofu, tofuEgg, soyPork, jeyukRice, aglioOlio, vongole, tomatoPasta, burrataPasta, raguPasta, rosePasta, beefAglio
    public var id: String { rawValue }
    public var title: String {
        if let template = HomeMealCatalog.templates[rawValue] { return template.title }
        switch self { case .doenjang: return "된장찌개"; case .kimchi: return "김치찌개"; case .sundubu: return "순두부찌개"; default: return HomeMealCatalog.templates[rawValue]?.title ?? rawValue }
    }
    public var detail: String {
        if let template = HomeMealCatalog.templates[rawValue] { return template.detail }
        switch self { case .doenjang: return "구수한 된장과 채소로 만드는 익숙한 한 끼"; case .kimchi: return "김치를 충분히 끓여 만드는 깊은 국물"; case .sundubu: return "부드러운 순두부를 마지막에 넣어 살짝 끓여요"
        default: return HomeMealCatalog.templates[rawValue]?.detail ?? "" }
    }
    public var defaultIngredients: Set<String> {
        if let template = HomeMealCatalog.templates[rawValue] { return Set(template.amounts.keys) }
        switch self {
        case .doenjang: return ["tofu", "zucchini", "onion", "scallion", "doenjang"]
        case .kimchi: return ["kimchi", "pork", "tofu", "scallion", "garlic", "chiliPowder"]
        case .sundubu: return ["softTofu", "zucchini", "onion", "scallion", "garlic", "chiliPowder", "soupSoy"]
        default: return []
        }
    }
    public var essentialIngredients: Set<String> {
        if isOriginalStew { switch self { case .doenjang: return []; case .kimchi: return ["kimchi"]; case .sundubu: return ["softTofu"]; default: break } }
        if let template = HomeMealCatalog.templates[rawValue] { return Set(template.amounts.keys) }
        switch self { case .doenjang: return []; case .kimchi: return ["kimchi"]; case .sundubu: return ["softTofu"]; default: return [] }
    }
    public static func matching(_ query: String) -> RecipeMenu? {
        let normalized = query.replacingOccurrences(of: " ", with: "")
        guard !normalized.isEmpty else { return nil }
        if normalized == "김치찌개" { return .kimchi }
        return allCases.sorted { $0.title.count > $1.title.count }.first { normalized.contains($0.title.replacingOccurrences(of: " ", with: "")) }
    }
    public var baselineStatus: String? { HomeMealCatalog.templates[rawValue]?.sourceStatus }
    public var usesFixedBatch: Bool { HomeMealCatalog.templates[rawValue]?.fixedBatch == true }
    public var isOriginalStew: Bool { [.doenjang, .kimchi, .sundubu].contains(self) }
    public var category: String { HomeMealCatalog.templates[rawValue]?.category ?? "국·찌개" }
    public var referenceURL: URL { var c = URLComponents(string: "https://www.10000recipe.com/recipe/list.html")!; c.queryItems = [URLQueryItem(name: "q", value: title)]; return c.url! }
    public func allows(_ ingredient: Ingredient) -> Bool {
        if !isOriginalStew { return defaultIngredients.contains(ingredient.id) }
        if HomeMealCatalog.addedIngredientIDs.contains(ingredient.id) { return false }
        if self == .doenjang { return ingredient.id != "kimchi" }
        return ingredient.group != "paste" && ingredient.id != "ssamjang" && (self == .kimchi ? ingredient.id != "softTofu" : ingredient.id != "kimchi")
    }
}

public enum HouseholdMeasure {
    private static func fraction(_ value: Double) -> String {
        let quarters = max(1, Int((value * 4).rounded()))
        let whole = quarters / 4
        let suffix = ["", "¼", "½", "¾"][quarters % 4]
        return (whole == 0 ? "" : String(whole)) + suffix
    }
    public static func water(_ ml: Int) -> String { "약 \(fraction(Double(ml) / 200))컵 (\(ml)ml)" }
    public static func ingredient(_ item: RecipeItem) -> String {
        let ingredient = item.ingredient
        let raw = item.quantityText
        // Spoon measures are for seasonings only. Fresh ingredients keep familiar
        // piece/cup/gram measures so a tofu or vegetable amount never becomes spoons.
        if ingredient.category == .seasoning {
            if ingredient.unit == "ml" {
                let small = item.amount < 7.5
                let divisor = small ? 5.0 : 15.0
                let unit = small ? "작은술" : "큰술"
                return "약 \(fraction(item.amount / divisor))\(unit)"
            }
            if ingredient.unit == "g" {
                let gramsPerTablespoon: [String: Double] = [
                    "doenjang": 18, "tojang": 18, "ssamjang": 18, "gochujang": 18,
                    "salt": 15, "sugar": 12, "chiliPowder": 6, "pepper": 6,
                    "shrimpPaste": 15, "chickenStock": 12, "sesame": 9,
                    "mayonnaise": 15, "doubanjiang": 18, "starch": 10,
                    "butter": 14, "ketchup": 17, "tomatoPuree": 16
                ]
                if ingredient.id == "pepper", item.amount < 0.5 { return "한 꼬집 정도" }
                if let grams = gramsPerTablespoon[ingredient.id] {
                    let small = item.amount < grams
                    let divisor = small ? grams / 3 : grams
                    return "약 \(fraction(item.amount / divisor))\(small ? "작은술" : "큰술")"
                }
            }
        }
        if ingredient.unit != "g" && ingredient.unit != "ml" { return raw }
        if ingredient.unit == "ml" {
            if item.amount > 45 { return "약 \(fraction(item.amount / 200))컵 (\(raw))" }
            let small = item.amount < 15
            return "약 \(fraction(item.amount / (small ? 5 : 15)))\(small ? "작은술" : "큰술") (\(raw))"
        }
        let portions: [String: (Double, String)] = ["tofu": (300, "모"), "softTofu": (350, "봉"), "zucchini": (300, "개"), "onion": (200, "개"), "potato": (200, "개"), "scallion": (30, "대"), "chili": (10, "개"), "redChili": (10, "개"), "kimchi": (150, "컵"), "riceCooked": (200, "공기"), "cucumber": (200, "개"), "carrot": (150, "개")]
        if let (grams, unit) = portions[ingredient.id] { return "약 \(fraction(item.amount / grams))\(unit) (\(raw))" }
        return raw
    }
    public static func object(_ item: RecipeItem) -> String {
        let quantity = ingredient(item)
        let measure = quantity.components(separatedBy: " (").first ?? quantity
        let scalar = measure.unicodeScalars.last
        let particle: String
        if let scalar, (0xAC00...0xD7A3).contains(scalar.value) { particle = (scalar.value - 0xAC00) % 28 == 0 ? "를" : "을" }
        else { particle = "을" }
        return quantity + particle
    }
    public static let guide = "평평하게 담은 계량 큰술 15ml · 작은술 5ml · 컵 200ml 기준입니다. 일반 밥숟가락과 제품 크기는 달라질 수 있어요."
}

public enum GroceryLinks {
    public static func coupangSearch(_ ingredient: String) -> URL {
        var components = URLComponents(string: "https://www.coupang.com/np/search")!
        components.queryItems = [URLQueryItem(name: "q", value: "로켓프레시 " + ingredient)]
        return components.url!
    }
}

/// Ingredient changes are the only reason to replace a baseline recipe with an AI adaptation.
public struct RecipeCustomization {
    public let menu: RecipeMenu
    public let selected: Set<String>
    public init(menu: RecipeMenu, selected: Set<String>) { self.menu = menu; self.selected = selected }
    public var added: Set<String> { selected.subtracting(menu.defaultIngredients) }
    public var removed: Set<String> { menu.defaultIngredients.subtracting(selected) }
    public var requiresAI: Bool { !added.isEmpty || !removed.isEmpty }
}
