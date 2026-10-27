import SwiftUI

struct NumericHeatEditor: View {
    @Binding var profile: KitchenProfile
    @State private var selectedHeat: HeatLevel = .medium
    private var step: Double { profile.halfSteps ? 0.5 : 1 }
    private var activeMinimum: Double { max(step, profile.minimum) }
    private var bound: Double { max(15, profile.maximum) }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("기기에 표시된 처음과 마지막 숫자를 맞춰주세요.").font(.subheadline).foregroundStyle(Palette.muted)
            HStack(spacing: 14) {
                limitTile("최소", profile.minimum)
                Image(systemName: "arrow.left.and.right").foregroundStyle(Palette.muted)
                limitTile("최대", profile.maximum)
            }
            RangeControl(minimum: Binding(get: { profile.minimum }, set: { HeatControlMath.rescale(profile: &profile, minimum: $0, maximum: profile.maximum) }), maximum: Binding(get: { profile.maximum }, set: { HeatControlMath.rescale(profile: &profile, minimum: profile.minimum, maximum: $0) }), upperBound: bound, step: step)
                .frame(height: 65)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach([9, 10, 15, 20], id: \.self) { maximum in
                    Button("1–\(maximum)단") { HeatControlMath.rescale(profile: &profile, minimum: 1, maximum: Double(maximum)) }.buttonStyle(.bordered).controlSize(.small)
                } }
            }
            Toggle("0.5단계도 있어요", isOn: $profile.halfSteps)
                .onChange(of: profile.halfSteps) { _, enabled in
                    if !enabled { HeatControlMath.rescale(profile: &profile, minimum: profile.minimum.rounded(), maximum: max(profile.minimum.rounded() + 1, profile.maximum.rounded())) }
                }
            if profile.minimum == 0 { Text("0단계는 전원 OFF로 사용하고, 조리 화력은 1단계 이상(0.5단계 지원 시 0.5단계)으로 안내합니다.").font(.caption).foregroundStyle(Palette.muted) }
            Divider()
            Text("화력은 자동으로 나눠드려요").font(.headline)
            Text("원하면 약불·중불·강불을 선택해 슬라이더로 조정하세요. 실제 열량을 측정한 값은 아닙니다.").font(.caption).foregroundStyle(Palette.muted)
            if profile.maximum - activeMinimum < 4 * step {
                Text("기기 눈금이 5개보다 적어 일부 화력은 같은 단계를 사용해요.").font(.caption).foregroundStyle(Palette.orange)
            }
            Button("화력 간격 다시 나누기") { HeatControlMath.rescale(profile: &profile, minimum: profile.minimum, maximum: profile.maximum) }.font(.caption)
            HeatSelector(selected: $selectedHeat)
            HStack { Text(selectedHeat.label); Spacer(); Text(profile.setting(selectedHeat)).font(.title2.bold()).monospacedDigit().foregroundStyle(Palette.green) }
            Slider(value: Binding(get: { profile.numericMap[selectedHeat.rawValue] ?? profile.minimum }, set: { HeatControlMath.setHeat($0, level: selectedHeat, profile: &profile) }), in: activeMinimum...max(activeMinimum + step, profile.maximum), step: step).disabled(profile.maximum <= activeMinimum).accessibilityLabel("\(selectedHeat.label) 화력")
            HStack { Text("\(KitchenProfile.number(activeMinimum))단"); Spacer(); Text("\(KitchenProfile.number(profile.maximum))단") }.font(.caption).foregroundStyle(Palette.muted)
            DisclosureGroup("직접 숫자를 입력할게요") {
                VStack(spacing: 12) {
                    numericField("최소 단계", value: Binding(get: { profile.minimum }, set: { if $0.isFinite && $0 >= 0 && $0 < profile.maximum { HeatControlMath.rescale(profile: &profile, minimum: $0, maximum: profile.maximum) } }))
                    numericField("최대 단계", value: Binding(get: { profile.maximum }, set: { if $0.isFinite && $0 > profile.minimum && $0 <= 100 { HeatControlMath.rescale(profile: &profile, minimum: profile.minimum, maximum: $0) } }))
                }.padding(.top, 12)
            }.font(.subheadline)
        }.padding(.vertical, 10)
        .onAppear {
            let levels = HeatLevel.allCases.filter { $0 != .off }
            let values = levels.compactMap { profile.numericMap[$0.rawValue] }
            if profile.maximum - activeMinimum >= 4 * step && Set(values).count < levels.count {
                HeatControlMath.rescale(profile: &profile, minimum: profile.minimum, maximum: profile.maximum)
            }
        }
    }
    private func limitTile(_ title: String, _ value: Double) -> some View { VStack(spacing: 6) { Text(title).font(.caption).foregroundStyle(Palette.muted); Text("\(KitchenProfile.number(value))단").font(.title2.bold()).monospacedDigit() }.frame(maxWidth: .infinity).padding(14).background(Palette.background, in: RoundedRectangle(cornerRadius: 16)) }
    private func numericField(_ title: String, value: Binding<Double>) -> some View { HStack { Text(title); TextField(title, value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) } }
}
struct RangeControl: View {
    @Binding var minimum: Double
    @Binding var maximum: Double
    var upperBound: Double
    var step: Double
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 36)
            let left = 18 + CGFloat(minimum / upperBound) * width
            let right = 18 + CGFloat(maximum / upperBound) * width
            ZStack(alignment: .topLeading) {
                Capsule().fill(Palette.green.opacity(0.12)).frame(width: width, height: 8).offset(x: 18, y: 24)
                Capsule().fill(Palette.green).frame(width: max(0, right - left), height: 8).offset(x: left, y: 24)
                handle("최소", value: minimum, x: left).highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("range")).onChanged { gesture in minimum = min(maximum - step, max(0, snapped(Double((gesture.location.x - 18) / width) * upperBound))) }).accessibilityRepresentation {
                    Slider(value: $minimum, in: 0...max(step, maximum - step), step: step).accessibilityLabel("최소 단계").accessibilityValue(KitchenProfile.number(minimum))
                }
                handle("최대", value: maximum, x: right).highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("range")).onChanged { gesture in maximum = min(upperBound, max(minimum + step, snapped(Double((gesture.location.x - 18) / width) * upperBound))) }).accessibilityRepresentation {
                    Slider(value: $maximum, in: min(upperBound - step, minimum + step)...upperBound, step: step).accessibilityLabel("최대 단계").accessibilityValue(KitchenProfile.number(maximum))
                }
            }.coordinateSpace(name: "range")
        }
    }
    private func snapped(_ value: Double) -> Double { (value / step).rounded() * step }
    private func handle(_ title: String, value: Double, x: CGFloat) -> some View { VStack(spacing: 5) { Circle().fill(.white).frame(width: 32, height: 32).overlay(Circle().stroke(Palette.green, lineWidth: 3)).shadow(color: .black.opacity(0.1), radius: 3, y: 2); Text(title).font(.caption2).foregroundStyle(Palette.muted) }.frame(width: 44).offset(x: x - 22, y: 12).accessibilityElement(children: .ignore).accessibilityLabel("\(title) 단계").accessibilityValue(KitchenProfile.number(value)) }
}
struct HeatSelector: View {
    @Binding var selected: HeatLevel
    var body: some View { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 7) { ForEach(HeatLevel.allCases.filter { $0 != .off }, id: \.self) { level in Button { selected = level } label: { Text(level.label).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 11).foregroundStyle(selected == level ? .white : Palette.green).background(selected == level ? Palette.green : Palette.green.opacity(0.08), in: Capsule()) }.buttonStyle(.plain).accessibilityAddTraits(selected == level ? .isSelected : []) } } } }
}
struct DialHeatEditor: View {
    @Binding var profile: KitchenProfile
    @State private var previewHeat: HeatLevel = .medium
    private var dial: DialConfiguration { profile.dialConfiguration ?? .clockwiseFromOff() }
    private func setEnd(_ angle: Double) {
        var value = DialConfiguration.clockwiseFromOff(sweep: dial.sweep, strongAtEnd: dial.strongAtEnd)
        value.moveEnd(to: angle)
        profile.dialConfiguration = value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if profile.dialConfiguration == nil || dial.startAngle != 0 || !dial.clockwise || dial.offAngle != 0 {
                Text("기존 눈금 설정을 사용 중이에요.").font(.subheadline).foregroundStyle(Palette.muted)
                Button("OFF부터 시계방향으로 새로 설정") {
                    profile.dialConfiguration = .clockwiseFromOff()
                }.buttonStyle(.borderedProminent)
            } else {
                Text("OFF에서 시계방향으로, 끝 위치만 맞춰주세요.").font(.subheadline).foregroundStyle(Palette.muted)
                DialFace(configuration: dial, pointerAngle: dial.endAngle, pointLabel: "회전 끝", editable: true, onAngle: setEnd).frame(height: 260)
                HStack {
                    Label("시작 · OFF", systemImage: "power")
                    Spacer()
                    Text("끝 · " + DialConfiguration.clockLabel(dial.endAngle)).bold()
                }.font(.caption).foregroundStyle(Palette.green)
                Slider(value: Binding(get: { dial.sweep }, set: setEnd), in: 30...330, step: 15).accessibilityLabel("시계방향 회전 끝")
                Text("원 위를 누르거나 슬라이더를 움직여주세요.").font(.caption).foregroundStyle(Palette.muted)
                Divider()
                HeatSelector(selected: $previewHeat)
                Text("\(previewHeat.label) · \(profile.setting(previewHeat))").font(.subheadline.bold()).foregroundStyle(Palette.green)
                DisclosureGroup("불 세기가 반대로 표시되나요?") {
                    Toggle("끝 쪽이 강불", isOn: Binding(get: { dial.strongAtEnd }, set: { profile.dialConfiguration?.strongAtEnd = $0 }))
                    Text("눈금 위치를 나눈 참고값이에요. 실제 불 세기를 확인해주세요.").font(.caption).foregroundStyle(Palette.muted)
                }.font(.caption)
            }
        }.padding(.vertical, 10)
    }
}
struct DialFace: View {
    var configuration: DialConfiguration
    var pointerAngle: Double
    var pointLabel: String
    var editable = false
    var onAngle: ((Double) -> Void)?
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = side / 2 - 28
            ZStack {
                Canvas { context, size in
                    var arc = Path()
                    for index in 0...90 {
                        let point = position(configuration.angle(at: Double(index) / 90), center: center, radius: radius)
                        if index == 0 { arc.move(to: point) } else { arc.addLine(to: point) }
                    }
                    context.stroke(arc, with: .color(Palette.green.opacity(0.2)), style: StrokeStyle(lineWidth: 15, lineCap: .round))
                    for index in 0..<24 {
                        let angle = Double(index) * 15
                        var tick = Path(); tick.move(to: position(angle, center: center, radius: radius - 13)); tick.addLine(to: position(angle, center: center, radius: radius - (index % 2 == 0 ? 24 : 18)))
                        context.stroke(tick, with: .color(Palette.muted.opacity(0.4)), lineWidth: 2)
                    }
                    for (angle, _, color) in [(configuration.endAngle, "끝", Palette.orange), (configuration.offAngle, "OFF", Palette.muted)] {
                        let point = position(angle, center: center, radius: radius)
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)), with: .color(color))
                        
                    }
                }
                Circle().fill(Palette.background).overlay(Circle().stroke(.white, lineWidth: 4)).shadow(color: Palette.ink.opacity(0.08), radius: 10, y: 5).frame(width: radius * 1.3, height: radius * 1.3).position(center)
                Capsule().fill(Palette.green).frame(width: 5, height: radius * 0.48).offset(y: -radius * 0.30).rotationEffect(.degrees(pointerAngle)).position(center)
                Text(pointLabel).font(.caption.bold()).padding(5).background(Palette.background.opacity(0.95), in: RoundedRectangle(cornerRadius: 6)).position(center)
                ForEach([0, 90, 180, 270], id: \.self) { angle in Text(angle == 0 ? "OFF" : "\(angle / 30)").font(.caption2).foregroundStyle(Palette.muted).position(position(Double(angle), center: center, radius: radius + 17)) }
            }.contentShape(Rectangle()).highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                guard editable else { return }
                let dx = gesture.location.x - center.x, dy = gesture.location.y - center.y
                if hypot(dx, dy) < 18 { return }
                onAngle?(DialConfiguration.normalize(atan2(dx, -dy) * 180 / .pi))
            }, including: editable ? .all : .none)
            .accessibilityRepresentation {
                if editable {
                    Slider(value: Binding(get: { DialConfiguration.normalize(pointerAngle) }, set: { onAngle?($0) }), in: 0...345, step: 15)
                        .accessibilityLabel("다이얼 \(pointLabel)").accessibilityValue(DialConfiguration.clockLabel(pointerAngle))
                } else { Text("다이얼 \(pointLabel), \(DialConfiguration.clockLabel(pointerAngle))") }
            }
        }
    }
    private func position(_ angle: Double, center: CGPoint, radius: CGFloat) -> CGPoint { let radians = angle * .pi / 180; return CGPoint(x: center.x + CGFloat(sin(radians)) * radius, y: center.y - CGFloat(cos(radians)) * radius) }
}
