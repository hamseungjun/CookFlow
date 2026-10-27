import SwiftUI

struct GroceryView: View {
    @State private var menu: RecipeMenu
    @State private var servings: Int
    @State private var wanted: Set<String>
    var recipe: Recipe?
    init(menu: RecipeMenu = .doenjang, recipe: Recipe? = nil) {
        self.recipe = recipe
        _menu = State(initialValue: menu)
        _servings = State(initialValue: recipe?.preferences.servings ?? 1)
        _wanted = State(initialValue: recipe.map { Set($0.items.map(\.id)) } ?? menu.defaultIngredients)
    }
    private var items: [RecipeItem] {
        if let recipe { return recipe.items }
        var preferences = Preferences(); preferences.servings = servings
        return (try? RecipeEngine.generate(selected: menu.defaultIngredients, quantities: [:], preferences: preferences, menu: menu))?.items ?? []
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionTitle(title: "필요한 것만, 장보기", subtitle: "재료를 골라 쿠팡에서 찾아보고 주문해요.")
                if recipe == nil {
                    Picker("장볼 메뉴", selection: $menu) { ForEach(RecipeMenu.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                    Stepper("\(servings)인분", value: $servings, in: 1...4)
                } else { Text("\(recipe?.title ?? menu.title) · \(servings)인분").font(.headline) }
                Text("이미 있는 재료는 체크를 해제하세요. 분량은 요리에 사용할 양이며, 판매 상품의 포장 수량은 쿠팡에서 선택해요.").font(.subheadline).foregroundStyle(Palette.muted)
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: Binding(get: { wanted.contains(item.id) }, set: { if $0 { wanted.insert(item.id) } else { wanted.remove(item.id) } })) {
                            VStack(alignment: .leading, spacing: 5) { Text(item.ingredient.name).font(.headline); Text(item.householdQuantity).font(.caption).foregroundStyle(Palette.muted) }
                        }.toggleStyle(.switch)
                        if wanted.contains(item.id) {
                            Link(destination: GroceryLinks.coupangSearch(item.ingredient.name)) {
                                HStack { Text("쿠팡에서 찾기"); Spacer(); Image(systemName: "arrow.up.right") }.font(.subheadline.bold()).foregroundStyle(Palette.green)
                            }.accessibilityLabel("\(item.ingredient.name) 쿠팡에서 찾기")
                        }
                    }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
                if wanted.isEmpty { Text("모든 재료가 준비됐어요. 레시피에서 요리를 시작해보세요.").font(.subheadline).foregroundStyle(Palette.green) }
                Text("로켓프레시 검색어로 쿠팡을 엽니다. 상품의 로켓프레시 배송 여부·가격·배송 지역은 쿠팡에서 확인해주세요. 상품 선택, 장바구니와 결제는 쿠팡에서 진행합니다.").font(.caption).foregroundStyle(Palette.muted).lineSpacing(4)
            }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.background(Palette.background).navigationTitle("장보기").navigationBarTitleDisplayMode(.inline)
        .onChange(of: menu) { _, value in wanted = value.defaultIngredients }
    }
}
