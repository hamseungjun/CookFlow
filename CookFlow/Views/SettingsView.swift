import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: KitchenProfile?
    @State private var deletingKitchen: KitchenProfile?
    @State private var serverAddress = AIConnection.pairedBase
    @State private var aiChecking = false
    @State private var aiStatus = "서비스별 연결 상태를 확인해주세요."
    @State private var serviceStatuses: [AIServiceStatus] = []
    @State private var showDeleteKitchen = false
    var body: some View {
        List {
            Section("AI 연결") {
                Text(aiStatus).font(.subheadline)
                Button(aiChecking ? "연결 확인 중" : "AI 서비스 상태 확인") { Task { await refreshAIStatus() } }.disabled(aiChecking)
                ForEach(serviceStatuses) { service in
                    HStack(spacing: 10) {
                        Image(systemName: service.configured == true ? "checkmark.circle.fill" : service.configured == false ? "exclamationmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(service.configured == true ? Palette.green : service.configured == false ? Palette.orange : Palette.muted)
                        Text(service.title).font(.subheadline)
                        Spacer()
                        Text(service.configured == true ? "키 설정됨" : service.configured == false ? "키 필요" : "확인 전").font(.caption).foregroundStyle(Palette.muted)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("서로 다른 Wi-Fi·LTE에서도 사용할 수 있어요. 무료 Mac 서버 방식은 노트북을 켜고 인터넷에 연결해두세요.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("서버 주소 변경") {
                    TextField("https://서버주소", text: $serverAddress).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("주소 저장하고 연결 확인") {
                        guard let url = URL(string: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { aiStatus = "HTTPS 서버 주소만 입력해주세요."; return }
                        let old = UserDefaults.standard.string(forKey: "cookflowServerBaseOverride")
                        UserDefaults.standard.set(url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forKey: "cookflowServerBaseOverride")
                        aiChecking = true
                        Task {
                            defer { aiChecking = false }
                            do {
                                _ = try await AIConnection.checkConnection()
                                serviceStatuses = try await AIConnection.serviceStatuses()
                                aiStatus = "서버 응답 확인됨 · 아래는 기능별 API 키 설정 상태입니다."
                            }
                            catch { UserDefaults.standard.set(old, forKey: "cookflowServerBaseOverride"); aiStatus = "새 주소에 연결하지 못했어요. 기존 연결을 유지해요." }
                        }
                    }.disabled(aiChecking)
                    Text("무료 외부 연결 주소가 바뀌면 여기서 갱신할 수 있어요.").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section { ForEach(store.data.kitchens) { kitchen in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(kitchen.name).font(.headline); Spacer(); if kitchen.id == store.kitchen?.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green) } }
                    Text("\(kitchen.heatingType.rawValue) · \(kitchen.burner)").font(.caption).foregroundStyle(.secondary)
                    HStack { Button("선택") { store.selectKitchen(kitchen.id) }; Spacer(); Button("수정") { editing = kitchen } }
                }.padding(.vertical, 6).swipeActions { Button("삭제", role: .destructive) { deletingKitchen = kitchen; showDeleteKitchen = true } }
            }; Button { editing = KitchenProfile() } label: { Label("새 주방 등록", systemImage: "plus.circle") } } header: { Text("주방과 화구") } footer: { Text("선택한 주방의 숫자·다이얼 위치가 현재 조리 안내에도 반영돼요. 레시피 분량과 타이머는 그대로 유지해요.") }
            Section("음성과 알림") {
                Picker("음성 제어", selection: $store.handsFreeEnabled) {
                    Text("음성 제어").tag(true)
                    Text("끄기").tag(false)
                }.pickerStyle(.segmented)
                Text("끄면 마이크 입력만 중지돼요. 화면 조작과 음성 안내는 계속 사용할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                Toggle("한국어 음성 안내", isOn: $store.data.voiceEnabled)
                Button("타이머 알림 권한 요청") { Task { await store.requestNotifications() } }
                Text(store.notificationStatus).font(.caption).foregroundStyle(.secondary)
            }
            Section("음성 안내") {
                Button("목소리 들어보기") { store.say("양파와 애호박을 넣고, 우리 집 화력에 맞춰 천천히 끓여볼게요.") }
                Text("안내가 끝나면 편하게 말해주세요.").font(.caption).foregroundStyle(.secondary)

            }
            Section {
                DisclosureGroup("고급 연결 설정") {
                    Text("음성 안내").font(.caption)
                    TextField("https://example.com/api/speech", text: Binding(get: { store.data.speechEndpoint ?? AIConnection.localSpeech }, set: { store.data.speechEndpoint = $0 })).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("레시피 생성").font(.caption)
                    TextField("https://example.com/api/recipe/generate", text: Binding(get: { store.data.generationEndpoint ?? AIConnection.localGeneration }, set: { store.data.generationEndpoint = $0 })).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("음성 판정").font(.caption)
                    TextField("https://example.com/api/voice/decide", text: Binding(get: { store.data.decisionEndpoint ?? AIConnection.localDecision }, set: { store.data.decisionEndpoint = $0 })).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("유튜브 가져오기").font(.caption)
                    TextField("https://example.com/api/video-recipe", text: Binding(get: { store.data.videoRecipeEndpoint ?? AIConnection.localVideo }, set: { store.data.videoRecipeEndpoint = $0 })).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            Section("CookFlow") { Text("한식 집밥 \(RecipeMenu.allCases.count)종 · 유튜브 레시피"); Text("우리 집 불에 맞춰 함께 요리해요.").font(.caption).foregroundStyle(.secondary) }
        }.scrollContentBackground(.hidden).background(Palette.background).navigationTitle("내 주방")
        .task { await refreshAIStatus() }
        .sheet(item: $editing) { profile in NavigationStack { KitchenEditor(profile: profile) } }
        .confirmationDialog("이 주방 프로필을 삭제할까요? 저장된 레시피의 주방 기록은 유지됩니다.", isPresented: $showDeleteKitchen, titleVisibility: .visible) { Button("주방 삭제", role: .destructive) { if let kitchen = deletingKitchen { store.data.kitchens.removeAll { $0.id == kitchen.id }; if store.data.selectedKitchenID == kitchen.id { store.selectKitchen(store.data.kitchens.first?.id) } else { store.bindKitchenGuidance() } } } }
    }
    @MainActor private func refreshAIStatus() async {
        aiChecking = true
        defer { aiChecking = false }
        do {
            serviceStatuses = try await AIConnection.serviceStatuses()
            aiStatus = "서버 응답 확인됨 · 아래는 기능별 API 키 설정 상태입니다."
        } catch {
            serviceStatuses = []
            aiStatus = error.localizedDescription
        }
    }

}
