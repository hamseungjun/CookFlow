import Foundation

public struct DialConfiguration: Codable, Equatable {
    public var offAngle: Double = 0
    public var startAngle: Double = 300
    public var sweep: Double = 150
    public var clockwise = false
    public var strongAtEnd = false
    public init() {}
    public static func clockwiseFromOff(sweep: Double = 270, strongAtEnd: Bool = true) -> DialConfiguration {
        var value = DialConfiguration()
        value.offAngle = 0
        value.startAngle = 0
        value.clockwise = true
        value.strongAtEnd = strongAtEnd
        value.sweep = sweep.isFinite ? min(330, max(30, (sweep / 15).rounded() * 15)) : 270
        return value
    }
    public var endAngle: Double { angle(at: 1) }
    public static func normalize(_ angle: Double) -> Double { let value = angle.truncatingRemainder(dividingBy: 360); return value < 0 ? value + 360 : value }
    public func angle(at fraction: Double) -> Double { Self.normalize(startAngle + (clockwise ? 1 : -1) * sweep * fraction) }
    public func angle(for level: HeatLevel) -> Double {
        if level == .off { return offAngle }
        let strength: Double
        switch level { case .off: strength = 0; case .low: strength = 0.1; case .mediumLow: strength = 0.3; case .medium: strength = 0.5; case .mediumHigh: strength = 0.7; case .high: strength = 0.9 }
        return angle(at: strongAtEnd ? strength : 1 - strength)
    }
    public static func clockLabel(_ angle: Double) -> String {
        let total = Int((normalize(angle) / 30 * 60 / 5).rounded()) * 5 % 720
        let hour = total / 60 == 0 ? 12 : total / 60
        let minute = total % 60
        return minute == 0 ? "\(hour)시 방향" : "\(hour)시 \(minute)분 방향"
    }
    public var validationErrors: [String] {
        guard [offAngle, startAngle, sweep].allSatisfy(\.isFinite), (0..<360).contains(offAngle), (0..<360).contains(startAngle), (30...330).contains(sweep) else { return ["다이얼 시작·끝 위치를 30~330도 범위로 지정해주세요."] }
        return []
    }
    public mutating func moveEnd(to angle: Double) {
        let distance = Self.normalize(clockwise ? angle - startAngle : startAngle - angle)
        sweep = min(330, max(30, (distance / 15).rounded() * 15))
    }
    public mutating func moveStart(to angle: Double) {
        let oldEnd = endAngle
        startAngle = Self.normalize((angle / 15).rounded() * 15)
        moveEnd(to: oldEnd)
    }
}
public enum HeatControlMath {
    public static func rescale(profile: inout KitchenProfile, minimum: Double, maximum: Double) {
        guard minimum.isFinite, maximum.isFinite, minimum < maximum else { return }
        let step = profile.halfSteps ? 0.5 : 1.0
        let activeMinimum = min(maximum, max(step, minimum))
        let levels = HeatLevel.allCases.filter { $0 != .off }
        let slots = max(0, Int(((maximum - activeMinimum) / step).rounded(.down)))
        // Derive from the new range, never from previously rounded values.
        for (index, level) in levels.enumerated() {
            let slot = (Double(slots) * Double(index) / Double(levels.count - 1)).rounded()
            profile.numericMap[level.rawValue] = min(maximum, activeMinimum + slot * step)
        }
        profile.minimum = minimum; profile.maximum = maximum
    }
    public static func setHeat(_ value: Double, level: HeatLevel, profile: inout KitchenProfile) {
        let levels = HeatLevel.allCases.filter { $0 != .off }
        guard let index = levels.firstIndex(of: level), value.isFinite else { return }
        let step = profile.halfSteps ? 0.5 : 1.0
        let activeMinimum = max(step, profile.minimum)
        let gap = profile.maximum - activeMinimum >= Double(levels.count - 1) * step ? step : 0
        let lower = activeMinimum + Double(index) * gap
        let upper = profile.maximum - Double(levels.count - 1 - index) * gap
        let target = min(upper, max(lower, (value / step).rounded() * step))
        profile.numericMap[level.rawValue] = target
        for position in levels.indices.reversed() where position < index {
            let next = profile.numericMap[levels[position + 1].rawValue] ?? target
            profile.numericMap[levels[position].rawValue] = min(profile.numericMap[levels[position].rawValue] ?? next - gap, next - gap)
        }
        for position in levels.indices where position > index {
            let previous = profile.numericMap[levels[position - 1].rawValue] ?? target
            profile.numericMap[levels[position].rawValue] = max(profile.numericMap[levels[position].rawValue] ?? previous + gap, previous + gap)
        }
    }
}
