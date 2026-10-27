import SwiftUI

struct AIRecipeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var dish = ""
    @State private var selected = Set<String>()
    @State private var quantities: [String: Double] = [:]
    @State private var extras: [Ingredient] = []
    @AppStorage("aiCustomIngredients") private var customIngredientsData: Data = Data()
    @State private var search = ""
    @State private var adding = false
    @State private var extraName = ""
    @State private var extraCategory: IngredientCategory = .fresh
    @State private var preferences = Preferences()
    @State private var initialized = false
    @State private var busy = false
    @State private var feedback = ""
    @State private var recipe: Recipe?
    @State private var review = false
    private var allItems: [Ingredient] { Catalog.items + extras }
    private var chosen: [Ingredient] { allItems.filter { selected.contains($0.id) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("집에 있는 재료를 골라주세요").font(.title2.bold())
                Text("집에 있는 식재료와 양념을 고르면, AI가 요리에 어울리는 재료만 골라 한 끼를 만들어줘요.").font(.subheadline).foregroundStyle(Palette.muted)
                TextField("먹고 싶은 요리 · 비워두면 AI 추천", text: $dish).textFieldStyle(.roundedBorder)
                HStack { Text("\(chosen.count)개 선택").font(.subheadline.bold()); Spacer(); Button("선택 비우기") { selected.removeAll() }.font(.caption).disabled(selected.isEmpty) }
                TextField("식재료·조미료 검색", text: $search).textFieldStyle(.roundedBorder)
                ingredientSection(.fresh)
                ingredientSection(.seasoning)
                DisclosureGroup("인분·취향 (선택)") {
                    VStack(spacing: 16) {
                        Stepper("\(preferences.servings)인분", value: $preferences.servings, in: 1...4)
                        Picker("매운맛", selection: $preferences.spice) { Text("순하게").tag(0); Text("보통").tag(1); Text("맵게").tag(2) }.pickerStyle(.segmented)
                        Picker("간", selection: $preferences.salt) { Text("싱겁게").tag(0); Text("보통").tag(1); Text("진하게").tag(2) }.pickerStyle(.segmented)
                        Toggle("고기 제외", isOn: $preferences.excludeMeat)
                        Toggle("해산물 제외", isOn: $preferences.excludeSeafood)
                    }.padding(.top, 12)
                }
                if !feedback.isEmpty { Text(feedback).font(.caption).foregroundStyle(Palette.orange) }
                if busy { ProgressView("재료와 조리 순서를 맞추고 있어요. 서버 응답을 기다리는 동안 입력은 유지됩니다.") }
            }.padding(16).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(Palette.background).navigationTitle("AI 맞춤 레시피").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: busy ? "선택한 재료로 레시피 만드는 중…" : feedback.isEmpty ? "선택한 재료로 AI 레시피 만들기" : "입력 유지하고 다시 만들기", icon: "sparkles") { Task { await create() } }
                .disabled(busy || chosen.isEmpty).padding(16).background(Palette.background)
        }
        .onAppear { if !initialized { preferences = store.data.preferences; preferences.servings = 1; selected = store.data.selected; extras = (try? JSONDecoder().decode([Ingredient].self, from: customIngredientsData)) ?? []; initialized = true } }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    Section("목록에 없는 재료") {
                        TextField("예: 청경채, 트러플 소금", text: $extraName)
                        Picker("종류", selection: $extraCategory) { ForEach(IngredientCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    }
                }.navigationTitle("재료 직접 추가")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { adding = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("추가") { addExtra() }.disabled(extraName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
            }.presentationDetents([.medium])
        }
        .navigationDestination(isPresented: $review) { if let recipe { RecipeReviewView(recipe: recipe) } }
    }
    private func ingredientSection(_ category: IngredientCategory) -> some View {
        let items = allItems.filter { $0.category == category && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(category.rawValue, systemImage: category == .fresh ? "carrot" : "takeoutbag.and.cup.and.straw").font(.headline)
                Spacer()
                Text("\(chosen.filter { $0.category == category }.count)개 선택").font(.caption).foregroundStyle(Palette.green)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 10)], spacing: 10) {
                ForEach(items) { item in IngredientTile(item: item, selectedIDs: $selected, quantities: $quantities, showAmounts: false, selectionLabel: selected.contains(item.id) ? "집에 있어요" : "눌러서 선택") }
            }
            if items.isEmpty { Text("검색 결과가 없어요. 직접 추가할 수 있어요.").font(.caption).foregroundStyle(Palette.muted) }
            Button { extraCategory = category; extraName = search; adding = true } label: { Label(category == .fresh ? "목록에 없는 식재료 추가" : "목록에 없는 조미료 추가", systemImage: "plus") }.buttonStyle(.bordered).font(.caption.bold())
        }.disabled(busy)
    }
    private func addExtra() {
        let name = extraName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let normalized = name.replacingOccurrences(of: " ", with: "").lowercased()
        if let item = allItems.first(where: { $0.name.replacingOccurrences(of: " ", with: "").lowercased() == normalized }) {
            selected.insert(item.id)
        } else {
            let item = Ingredient("custom-" + UUID().uuidString, name, extraCategory, "g", 0)
            extras.append(item); selected.insert(item.id)
            if let encoded = try? JSONEncoder().encode(extras) { customIngredientsData = encoded }
        }
        search = ""; extraName = ""; adding = false
    }
    @MainActor private func create() async {
        busy = true; feedback = ""; defer { busy = false }
        let ingredients = chosen.map(\.name).joined(separator: ", ")
        do {
            let draft = try await AIConnection.generate(dish: dish, ingredients: ingredients, preferences: preferences, endpoint: AIConnection.configuredEndpoint(store.data.generationEndpoint, fallback: AIConnection.localGeneration))
            recipe = try draft.generatedRecipe(kitchen: store.kitchen, preferences: preferences); review = true
        } catch { feedback = error.localizedDescription }
    }
}

struct RecipeBookView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var favorites = false
    @State private var removal: UUID?
    private var recipes: [SavedRecipe] { store.savedRecipes.filter { (!favorites || $0.favorite) && (search.isEmpty || $0.recipe.title.localizedCaseInsensitiveContains(search) || $0.recipe.items.contains { $0.ingredient.name.localizedCaseInsensitiveContains(search) }) } }
    var body: some View {
        List {
            Section {
                NavigationLink { AIRecipeView() } label: { Label("AI로 새 레시피 만들기", systemImage: "sparkles") }
                NavigationLink { VideoRecipeView() } label: { Label("유튜브에서 가져오기", systemImage: "play.rectangle") }
                NavigationLink { RecipeLibraryView() } label: { Label("기본 레시피 둘러보기", systemImage: "fork.knife") }
            }
            Section {
                Toggle("즐겨찾기만 보기", isOn: $favorites)
            }
            Section("저장한 레시피 · \(recipes.count)") {
                if recipes.isEmpty { Text(search.isEmpty ? "유튜브에서 가져온 레시피만 모아둬요. 영상을 가져온 뒤 저장하거나 요리를 시작해주세요." : "조건에 맞는 레시피가 없어요.").foregroundStyle(.secondary) }
                ForEach(recipes) { saved in
                    VStack(alignment: .leading, spacing: 12) {
                    NavigationLink { RecipeReviewView(recipe: saved.recipe) } label: {
                        VStack(alignment: .leading, spacing: 7) { Text(saved.recipe.title).font(.headline); Text("\(saved.recipe.recipeOrigin.label) · \(saved.recipe.preferences.servings)인분 · 약 \(max(1, saved.recipe.estimatedSeconds / 60))분" ).font(.caption).foregroundStyle(.secondary); if saved.favorite { Label("즐겨찾기", systemImage: "star.fill").font(.caption).foregroundStyle(Palette.green) } }
                    }
                    Button(role: .destructive) { removal = saved.id } label: { Label("레시피 삭제", systemImage: "trash") }.font(.caption).buttonStyle(.borderless)
                    }
                    .swipeActions(edge: .leading) { Button { store.favorite(saved.id) } label: { Label("즐겨찾기", systemImage: "star") }.tint(Palette.green) }
                    .swipeActions { Button(role: .destructive) { removal = saved.id } label: { Label("삭제", systemImage: "trash") } }
                    .contextMenu { Button(saved.favorite ? "즐겨찾기 해제" : "즐겨찾기") { store.favorite(saved.id) }; Button("삭제", role: .destructive) { removal = saved.id } }
                }
            }
            Section { NavigationLink { HistoryView() } label: { Label("조리 기록 · \(store.data.history.count)회", systemImage: "clock.arrow.circlepath") } }
        }.scrollContentBackground(.hidden).background(Palette.background).navigationTitle("나의 레시피북").searchable(text: $search, prompt: "요리 이름 또는 재료")
        .confirmationDialog("레시피북에서 삭제할까요? 조리 기록은 보관됩니다.", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) { Button("레시피 삭제", role: .destructive) { if let removal { store.removeRecipe(removal) }; removal = nil }; Button("취소", role: .cancel) { removal = nil } }
    }
}
