import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showKitchen = false
    @State private var showRecipes = false

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 700
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Cookflow").font(.system(size: 28, weight: .semibold, design: .serif)).tracking(-1)
                        Spacer()
                        Text("당신의 요리 도우미").font(.caption).foregroundStyle(Palette.muted)
                    }
                    Rectangle().fill(Palette.green.opacity(0.2)).frame(height: 1)
                    introduction.padding(.vertical, wide ? 30 : 8)
                    if let session = store.data.session, [.preparing, .cooking, .paused].contains(session.state) {
                        Button { store.selectedTab = 1 } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "play.circle.fill").font(.title)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("만들던 요리 이어하기").font(.headline)
                                    Text(session.state == .preparing ? "재료 준비를 확인해주세요" : "\(session.stepIndex + 1) / \(session.recipe.steps.count) 단계 · \(session.currentStep?.title ?? "")").font(.caption)
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                            }.padding(20).foregroundStyle(Palette.green).background(Palette.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                    if wide {
                        HStack(alignment: .top, spacing: 24) { kitchenEntry; recipeEntry }
                    } else {
                        VStack(spacing: 18) { kitchenEntry; recipeEntry }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "waveform").foregroundStyle(Palette.green)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("손은 요리에, 안내는 목소리로.").font(.subheadline.weight(.semibold))
                            Text("준비부터 불 조절까지 한 번에 한 가지씩 함께해요.").font(.caption).foregroundStyle(Palette.muted)
                        }
                    }.padding(.vertical, 6)
                }.padding(wide ? 40 : 24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }.background(Palette.background)
        }.foregroundStyle(Palette.ink).toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showKitchen) { NavigationStack { KitchenEditor(profile: KitchenProfile()) } }
        .sheet(isPresented: $showRecipes) { NavigationStack { RecipeLibraryView() } }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MADE FOR YOUR KITCHEN").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Palette.green)
            Text("나를 아는,\n요리의 시작.").font(.system(size: 34, weight: .semibold, design: .serif)).tracking(-1.5).fixedSize(horizontal: false, vertical: true)
            Text("내 주방의 화력, 냉장고 속 재료, 좋아하는 맛.\n나에게 맞는 방법으로 차근차근 요리해요.").font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                personalDetail("cooktop", "우리 집 화력")
                Spacer(minLength: 8)
                personalDetail("carrot", "보유 재료")
                Spacer(minLength: 8)
                personalDetail("heart", "나의 취향")
            }.padding(.top, 8)
        }
    }

    private func personalDetail(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 13, weight: .light)).foregroundStyle(Palette.green)
            Text(title).font(.caption).foregroundStyle(Palette.muted)
        }
    }

    private var kitchenEntry: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("내 주방").font(.title2.bold()); Spacer(); Image(systemName: "cooktop").font(.title2) }
            Text(store.kitchen.map { "\($0.name) · \($0.heatingType.rawValue)" } ?? "등록하면 우리 집 화력으로 더 편하게 안내해요.").font(.subheadline).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            Button {
                if store.kitchen == nil { showKitchen = true } else { store.selectedTab = 3 }
            } label: {
                HStack { Text(store.kitchen == nil ? "첫 주방 등록하기" : "등록한 주방 보기"); Spacer(); Image(systemName: "arrow.right") }.font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Palette.green, in: RoundedRectangle(cornerRadius: 12))
    }

    private var recipeEntry: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("오늘의 레시피").font(.title2.bold()); Spacer(); Image(systemName: "book.closed").font(.title2).foregroundStyle(Palette.orange) }
            Text("AI가 만들어주거나, 좋아하는 영상에서 가져와요.").font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
            NavigationLink { AIRecipeView() } label: { Label("AI 맞춤 레시피 만들기", systemImage: "sparkles").font(.subheadline.bold()).foregroundStyle(Palette.green) }
            NavigationLink { VideoRecipeView() } label: { Label("유튜브 레시피 가져오기", systemImage: "play.rectangle").font(.subheadline.bold()).foregroundStyle(Palette.green) }
            Button { showRecipes = true } label: {
                HStack { Text("기본 레시피 둘러보기"); Spacer(); Image(systemName: "arrow.right") }.font(.subheadline.bold()).foregroundStyle(Palette.green).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Divider()
            Button { store.selectedTab = 2 } label: {
                HStack { Text("나의 레시피북"); Spacer(); Text("\(store.savedRecipes.count)개 저장").foregroundStyle(Palette.muted); Image(systemName: "chevron.right") }.font(.caption).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct RecipeLibraryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showKitchen = false
    @State private var selectedMenu: RecipeMenu?
    @State private var search = ""
    @State private var category = "전체"
    private let categories = ["전체", "국·찌개", "메인요리", "반찬", "밥·한그릇", "파스타"]
    private var filtered: [RecipeMenu] {
        RecipeMenu.allCases.filter { menu in
            (category == "전체" || category == menu.category) && (search.isEmpty || menu.title.localizedCaseInsensitiveContains(search) || menu.defaultIngredients.compactMap { Catalog.item($0)?.name }.contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NavigationLink { AIRecipeView() } label: { Label("AI로 내 입맛에 맞춰 만들기", systemImage: "sparkles").font(.headline) }
                NavigationLink { VideoRecipeView() } label: { Label("유튜브 레시피 가져오기", systemImage: "play.rectangle").font(.headline) }
                Text("아래는 바로 시작할 수 있는 기본 집밥 레시피예요.").font(.caption).foregroundStyle(Palette.muted)

                SectionTitle(title: "매일 먹는 우리 집 한 끼", subtitle: "집밥·파스타 \(RecipeMenu.allCases.count)종 · 재료부터 완성까지 함께해요.")
                if search.isEmpty && category == "전체" {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("첫 요리는, 된장찌개").font(.title2.bold())
                        Text("재료를 준비하고, 손질을 확인하고, 목소리를 따라 한 냄비를 완성해요.").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                        Button { selectedMenu = .doenjang } label: { HStack { Text("된장찌개로 시작하기").font(.headline); Spacer(); Image(systemName: "arrow.right") }.padding(16).foregroundStyle(Palette.green).background(.white, in: RoundedRectangle(cornerRadius: 10)) }
                    }.padding(24).foregroundStyle(.white).background(Palette.green, in: RoundedRectangle(cornerRadius: 16))
                }
                HStack { Image(systemName: "magnifyingglass"); TextField("메뉴나 재료로 찾기", text: $search).autocorrectionDisabled(); if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("검색 지우기") } }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 12))
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(categories, id: \.self) { value in Button { category = value } label: { Text(value).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 10).foregroundStyle(category == value ? .white : Palette.green).background(category == value ? Palette.green : Palette.green.opacity(0.08), in: Capsule()) }.buttonStyle(.plain) } } }
                HStack { Text(category == "전체" ? "집밥 레시피" : category).font(.headline); Spacer(); Text("\(filtered.count)개 메뉴").font(.caption).foregroundStyle(Palette.muted) }
                if filtered.isEmpty { ContentUnavailableView("찾는 메뉴가 없어요", systemImage: "magnifyingglass", description: Text("다른 메뉴나 재료 이름으로 검색해주세요.")) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(filtered) { menu in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text(menu.category).font(.caption.weight(.semibold)).foregroundStyle(Palette.green); Spacer(); Image(systemName: menu.category == "밥·한그릇" ? "fork.knife" : "flame").foregroundStyle(Palette.orange) }
                            Text(menu.title).font(.title3.bold())
                            Text(menu.detail).font(.subheadline).foregroundStyle(Palette.muted).frame(minHeight: 40, alignment: .top)
                            Button { selectedMenu = menu } label: { HStack { Text("재료 고르고 시작"); Spacer(); Image(systemName: "arrow.right") }.font(.subheadline.weight(.semibold)).padding(14).foregroundStyle(.white).background(Palette.green, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle()) }
                            NavigationLink { GroceryView(menu: menu) } label: { Label("재료 장보기", systemImage: "cart").font(.caption) }
                            Link("만개의레시피에서 다른 조리법 보기", destination: menu.referenceURL).font(.caption2).foregroundStyle(Palette.muted)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                NavigationLink { VideoRecipeView() } label: {
                    Card { VStack(alignment: .leading, spacing: 12) { Label("유튜브에서 레시피 가져오기", systemImage: "play.rectangle").font(.headline); Text("찾는 메뉴가 없다면 좋아하는 영상의 요리도 가져올 수 있어요.").font(.subheadline).foregroundStyle(Palette.muted); Text("영상 링크 넣기 →").foregroundStyle(Palette.green) } }
                }.buttonStyle(.plain)
                if store.kitchen == nil { Button("선택 · 내 주방 화력 등록") { showKitchen = true }.font(.caption) }
                NavigationLink { HistoryView() } label: { Label("저장한 조리 기록 보기", systemImage: "books.vertical").font(.headline) }
                Text("집밥을 위한 기본 조리 안내예요. 다양한 조리법은 만개의레시피에서도 찾아볼 수 있어요.").font(.caption2).foregroundStyle(Palette.muted)
            }.padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.background(Palette.background).navigationTitle("집밥 레시피").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        .sheet(isPresented: $showKitchen) { NavigationStack { KitchenEditor(profile: KitchenProfile()) } }
        .sheet(item: $selectedMenu) { menu in NavigationStack { IngredientsView(menu: menu) } }
        .onChange(of: store.data.session?.id) { _, _ in dismiss() }
    }
}

struct CookingArtwork: View {
    var body: some View {
        Image(systemName: "checkmark.seal").font(.system(size: 72, weight: .ultraLight))
            .foregroundStyle(Palette.green).frame(maxWidth: .infinity).accessibilityLabel("요리 완료")
    }
}
