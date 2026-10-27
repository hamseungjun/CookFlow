import SwiftUI
import UIKit

struct SessionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var cancel = false
    @State private var revise = false
    var body: some View {
        Group {
            if let session = store.data.session {
                switch session.state {
                case .preparing, .confirmed, .ready: PreparationView(session: session)
                case .cooking, .paused: CookingView(session: session)
                case .completed: CompletionView(session: session)
                case .saved: EmptyState(icon: "checkmark.seal", title: "조리 기록을 저장했어요", detail: "오늘의 기록을 확인하거나 새로운 조리를 시작해보세요.")
                case .cancelled: EmptyState(icon: "pause.circle", title: "조리를 종료했어요", detail: "가열기 전원이 꺼졌는지 직접 확인해주세요. 오늘의 요리에서 다시 시작할 수 있어요.")
                case .draft: EmptyState(icon: "leaf", title: "레시피를 확정해주세요", detail: "재료를 선택하고 레시피를 확인해주세요.")
                }
            } else { EmptyState(icon: "flame", title: "함께 요리할 준비가 됐어요", detail: "오늘의 요리에서 주방과 재료를 선택해주세요.") }
        }.sheet(isPresented: $revise) { if let session = store.data.session { NavigationStack { RemainingRecipeEditor(session: session) } } }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.background).navigationTitle("조리 안내").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let session = store.data.session, session.state == .cooking && session.phase == .ready && session.recipe.recipeOrigin == .preset && session.recipe.flowVersion == nil { ToolbarItem(placement: .topBarLeading) { Button("분량 수정") { revise = true } } }; if let session = store.data.session, [.preparing, .cooking, .paused].contains(session.state) { ToolbarItem(placement: .topBarTrailing) { Button("종료", role: .destructive) { cancel = true } } } }
        .confirmationDialog("조리를 종료할까요? 앱은 가열기를 끄지 않습니다. 전원을 직접 꺼주세요.", isPresented: $cancel, titleVisibility: .visible) { Button("전원 확인 후 조리 종료", role: .destructive) { store.perform(.cancel) }; Button("돌아가기", role: .cancel) {} }
    }
}
struct CookingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var voiceSettings = false
    var session: CookingSession
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(session.recipe.title).font(.subheadline.bold())
                        Spacer()
                        Text("\(session.stepIndex + 1)/\(session.recipe.steps.count) · \(session.state == .paused ? "일시정지" : "조리 중")").font(.caption).foregroundStyle(Palette.muted)
                    }
                    currentStep(at: context.date)
                    VoiceControls(compact: true)
                    entireRecipe
                }.padding(.horizontal, 16).padding(.vertical, 10).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(Palette.background)
            .onChange(of: context.date) { _, _ in store.tick() }
        }
        .safeAreaInset(edge: .bottom) { stageAction.padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: 760).frame(maxWidth: .infinity).background(Palette.background) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { voiceSettings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("음성 설정") } }
        .sheet(isPresented: $voiceSettings) { NavigationStack { ScrollView { VoiceControls().padding() }.navigationTitle("음성 설정").toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { voiceSettings = false } } } } }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; store.cookingScreen(true) }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; store.cookingScreen(false); store.voice.stopSpeaking() }
    }
    private func currentStep(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let step = session.currentStep {
                HStack(alignment: .firstTextBaseline) {
                    Text(displayTitle(step)).font(.title3.bold()).foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    if step.durationSeconds > 0 {
                        Text(String(format: "%02d:%02d", session.remaining(at: now) / 60, session.remaining(at: now) % 60)).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Palette.green).accessibilityLabel("남은 시간 \(session.remaining(at: now))초")
                    }
                }
                HeatGuide(kitchen: session.recipe.kitchen, heat: step.heatTo, compact: true)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(CookingNarration.actions(for: step, recipe: session.recipe).enumerated()), id: \.offset) { _, action in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").foregroundStyle(Palette.green)
                            Text(action).frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if step.durationSeconds > 0 && session.phase != .ready {
                    HStack(spacing: 12) {
                        Button("+30초") { store.perform(.addTime(30)) }
                        Button("+1분") { store.perform(.addTime(60)) }
                        Spacer()
                        if session.state == .cooking { Button { store.perform(.pause) } label: { Label("잠깐 멈춤", systemImage: "pause.fill") } }
                    }.font(.caption.bold()).buttonStyle(.bordered)
                }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
    private var entireRecipe: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("전체 요리 순서").font(.caption.bold()).foregroundStyle(Palette.muted).padding(.bottom, 6)
            ForEach(Array(session.recipe.steps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(index == session.stepIndex ? Palette.green : Palette.green.opacity(0.07))
                        if index < session.stepIndex { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Palette.green) }
                        else { Text("\(index + 1)").font(.caption.bold()).foregroundStyle(index == session.stepIndex ? .white : Palette.muted) }
                    }.frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayTitle(step)).font(.subheadline.weight(index == session.stepIndex ? .bold : .medium)).foregroundStyle(index == session.stepIndex ? Palette.green : Palette.ink)
                        Text(stageDetail(step)).font(.caption2).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 4)
                    Text(step.durationSeconds > 0 ? RecipeEngine.time(step.durationSeconds).replacingOccurrences(of: " 0초", with: "") : "완료").font(.caption).foregroundStyle(Palette.muted)
                }.padding(.horizontal, 8).padding(.vertical, 6).background(index == session.stepIndex ? Palette.green.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(index + 1)단계, \(step.title), \(stageDetail(step)), \(index == session.stepIndex ? "현재 단계" : index < session.stepIndex ? "완료한 단계" : "예정 단계")")
            }
        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
    private func displayTitle(_ step: CookingStep) -> String {
        if step.title == "두부·마무리 재료 넣고 끓이기" {
            let names = step.requiredItems.map { $0.ingredient.name }.joined(separator: "·")
            return names.isEmpty ? "마무리 끓이기" : names + " 넣고 끓이기"
        }
        return step.title
    }
    private func stageDetail(_ step: CookingStep) -> String {
        let names = step.requiredItems.map { $0.ingredient.name }.joined(separator: "·")
        let kitchen = session.recipe.kitchen
        let setting: String
        if step.heatTo == .off { setting = "불 끄기" }
        else if kitchen.usesGeneralGuidance == true { setting = step.heatTo.label }
        else if kitchen.controlType.isNumeric { setting = step.heatTo.label + " · " + kitchen.setting(step.heatTo) }
        else if let dial = kitchen.dialConfiguration { setting = step.heatTo.label + " · " + DialConfiguration.clockLabel(dial.angle(for: step.heatTo)) }
        else { setting = kitchen.setting(step.heatTo) }
        return (names.isEmpty ? "" : names + " · ") + setting
    }
    @ViewBuilder private var stageAction: some View {
        if let step = session.currentStep {
            VStack(spacing: 5) {
                if session.state == .paused { PrimaryButton(title: "이어서 요리하기", icon: "play.fill") { store.perform(.resume) } }
                else if step.durationSeconds > 0 && session.phase == .ready {
                    PrimaryButton(title: step.timerStartEvent == "화력 설정 확인 후 시작" ? "불 맞췄어요 · 타이머 시작" : "재료 넣었어요 · 타이머 시작", icon: "timer") { store.perform(.startTimer, key: "start-\(step.id)") }
                } else if step.durationSeconds > 0 && session.phase == .active {
                    Text("시간이 끝나면 다음 안내로 넘어가요").font(.caption).foregroundStyle(Palette.muted)
                    HStack {
                        Button("아직 안 넣었어요") { store.perform(.resetTimer); store.speakCurrent() }
                        Spacer()
                        Button("이미 익었어요 · 다음") { store.perform(.finishEarly, key: "early-\(step.id)") }
                    }.font(.subheadline.bold()).buttonStyle(.bordered)
                } else {
                    PrimaryButton(title: step.actionType == .finish ? "불 껐어요 · 요리 완료" : "다음 요리 단계", icon: step.actionType == .finish ? "checkmark" : "arrow.right") { store.perform(.done, key: "done-\(step.id)") }
                }
                if session.stepIndex > 0 { Button { store.perform(.previous) } label: { Label("이전 단계", systemImage: "arrow.uturn.backward") }.font(.caption).padding(.vertical, 4) }
            }
        }
    }
}
struct VoiceControls: View {
    @EnvironmentObject private var store: AppStore
    var compact = false
    var body: some View { VoiceControlContent(voice: store.voice, compact: compact).environmentObject(store) }
}
struct VoiceControlContent: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var voice: VoiceService
    var compact = false
    var body: some View {
        if compact { compactBody } else { expandedBody }
    }
    private var timerRunning: Bool { store.data.session?.state == .cooking && store.data.session?.phase == .active }
    private var micLabel: String {
        if timerRunning { return "타이머 중 · 마이크 꺼짐" }
        if voice.transcribing { return "확인 중" }
        if store.decidingVoice { return "확인 중" }
        if !store.handsFreeEnabled { return "음성 제어 꺼짐"}
        return voice.speaking ? "안내 후 자동 듣기" : voice.listening ? "듣고 있어요" : "자동 듣기 켜짐"
    }
    private var voiceErrorMessage: String {
        let error = voice.error ?? ""
        return error.contains("권한") ? "설정에서 마이크 권한을 켜주세요." : error.contains("녹음") ? "마이크를 시작하지 못했어요. 음성 설정을 확인해주세요." : "음성 연결을 확인해주세요."
    }
    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(micLabel, systemImage: voice.listening ? "waveform" : timerRunning ? "mic.slash.fill" : "mic.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(voice.error == nil ? Palette.green : Palette.orange)
                Spacer()
                Button { store.speakCurrent() } label: { Label("다시 듣기", systemImage: "speaker.wave.2") }
            }.buttonStyle(.bordered).controlSize(.regular)
            if voice.listening {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.green.opacity(0.12))
                        Capsule().fill(Palette.green).frame(width: max(4, proxy.size.width * voice.microphoneLevel))
                    }
                }.frame(height: 5).accessibilityLabel("마이크 입력 레벨")
            }
            Picker("음성 제어", selection: $store.handsFreeEnabled) {
                Text("음성 제어").tag(true)
                Text("끄기").tag(false)
            }.pickerStyle(.segmented)
            Text(timerRunning ? "타이머 중에는 마이크가 잠시 꺼져요. 화면 버튼으로 시간을 조절하세요." : "음성 제어를 끄면 마이크 입력만 꺼지고, 화면 조작과 음성 안내는 계속 사용할 수 있어요.").font(.caption2).foregroundStyle(Palette.muted)
            Text(voice.voiceStatus).font(.caption).foregroundStyle(Palette.muted).lineLimit(2)
            if !voice.transcript.isEmpty { Text("인식 문장: “" + voice.transcript + "”").font(.caption).foregroundStyle(Palette.ink).lineLimit(2) }
            if let feedback = store.voiceFeedback {
                Label(feedback, systemImage: "info.circle.fill").font(.caption).foregroundStyle(Palette.orange).fixedSize(horizontal: false, vertical: true)
            }
            if voice.error != nil { Label(voiceErrorMessage, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Palette.orange) }
        }
        .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
    private var expandedBody: some View {
        Card { VStack(alignment: .leading, spacing: 14) {
            HStack { Label("음성 도우미", systemImage: "waveform").font(.headline); Spacer(); Toggle("음성 안내", isOn: $store.data.voiceEnabled).labelsHidden().accessibilityLabel("한국어 음성 안내") }
            HStack { Button { store.speakCurrent() } label: { Label("다시 듣기", systemImage: "speaker.wave.2") }.buttonStyle(.bordered); Spacer(); Text(micLabel).font(.caption.bold()).foregroundStyle(voice.listening ? Palette.green : Palette.muted) }
            Picker("음성 제어", selection: $store.handsFreeEnabled) {
                Text("음성 제어").tag(true)
                Text("끄기").tag(false)
            }.pickerStyle(.segmented)
            Text(timerRunning ? "타이머 중에는 마이크가 잠시 꺼져요. 다음 단계에서 음성 제어가 다시 시작됩니다. 시간 추가와 일시정지는 화면 버튼으로도 할 수 있어요." : "안내가 끝나면 말로 조작할 수 있어요. 음성 제어를 끄면 마이크 입력만 꺼지고 화면 조작은 계속 사용할 수 있어요.").font(.caption).foregroundStyle(Palette.muted)
            DisclosureGroup("음성 연결 상세") {
                Text(voice.voiceStatus).font(.caption).foregroundStyle(Palette.muted)
                if !voice.transcript.isEmpty { Text("“\(voice.transcript)”").font(.caption) }
                if let error = voice.error { Text(error).font(.caption).foregroundStyle(Palette.orange) }
            }.font(.caption)
            if let feedback = store.voiceFeedback { Text(feedback).font(.caption).foregroundStyle(Palette.muted) }
            if voice.error != nil { Text(voiceErrorMessage).font(.caption).foregroundStyle(Palette.orange) }
            Text("완료 보고 · 잠시 멈춤 · 시간 추가 · 남은 시간 질문\n타이머 중에는 마이크가 꺼져요.").font(.caption).foregroundStyle(Palette.muted).lineSpacing(4)
            Button("잠금 화면 알림 켜기") { Task { await store.requestNotifications() } }.font(.caption.bold())
            Text(store.notificationStatus).font(.caption2).foregroundStyle(Palette.muted)
        } }
    }
}
struct CompletionView: View {
    @EnvironmentObject private var store: AppStore
    var session: CookingSession
    @State private var review = Review()
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 16) {
                if LiveCamera.generatedDemo,
                   let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
                   let image = UIImage(contentsOfFile: root.appendingPathComponent("DemoInputs/finished.jpg").path) {
                    GeometryReader { proxy in Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: 230).clipped().clipShape(RoundedRectangle(cornerRadius: 20)) }.frame(height: 230)
                    Text("가상 시연 · AI가 생성한 완성 이미지").font(.caption).foregroundStyle(Palette.orange)
                } else { CookingArtwork().frame(height: 230) }
                Text("따뜻한 한 냄비, 완성!").font(.largeTitle.bold()); Text("오늘도 차근차근 잘 만들었어요.").foregroundStyle(Palette.muted); Tag(text: "실제 조리 \(RecipeEngine.time(session.elapsedSeconds))", icon: "clock") }.frame(maxWidth: .infinity).padding(.vertical, 25)
            Card { VStack(alignment: .leading, spacing: 18) {
                Text("오늘의 맛은 어땠나요?").font(.title3.bold())
                Stepper("만족도 \(review.taste) / 5", value: $review.taste, in: 1...5)
                Picker("간", selection: $review.salt) { Text("싱거움").tag(0); Text("알맞음").tag(1); Text("짬").tag(2) }.pickerStyle(.segmented)
                Picker("맵기", selection: $review.spice) { Text("순함").tag(0); Text("알맞음").tag(1); Text("매움").tag(2) }.pickerStyle(.segmented)
                TextField("다음에 기억하고 싶은 점", text: $review.notes, axis: .vertical).lineLimit(3...6).padding(12).background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
            } }
            Text("가열기 전원이 꺼졌는지 마지막으로 확인해주세요.").font(.subheadline).foregroundStyle(Palette.orange)
            PrimaryButton(title: "조리 기록 저장", icon: "bookmark.fill") { store.saveReview(review) }
        }.padding(24).frame(maxWidth: 740).frame(maxWidth: .infinity) }.background(Palette.background)
    }
}
