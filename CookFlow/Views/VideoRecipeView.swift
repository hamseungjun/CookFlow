import SwiftUI

struct VideoRecipeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var link = ""
    @State private var busy = false
    @State private var draft: VideoRecipeDraft?
    @State private var source = ""
    @State private var review = false
    @State private var feedback = ""
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            SectionTitle(title: "영상 속 요리, 우리 주방에서", subtitle: "유튜브 링크를 넣으면 재료와 조리 순서를 가져와요.")
            Card { VStack(alignment: .leading, spacing: 16) {
                Label("유튜브 레시피 가져오기", systemImage: "play.rectangle").font(.headline)
                TextField("https://youtu.be/…", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).disabled(busy)
                Text("공개 요리 영상의 링크를 AI 서버로 보내 분석합니다. 비공개 영상은 지원하지 않아요.").font(.caption).foregroundStyle(Palette.muted)
                PrimaryButton(title: busy ? "영상 분석·빈 정보 보완 중…" : "레시피 가져오기", icon: "sparkles") { Task { await extract() } }.disabled(busy || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if busy { ProgressView(); Text("영상 길이에 따라 시간이 걸릴 수 있어요.").font(.caption).foregroundStyle(Palette.muted) }
                if !feedback.isEmpty { Text(feedback).font(.subheadline).foregroundStyle(Palette.orange) }
            } }
            Label("재료 손질 안내", systemImage: "viewfinder")
            Label("내 주방에 맞춘 불 조절", systemImage: "flame")
            Label("단계별 타이머와 음성 안내", systemImage: "timer")
            Label("부족한 재료 장보기", systemImage: "cart")
            Text("가져온 레시피의 계량과 순서를 확인한 뒤 조리를 시작해주세요. 빠진 불 세기·손질 방법·시간은 AI가 보완하고 따로 표시해요.").font(.caption).foregroundStyle(Palette.muted)
        }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity) }.background(Palette.background).navigationTitle("영상 레시피").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $review) { if let draft { VideoRecipeDraftEditor(draft: draft, source: source) } }
    }
    @MainActor private func extract() async {
        busy = true; feedback = ""; defer { busy = false }
        do {
            let source = try YouTubeLink.canonical(link).absoluteString
            self.source = source
            let draft = try await AIConnection.video(source: source, endpoint: AIConnection.configuredEndpoint(store.data.videoRecipeEndpoint, fallback: AIConnection.localVideo), requestedServings: 1)
            self.draft = draft
            review = true
        } catch { feedback = error.localizedDescription }
    }
}

struct VideoRecipeDraftEditor: View {
    @EnvironmentObject private var store: AppStore
    @State var draft: VideoRecipeDraft
    let source: String
    @State private var recipe: Recipe?
    @State private var review = false
    @State private var feedback = ""
    @State private var edited = false
    var body: some View {
        Form {
            Section { TextField("요리 이름", text: $draft.title)
                Stepper(draft.servings == 0 ? "인분을 지정해주세요" : "\(draft.servings)인분", value: $draft.servings, in: 0...12)
                Text("기본은 1인분이며, 인분을 바꾸면 재료와 물 분량도 함께 조정돼요.").font(.caption).foregroundStyle(.secondary)
                if let url = URL(string: source) { Link("원본 영상과 비교하기", destination: url) }
            } header: { Text("가져온 레시피 확인") }
            if let completions = draft.ai_completions, !completions.isEmpty {
                Section {
                    Text("영상에 없는 정보를 AI가 요리에 맞춰 보완했어요. 값은 수정할 수 있어요.").font(.subheadline)
                    DisclosureGroup("AI가 보완한 \(completions.count)개 항목") {
                        ForEach(completions, id: \.field) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(item.label) · \(item.value)").font(.subheadline.bold())
                                Text(item.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Label("AI 보완", systemImage: "sparkles") }
            }
            if !draft.uncertainties.isEmpty { Section("영상 분석 참고") { ForEach(draft.uncertainties, id: \.self) { Text($0).font(.subheadline) } } }
            Section { ForEach(draft.ingredients.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(draft.ingredients[index].name).font(.headline); if draft.isAIFilled("ingredients.\(index).cut") || draft.isAIFilled("ingredients.\(index).amount") { Label("AI 보완", systemImage: "sparkles").font(.caption).foregroundStyle(Palette.green) } }
                    HStack { TextField("수량", value: $draft.ingredients[index].amount, format: .number).keyboardType(.decimalPad).textFieldStyle(.roundedBorder); Text(draft.ingredients[index].unit) }
                    if draft.ingredients[index].amount <= 0 { Text("영상에 없는 분량입니다. 직접 확인해 입력해주세요.").font(.caption).foregroundStyle(Palette.orange) }
                    if !draft.ingredients[index].cut.isEmpty { Text(PreparationGuide.instruction(name: draft.ingredients[index].name, cut: draft.ingredients[index].cut)).font(.caption).foregroundStyle(.secondary) }
                }
            } } header: { Text("재료와 계량") } footer: { Text("큰술·작은술·컵은 영상 기준입니다. 계량을 수정했다면 단계 설명의 원본 수량보다 ‘이번 조리 계량’을 따르세요. 분량이 없는 재료는 값을 입력해야 실행할 수 있어요.") }
            Section("조리 단계") { ForEach(draft.steps.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("\(index + 1). \(draft.steps[index].title)").font(.headline); if draft.isAIFilled("steps.\(index).heat") || draft.isAIFilled("steps.\(index).seconds") { Label("AI 보완", systemImage: "sparkles").font(.caption).foregroundStyle(Palette.green) } }
                    Text(draft.steps[index].instruction).font(.subheadline)
                    Picker("화력", selection: Binding(get: { draft.steps[index].heat?.rawValue ?? "" }, set: { draft.steps[index].heat = HeatLevel(rawValue: $0) })) { Text("이전 화력 유지").tag(""); ForEach(HeatLevel.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) } }
                    HStack { Text("타이머 (초)"); TextField("0", value: $draft.steps[index].seconds, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    if draft.steps[index].seconds == 0 { Text("시간이 없는 단계는 직접 상태를 확인하고 완료합니다.").font(.caption).foregroundStyle(.secondary) }
                }
            } }
            Section { if !feedback.isEmpty { Text(feedback).foregroundStyle(Palette.orange) }
                PrimaryButton(title: "검토한 레시피로 조리 준비", icon: "arrow.right") {
                    do {
                        var result = try draft.recipe(source: source, kitchen: store.kitchen, preferences: store.data.preferences)
                        if edited { result.warnings.append("가져온 레시피의 계량·화력·시간 일부를 사용자가 수정했습니다.") }
                        recipe = result; review = true
                    } catch { feedback = error.localizedDescription }
                }
            }
        }.navigationTitle("영상 내용 확인").navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft.servings) { oldValue, newValue in
            if oldValue > 0, newValue > 0 {
                let ratio = Double(newValue) / Double(oldValue)
                for index in draft.ingredients.indices { draft.ingredients[index].amount *= ratio }
                draft.waterML = Int((Double(draft.waterML) * ratio).rounded())
            }
            edited = true
        }
        .onChange(of: draft.title) { _, _ in edited = true }
        .onChange(of: fingerprint) { _, _ in edited = true }
        .navigationDestination(isPresented: $review) { if let recipe { RecipeReviewView(recipe: recipe) } }
    }
    private var fingerprint: String { (try? String(data: JSONEncoder().encode(draft), encoding: .utf8)) ?? "" }
}
