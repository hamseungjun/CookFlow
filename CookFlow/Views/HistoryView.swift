import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 22) {
            SectionTitle(title: "조리 기록", subtitle: "내 주방에서 완성한 한 냄비의 기록")
            if store.data.history.isEmpty { EmptyState(icon: "books.vertical", title: "첫 번째 레시피를 기다려요", detail: "조리를 완료하고 평가를 저장하면 여기에 기록됩니다.") }
            ForEach(store.data.history) { session in NavigationLink { HistoryDetail(session: session) } label: { Card { VStack(alignment: .leading, spacing: 14) {
                HStack { Tag(text: "\(session.recipe.preferences.servings)인분", icon: "person.2"); Spacer(); Text(session.completedAt ?? session.recipe.createdAt, format: .dateTime.month().day()).font(.caption).foregroundStyle(Palette.muted) }
                Text("우리 집 \(session.recipe.title)").font(.title2.bold()).foregroundStyle(Palette.ink)
                Text(session.recipe.items.filter { $0.ingredient.category == .fresh }.map { $0.ingredient.name }.joined(separator: " · ")).font(.subheadline).foregroundStyle(Palette.muted)
                HStack { Label("\(session.review.taste) / 5", systemImage: "star.fill"); Spacer(); Text(RecipeEngine.time(session.elapsedSeconds)); Image(systemName: "chevron.right") }.font(.caption).foregroundStyle(Palette.green)
            } } }.buttonStyle(.plain) }
        }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity) }.background(Palette.background).navigationTitle("조리 기록").navigationBarTitleDisplayMode(.inline)
    }
}
struct HistoryDetail: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var session: CookingSession
    @State private var replace = false
    @State private var remove = false
    @State private var showLog = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 22) {
            SectionTitle(title: "우리 집 \(session.recipe.title)", subtitle: (session.completedAt ?? session.recipe.createdAt).formatted(date: .abbreviated, time: .shortened))
            Card { VStack(alignment: .leading, spacing: 12) {
                Text("\(session.recipe.kitchen.name) · \(session.recipe.preferences.servings)인분").font(.headline)
                Text("실제 시간 \(RecipeEngine.time(session.elapsedSeconds)) · 만족도 \(session.review.taste)/5")
                Text("간: \(["싱거움", "알맞음", "짬"][max(0, min(2, session.review.salt))]) · 맵기: \(["순함", "알맞음", "매움"][max(0, min(2, session.review.spice))])").foregroundStyle(Palette.muted)
                if !session.review.notes.isEmpty { Text(session.review.notes).padding(.top, 8) }
            } }
            Card { VStack(alignment: .leading, spacing: 12) { Text("저장된 분량").font(.headline); if session.recipe.waterML > 0 { Text("물 \(session.recipe.waterMeasure)") }; ForEach(session.recipe.items) { item in HStack { Text(item.ingredient.name); Spacer(); Text(item.householdQuantity) } } } }
            Card { VStack(alignment: .leading, spacing: 12) {
                Text("이번 설정과 비교").font(.headline)
                Text("저장: \(session.recipe.kitchen.heatingName), 중불 \(session.recipe.kitchen.setting(.medium)), \(session.recipe.preferences.servings)인분").font(.subheadline)
                if let kitchen = store.kitchen { Text("현재: \(kitchen.heatingType.rawValue), 중불 \(kitchen.setting(.medium)), \(store.data.preferences.servings)인분").font(.subheadline).foregroundStyle(Palette.muted) }
                Text("다시 조리하면 저장 당시 주방·화력·분량을 그대로 사용합니다. 변경하려면 오늘의 요리에서 새 레시피를 생성해주세요.").font(.caption).foregroundStyle(Palette.muted)
            } }
            if !session.recipe.revisions.isEmpty {
                Card { VStack(alignment: .leading, spacing: 14) {
                    Text("조리 중 변경 이력").font(.headline)
                    ForEach(session.recipe.revisions) { revision in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(revision.at, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(Palette.muted)
                            if revision.oldWaterML != revision.newWaterML { Text("물 \(revision.oldWaterML)ml → \(revision.newWaterML)ml").font(.subheadline) }
                            ForEach(revision.before) { before in
                                let after = revision.after.first { $0.id == before.id }
                                if after?.amount != before.amount { Text("\(before.ingredient.name): \(before.quantityText) → \(after?.quantityText ?? "제외")").font(.subheadline) }
                            }
                        }
                    }
                } }
            }
            DisclosureGroup("조리 이벤트 기록", isExpanded: $showLog) { ForEach(session.events) { event in HStack(alignment: .top) { Text(event.at, style: .time).font(.caption.monospaced()); Text("\(event.label) \(event.detail)").font(.caption) }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4) } }
            PrimaryButton(title: "이 레시피로 다시 조리", icon: "arrow.clockwise") { if let active = store.data.session, [.cooking, .paused, .preparing].contains(active.state) { replace = true } else { replay() } }
            Button("이 기록 삭제", role: .destructive) { remove = true }.frame(maxWidth: .infinity).padding()
        }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity) }.background(Palette.background).navigationTitle("조리 기록").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("진행 중인 조리를 종료하고 시작할까요? 가열기는 직접 꺼주세요.", isPresented: $replace, titleVisibility: .visible) { Button("종료하고 다시 조리", role: .destructive) { store.perform(.cancel); replay() } }
        .confirmationDialog("이 조리 기록을 삭제할까요?", isPresented: $remove, titleVisibility: .visible) { Button("삭제", role: .destructive) { store.data.history.removeAll { $0.id == session.id }; if store.data.session?.id == session.id && store.data.session?.state == .saved { store.data.session = nil }; dismiss() } }
    }
    private func replay() { var recipe = session.recipe; recipe.id = UUID(); recipe.createdAt = Date(); store.confirm(recipe); dismiss() }
}
