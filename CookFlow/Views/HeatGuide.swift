import SwiftUI

struct HeatGuide: View {
    let kitchen: KitchenProfile
    let heat: HeatLevel
    var compact = false
    var body: some View {
        if compact { compactGuide } else { expandedGuide }
    }
    private var compactGuide: some View {
        HStack(spacing: 12) {
            if kitchen.usesGeneralGuidance != true, !kitchen.controlType.isNumeric, let dial = kitchen.dialConfiguration {
                ZStack {
                    Circle().stroke(Palette.green.opacity(0.18), lineWidth: 5)
                    Capsule().fill(Palette.green).frame(width: 4, height: 23).offset(y: -10).rotationEffect(.degrees(dial.angle(for: heat)))
                    Text("OFF").font(.system(size: 8, weight: .semibold)).offset(y: -29)
                }.frame(width: 58, height: 58).padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(heat == .off ? "OFF · 불 끄기" : "\(heat.label) · \(DialConfiguration.clockLabel(dial.angle(for: heat)))").font(.subheadline.bold())
                    Text(heat == .off ? kitchen.burner : "OFF부터 \(dial.clockwise ? "시계방향" : "반시계방향") · \(kitchen.burner)").font(.caption).foregroundStyle(Palette.muted)
                }
            } else {
                Image(systemName: "flame.fill").foregroundStyle(Palette.green)
                Text(kitchen.spokenSetting(heat)).font(.subheadline.bold())
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 12).padding(.vertical, 8).background(Palette.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
    private var expandedGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label(kitchen.usesGeneralGuidance == true ? "사용할 화력" : "\(kitchen.name) · \(kitchen.burner)", systemImage: "flame").font(.caption).foregroundStyle(Palette.muted); Spacer(); if kitchen.usesGeneralGuidance != true { Text(heat == .off ? "꺼짐" : heat.label).font(.headline).foregroundStyle(Palette.green) } }
            if kitchen.usesGeneralGuidance == true {
                Text(heat == .off ? "불을 꺼주세요" : heat.label).font(.largeTitle.bold())
            } else if kitchen.controlType.isNumeric {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(heat == .off ? "OFF" : KitchenProfile.number(kitchen.numericMap[heat.rawValue] ?? kitchen.minimum)).font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Palette.green)
                    if heat != .off { Text("단계").font(.title2.bold()); Spacer(); Text("\(KitchenProfile.number(kitchen.minimum))–\(KitchenProfile.number(kitchen.maximum))단계 중").font(.caption).foregroundStyle(Palette.muted) }
                }
            } else if let dial = kitchen.dialConfiguration {
                DialFace(configuration: dial, pointerAngle: dial.angle(for: heat), pointLabel: heat == .off ? "꺼짐" : heat.label).frame(height: 210)
                Text(heat == .off ? "다이얼을 OFF 위치로 돌려주세요" : "OFF에서 \(dial.clockwise ? "시계방향" : "반시계방향")으로 · \(DialConfiguration.clockLabel(dial.angle(for: heat))) 위치").font(.subheadline.bold()).frame(maxWidth: .infinity)
            } else {
                Label(kitchen.setting(heat), systemImage: "dial.low.fill").font(.title2.bold())
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}
