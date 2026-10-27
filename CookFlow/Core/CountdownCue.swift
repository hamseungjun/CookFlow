import Foundation

/// Tracks each deadline independently so repeated UI ticks never repeat a beep.
public struct CountdownCue {
    private var previous: [String: Int] = [:]
    public init() {}
    public mutating func update(id: String, remaining: Int) -> Bool {
        let last = previous.updateValue(remaining, forKey: id)
        guard let last, remaining < last else { return false }
        return remaining == 10 || (0...5).contains(remaining)
    }
    public mutating func retain(ids: Set<String>) {
        previous = previous.filter { ids.contains($0.key) }
    }
}
