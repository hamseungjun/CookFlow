import SwiftUI

struct IngredientsView: View {
    var menu: RecipeMenu = .doenjang
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @AppStorage("aiCustomIngredients") private var customIngredientsData: Data = Data()
    @State private var category: IngredientCategory = .fresh
    @State private var search = ""
    @State private var recipe: Recipe?
    @State private var review = false
    @State private var replaceSession = false
    @State private var initialized = false
    @State private var selected = Set<String>()
    @State private var quantities: [String: Double] = [:]
    @State private var preferences = Preferences()
    @State private var addIngredients = false
    @State private var busy = false
    @State private var feedback = ""
    @State private var showAmounts = false
    @State private var customIngredients: [Ingredient] = []
    @State private var customIngredientName = ""
    private var customization: RecipeCustomization { RecipeCustomization(menu: menu, selected: selected) }
    private var allItems: [Ingredient] { Catalog.items + customIngredients }
    private var currentItems: [Ingredient] { allItems.filter { menu.defaultIngredients.contains($0.id) || selected.contains($0.id) } }
    private var filtered: [Ingredient] { currentItems }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("집에 있는 재료로 요리해요").font(.headline)
                Text("추천 재료는 미리 골라뒀어요. 집에 없는 건 눌러서 빼주세요.").font(.caption).foregroundStyle(Palette.muted)
                selectionControls
                HStack {
                    Text("\(filtered.count)개 재료").font(.caption).foregroundStyle(Palette.muted)
                    Spacer()
                    Text("\(selected.count)개 집에 있음").font(.caption.bold()).foregroundStyle(Palette.green)
                }
                ingredientSection(.fresh)
                ingredientSection(.seasoning)
                if filtered.isEmpty { Text("검색한 재료가 없어요.").font(.subheadline).foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.vertical, 20) }
                if customization.requiresAI {
                    Text("재료를 바꿨어요. AI가 투입 순서와 조리 시간을 맞춰줄게요.").font(.caption).foregroundStyle(Palette.green)
                    Button("기본 재료로 되돌리기") { selected = menu.defaultIngredients; quantities = [:] }.font(.caption)
                }
                optionalSettings
                if !feedback.isEmpty { Text(feedback).font(.caption).foregroundStyle(Palette.orange) }
                if busy { ProgressView("변경한 재료로 조리 순서를 정리하고 있어요.") }
            }.padding(16).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.disabled(busy).background(Palette.background).navigationTitle("재료 선택").navigationBarTitleDisplayMode(.inline)
         .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: busy ? "AI가 조리법을 맞추는 중…" : customization.requiresAI ? "AI로 바꾼 레시피 보기" : "기본 레시피로 바로 시작", icon: customization.requiresAI ? "sparkles" : "play.fill") { Task { await proceed() } }
                .disabled(busy || selected.isEmpty).padding(.horizontal, 16).padding(.vertical, 10).background(Palette.background)
        }
        .onAppear { if !initialized { selected = menu.defaultIngredients; preferences = store.data.preferences; preferences.servings = 1; customIngredients = (try? JSONDecoder().decode([Ingredient].self, from: customIngredientsData)) ?? []; initialized = true } }
        .sheet(isPresented: $addIngredients) { NavigationStack { ingredientPicker } }
        .confirmationDialog("진행 중인 조리를 종료하고 시작할까요? 가열기는 직접 꺼주세요.", isPresented: $replaceSession) {
            Button("기존 조리 종료 후 시작", role: .destructive) { if let recipe { store.perform(.cancel); store.confirm(recipe); dismiss() } }
            Button("돌아가기", role: .cancel) {}
        }
        .onChange(of: store.data.session?.id) { _, _ in dismiss() }
        .navigationDestination(isPresented: $review) { if let recipe { RecipeReviewView(recipe: recipe) } }
    }
    private func ingredientSection(_ category: IngredientCategory) -> some View {
        let items = currentItems.filter { $0.category == category }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(category.rawValue, systemImage: category == .fresh ? "carrot" : "takeoutbag.and.cup.and.straw")
                    .font(.subheadline.bold()).foregroundStyle(Palette.ink)
                Spacer()
                Text("\(items.filter { selected.contains($0.id) }.count)/\(items.count)개 집에 있음")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 10)], spacing: 10) {
                ForEach(items) { item in
                    IngredientTile(item: item, selectedIDs: $selected, quantities: $quantities, baseline: menu.defaultIngredients.contains(item.id), showAmounts: showAmounts)
                }
            }
            Button {
                self.category = category
                search = ""
                addIngredients = true
            } label: {
                Label(category == .fresh ? "식재료 추가" : "조미료·양념 추가", systemImage: "plus")
                    .font(.caption.bold())
            }.buttonStyle(.bordered)
        }
    }
    @ViewBuilder private var selectionControls: some View {
        Stepper("\(preferences.servings)인분", value: $preferences.servings, in: 1...4).font(.subheadline.bold()).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
    private var optionalSettings: some View {
                DisclosureGroup("취향·보유량 설정 (선택)") { VStack(alignment: .leading, spacing: 16) {
                    Toggle("재료별 보유량 입력", isOn: $showAmounts)
                    if !menu.isOriginalStew { Text("이 메뉴의 기본 재료를 준비한 뒤 인분·맵기·간·보유량으로 조절해요.").font(.caption).foregroundStyle(Palette.muted) }
                    preferencePicker("맵기", selection: $preferences.spice, labels: ["순하게", "보통", "매콤", "아주 매콤"])
                    preferencePicker("짠맛", selection: $preferences.salt, labels: ["싱겁게", "보통", "진하게", "아주 진하게"])
                    if menu.isOriginalStew { Picker("국물 농도", selection: $preferences.richness) { ForEach(["맑음", "보통", "진함"], id: \.self) { Text($0) } }.pickerStyle(.segmented) }
                    Toggle("육류 제외", isOn: $preferences.excludeMeat)
                    Toggle("해산물 및 생선 양념 제외", isOn: $preferences.excludeSeafood)
                    if menu.isOriginalStew { Toggle("기름에 향채를 볶는 방식", isOn: $preferences.saute)
                    Text("볶는 방식에는 식용유와 양파 또는 마늘이 필요합니다. 기본은 기름 없이 끓이는 방식입니다.").font(.caption).foregroundStyle(Palette.muted) }
                } }
    }
    private var ingredientPicker: some View {
        ScrollView {
            VStack(spacing: 12) {
                Picker("재료 종류", selection: $category) { ForEach(IngredientCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                TextField("재료 검색", text: $search).textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    TextField("사전에 없는 재료 이름", text: $customIngredientName).textFieldStyle(.roundedBorder)
                    Button("이름으로 추가") { addCustomIngredient() }
                        .buttonStyle(.borderedProminent).tint(Palette.green)
                        .disabled(customIngredientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 10)], spacing: 10) {
                    ForEach(allItems.filter { $0.category == category && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }) { item in
                        IngredientTile(item: item, selectedIDs: $selected, quantities: $quantities, baseline: menu.defaultIngredients.contains(item.id), showAmounts: false)
                    }
                }
            }.padding(16)
        }.background(Palette.background).navigationTitle("추가할 재료").toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { search = ""; addIngredients = false } } }
    }
    private func addCustomIngredient() {
        let name = customIngredientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let normalized = name.replacingOccurrences(of: " ", with: "").lowercased()
        if let existing = allItems.first(where: { $0.name.replacingOccurrences(of: " ", with: "").lowercased() == normalized }) {
            selected.insert(existing.id)
        } else {
            let item = Ingredient("custom-" + UUID().uuidString, name, category, "g", 0)
            customIngredients.append(item)
            selected.insert(item.id)
            if let encoded = try? JSONEncoder().encode(customIngredients) { customIngredientsData = encoded }
        }
        customIngredientName = ""
        search = ""
        addIngredients = false
    }
    @MainActor private func proceed() async {
        busy = true; feedback = ""; defer { busy = false }
        let selection = selected
        let preferences = self.preferences
        do {
            if !customization.requiresAI {
                let base = try RecipeEngine.generate(kitchen: store.kitchen, selected: menu.defaultIngredients, quantities: quantities, preferences: preferences, menu: menu)
                recipe = base
                if let session = store.data.session, [.preparing, .cooking, .paused].contains(session.state) { replaceSession = true }
                else { store.confirm(base); dismiss() }
            } else {
                let items = allItems.filter { selection.contains($0.id) }
                let list = items.map { item in item.name + (quantities[item.id].map { " (보유량 최대 " + KitchenProfile.number($0) + item.unit + ")" } ?? "") }.joined(separator: ", ")
                let baseline = try? RecipeEngine.generate(kitchen: store.kitchen, selected: menu.defaultIngredients, quantities: [:], preferences: preferences, menu: menu)
                let draft = try await AIConnection.generate(dish: menu.title, ingredients: list, preferences: preferences, endpoint: AIConnection.configuredEndpoint(store.data.generationEndpoint, fallback: AIConnection.localGeneration), baseline: baseline)
                let allowedNames = Set(items.map(\.name))
                let actualNames = Set(draft.ingredients.filter { $0.name != "물" }.map(\.name))
                guard actualNames.isSubset(of: allowedNames) else { throw RecipeError.invalid("집에 없는 재료가 AI 결과에 포함됐어요. 다시 만들기를 눌러주세요.") }
                var generated = try draft.generatedRecipe(kitchen: store.kitchen, preferences: preferences)
                generated.menu = menu
                recipe = generated
                review = true
            }
        } catch { feedback = error.localizedDescription }
    }
    private func preferencePicker(_ title: String, selection: Binding<Int>, labels: [String]) -> some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.subheadline); Picker(title, selection: selection) { ForEach(labels.indices, id: \.self) { Text(labels[$0]).tag($0) } }.pickerStyle(.segmented) } }
}
struct IngredientTile: View {
    var item: Ingredient
    @Binding var selectedIDs: Set<String>
    @Binding var quantities: [String: Double]
    var baseline = false
    var showAmounts = false
    var required = false
    var selectionLabel: String? = nil
    private var selected: Bool { selectedIDs.contains(item.id) }
    private func toggle() {
        if selected { selectedIDs.remove(item.id) }
        else { selectedIDs.insert(item.id) }
    }
    private var quantity: Binding<String> {
        Binding(get: { quantities[item.id].map(KitchenProfile.number) ?? "" }, set: { text in
            if text.isEmpty { quantities.removeValue(forKey: item.id) }
            else if let value = Double(text) { quantities[item.id] = value }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(item.name).font(.subheadline.bold()).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle").font(.body).foregroundStyle(selected ? Palette.green : Palette.muted.opacity(0.6))
                    }
                    Text(selectionLabel ?? (baseline ? "추천 재료" : "추가 재료")).font(.caption2.bold()).foregroundStyle(baseline ? Palette.orange : Palette.muted).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        if required { Text("필수").foregroundStyle(Palette.orange) }

                    }.font(.caption2)
                    Spacer(minLength: 0)
                    if !selected || !showAmounts { Text(selected ? "집에 있어요" : "눌러서 선택").font(.caption2).foregroundStyle(Palette.muted) }
                }.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            .accessibilityLabel("\(item.name), \(selected ? "집에 있음" : "집에 없음")\(required ? ", 필수 재료" : "")")
            .accessibilityAddTraits(selected ? .isSelected : [])
            if selected && showAmounts {
                HStack(spacing: 4) {
                    TextField("보유량", text: quantity).keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(.caption).accessibilityLabel("\(item.name) 보유량, \(item.unit)")
                    Text(item.unit).font(.caption2).foregroundStyle(Palette.muted)
                }.padding(.horizontal, 8).frame(height: 28).background(Palette.background, in: RoundedRectangle(cornerRadius: 7))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1, contentMode: .fit)
        .background(selected ? Palette.green.opacity(0.06) : baseline ? Palette.orange.opacity(0.06) : .white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Palette.green.opacity(0.55) : baseline ? Palette.orange.opacity(0.35) : Palette.green.opacity(0.08), lineWidth: selected ? 1.5 : 1))
    }
}
struct RecipeReviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var recipe: Recipe
    private var flow: Recipe { CookingFlow.prepare(recipe, kitchen: store.kitchen) }
    @State private var replace = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 22) {
            SectionTitle(title: "오늘의 \(recipe.title)", subtitle: "\(recipe.preferences.servings)인분 · 약 \(max(1, recipe.estimatedSeconds / 60))분 · \(flow.steps.count)개 요리 단계")
            Card { VStack(alignment: .leading, spacing: 12) { Label(flow.kitchen.name, systemImage: "cooktop").font(.headline); Text("\(flow.kitchen.heatingName) · \(flow.kitchen.burner)").font(.subheadline).foregroundStyle(Palette.muted) } }
            Card { VStack(alignment: .leading, spacing: 15) {
                Text("계량과 손질").font(.headline)
                if recipe.waterML > 0 && !recipe.items.contains(where: { $0.ingredient.name == "물" }) { HStack { Text("물"); Spacer(); Text(recipe.waterMeasure).monospacedDigit() } }
                ForEach(recipe.items) { item in VStack(alignment: .leading, spacing: 4) { HStack { Text(item.ingredient.name); Spacer(); Text(item.householdQuantity).fontWeight(.semibold).monospacedDigit() }; if !item.ingredient.cut.isEmpty { Text(item.preparationInstruction).font(.caption).foregroundStyle(Palette.muted) } } }
            } }
            if !recipe.warnings.isEmpty {
                DisclosureGroup("참고 사항") {
                    ForEach(recipe.warnings.map { $0.contains("승준 레시피북") ? "기본 레시피입니다." : $0 }, id: \.self) { Text($0).font(.caption).foregroundStyle(Palette.muted) }
                }.font(.subheadline)
            }
            NavigationLink { GroceryView(menu: recipe.menu ?? .doenjang, recipe: recipe) } label: { Label("이 레시피 재료 장보기", systemImage: "cart") }.font(.headline)
            if let source = recipe.sourceVideoURL, let url = URL(string: source) { Link("원본 유튜브 영상 확인", destination: url) }
            if recipe.recipeOrigin == .youtube {
            Button { store.saveRecipe(recipe) } label: { Label(store.savedRecipes.contains { $0.id == recipe.id } ? "레시피북에 저장됨" : "레시피북에 저장", systemImage: "bookmark") }.buttonStyle(.bordered).frame(maxWidth: .infinity)
            }
            Text("요리 흐름대로 함께해요").font(.title3.bold())
            ForEach(Array(flow.steps.enumerated()), id: \.element.id) { index, step in Card { HStack(alignment: .top, spacing: 14) { Text(String(format: "%02d", index + 1)).font(.caption.monospaced().bold()).foregroundStyle(Palette.green).padding(9).background(Palette.green.opacity(0.1), in: Circle()); VStack(alignment: .leading, spacing: 7) { Text(step.title).font(.headline); ForEach(Array(CookingNarration.actions(for: step, recipe: flow).enumerated()), id: \.offset) { _, action in HStack(alignment: .top, spacing: 7) { Text("•"); Text(action).frame(maxWidth: .infinity, alignment: .leading) }.font(.subheadline).foregroundStyle(Palette.muted) }; if step.durationSeconds > 0 { Tag(text: RecipeEngine.time(step.durationSeconds), icon: "timer") } } } } }
            PrimaryButton(title: "레시피 확정 · 재료 준비", icon: "checkmark") {
                if let session = store.data.session, [.preparing, .cooking, .paused].contains(session.state) { replace = true } else { begin() }
            }
        }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity) }.background(Palette.background).navigationTitle("레시피 검토").navigationBarTitleDisplayMode(.inline)
        .onAppear { store.warmRecipeVoice(recipe) }
        .confirmationDialog("진행 중인 조리를 종료하고 새로 시작할까요? 가열기는 직접 꺼주세요.", isPresented: $replace, titleVisibility: .visible) { Button("기존 조리 종료 후 시작", role: .destructive) { store.perform(.cancel); begin() }; Button("돌아가기", role: .cancel) {} }
    }
    private func begin() { store.confirm(recipe); dismiss() }
}
