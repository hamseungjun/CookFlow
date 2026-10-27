import SwiftUI

struct RemainingRecipeEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var session: CookingSession
    @State private var amounts: [String: Double] = [:]
    @State private var excluded: Set<String> = []
    @State private var water = 0
    private var editableItems: [RecipeItem] {
        let locked = Set(session.recipe.steps.prefix(session.stepIndex).filter { $0.actionType == .add }.flatMap { $0.requiredItems.map(\.id) })
        let future = Set(session.recipe.steps.dropFirst(session.stepIndex).filter { $0.actionType == .add }.flatMap { $0.requiredItems.map(\.id) }).subtracting(locked)
        return session.recipe.items.filter { future.contains($0.id) }
    }
    private var waterEditable: Bool { session.recipe.waterML > 0 && !session.recipe.steps.prefix(session.stepIndex).contains { $0.title == "물 계량해 붓기" } }
    var body: some View {
        Form {
            Section { Text("아직 넣지 않은 재료의 분량을 줄이거나 식재료를 제외할 수 있습니다. 완료한 동작과 익히는 시간은 유지합니다. 재료를 늘리려면 새 레시피로 시작해주세요.").font(.subheadline) }
            if waterEditable { Section("물") { Stepper("\(water)ml", value: $water, in: Int(Double(session.recipe.waterML) * 0.8)...session.recipe.waterML, step: 5) } }
            Section("아직 넣지 않은 재료") {
                ForEach(editableItems) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.ingredient.name).font(.headline)
                        HStack { Text("분량"); Spacer(); TextField(item.quantityText, value: Binding(get: { amounts[item.id] ?? item.amount }, set: { amounts[item.id] = $0 }), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text(item.ingredient.unit) }
                        Text("기존 \(item.quantityText) 이하로 입력해주세요.").font(.caption).foregroundStyle(.secondary)
                        if item.ingredient.category == .fresh { Toggle("이번 조리에서 제외", isOn: Binding(get: { excluded.contains(item.id) }, set: { if $0 { excluded.insert(item.id) } else { excluded.remove(item.id) } })) }
                    }.padding(.vertical, 7)
                }
                if editableItems.isEmpty { Text("수정할 수 있는 재료 투입이 없습니다.").foregroundStyle(.secondary) }
            }
            Section { PrimaryButton(title: "남은 단계에 적용", icon: "checkmark") { if store.reviseRemaining(amounts: amounts, remove: excluded, water: waterEditable ? water : nil) { dismiss() } } }
        }.navigationTitle("남은 재료 수정").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        .onAppear { water = session.recipe.waterML }
    }
}
