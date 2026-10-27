import SwiftUI

struct PreparationView: View {
    @EnvironmentObject private var store: AppStore
    var session: CookingSession
    @State private var images: [String: Data] = [:]
    @State private var failures: [String: String] = [:]
    @State private var referenceItem: RecipeItem?
    @State private var editedInstructions: [String: String] = [:]
    @State private var editingInstruction: Set<String> = []
    @State private var imageRefreshToken = 0
    private var freshItems: [RecipeItem] { session.recipe.items.filter { $0.ingredient.category == .fresh } }
    private var imageSignature: String { freshItems.map { $0.id + $0.ingredient.cut }.joined(separator: "|") + String(imageRefreshToken) }
    private func instruction(for item: RecipeItem) -> String { editedInstructions[item.id] ?? item.preparationInstruction }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            SectionTitle(title: "재료를 이렇게 준비하세요", subtitle: "재료별 안내를 확인하고 필요한 손질을 마친 뒤 조리를 시작하세요.")
            Text("손질 참고 이미지는 이해를 돕는 예시예요.").font(.subheadline).foregroundStyle(Palette.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(freshItems) { item in
                    Card { VStack(alignment: .leading, spacing: 10) {
                        Text(item.ingredient.name).font(.headline)
                        Text(item.householdQuantity).font(.subheadline).fontWeight(.semibold)
                        if let bytes = images[item.id], let image = UIImage(data: bytes) {
                            Button { referenceItem = item } label: {
                                GeometryReader { proxy in
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: 125).clipped()
                                }.frame(height: 125).clipShape(RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityLabel("\(item.ingredient.name) 손질 예시 크게 보기")
                            Text("손질 모양 참고").font(.caption2).foregroundStyle(Palette.muted)
                        } else {
                            VStack(spacing: 8) {
                                if failures[item.id] == nil { ProgressView(); Text("손질 예시 준비 중").font(.caption) }
                                else { Text("이미지를 만들지 못했어요. 글 안내를 따라 준비하세요.").font(.caption); Button("예시 다시 만들기") { Task { await load(item, retry: true, method: instruction(for: item)) } }.font(.caption) }
                            }.frame(maxWidth: .infinity).frame(height: 125).background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
                        }
                        if editingInstruction.contains(item.id) {
                            TextField("손질 방법을 적어주세요", text: Binding(get: { instruction(for: item) }, set: { editedInstructions[item.id] = $0 }), axis: .vertical)
                                .lineLimit(2...5).textFieldStyle(.roundedBorder)
                            Button("수정 완료") { editingInstruction.remove(item.id); imageRefreshToken += 1 }.font(.caption.bold())
                        } else {
                            Text(instruction(for: item)).font(.subheadline).foregroundStyle(Palette.muted)
                            Button("손질 방법 수정") { editingInstruction.insert(item.id); if editedInstructions[item.id] == nil { editedInstructions[item.id] = item.preparationInstruction } }.font(.caption.bold())
                        }
                    } }
                }
            }
            if store.preparingCookingVoice { ProgressView(store.cookingVoiceProgress).font(.subheadline) }
            PrimaryButton(title: store.preparingCookingVoice ? "첫 안내 준비 중" : "재료 준비됐어요 · 조리 시작", icon: "play.fill") {
                store.perform(.approveAllPreparation); store.perform(.beginCooking)
            }.disabled(store.preparingCookingVoice)
        }.padding(16).frame(maxWidth: 800).frame(maxWidth: .infinity) }.background(Palette.background)
        .onChange(of: imageSignature) { _, _ in images.removeAll(); failures.removeAll() }
        .task(id: imageSignature) {
            store.warmVoice()
            await withTaskGroup(of: Void.self) { group in
                let items = freshItems
                var next = 0
                for _ in 0..<min(2, items.count) { let item = items[next]; next += 1; group.addTask { await load(item, method: instruction(for: item)) } }
                while await group.next() != nil {
                    if Task.isCancelled { group.cancelAll(); return }
                    if next < items.count { let item = items[next]; next += 1; group.addTask { await load(item, method: instruction(for: item)) } }
                }
            }
        }
        .sheet(item: $referenceItem) { item in
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    if let bytes = images[item.id], let image = UIImage(data: bytes) { Image(uiImage: image).resizable().scaledToFit() }
                    Text(instruction(for: item)).font(.title3.bold())
                    Text("손질 모양을 이해하기 위한 참고 예시예요. 크기와 모양이 완전히 같을 필요는 없어요.").font(.subheadline).foregroundStyle(Palette.muted)
                    Spacer()
                }.padding(20).navigationTitle(item.ingredient.name).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { referenceItem = nil } } }
            }
        }
    }
    @MainActor private func load(_ item: RecipeItem, retry: Bool = false, method: String? = nil) async {
        guard images[item.id] == nil else { return }
        failures[item.id] = nil
        do {
            let preparation = editedInstructions[item.id].map { PreparationGuide.shape($0) } ?? item.preparationShape
            let shape = preparation == .unclear ? "reference" : preparation.rawValue
            let bytes = try await AIConnection.preparationImage(ingredient: item.ingredient.name, shape: shape, method: method ?? instruction(for: item), retry: retry)
            guard !Task.isCancelled else { return }; images[item.id] = bytes
        } catch { if !Task.isCancelled { failures[item.id] = error.localizedDescription } }
    }
}
