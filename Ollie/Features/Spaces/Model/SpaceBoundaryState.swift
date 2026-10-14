import Foundation

struct SpaceBoundaryState {
    private struct Prediction {
        let spaces: [UInt64]
        let target: UInt64
        let expires: TimeInterval
    }

    private var predictions: [String: Prediction] = [:]

    mutating func target(
        direction: SpaceDirection, display: String, current: UInt64, spaces: [UInt64], now: TimeInterval
    ) -> UInt64? {
        let prediction = predictions[display]
        let predicted = prediction.flatMap { $0.expires > now && $0.spaces == spaces ? $0.target : nil }
        guard let index = spaces.firstIndex(of: predicted ?? current) else { return nil }
        let targetIndex = index + (direction == .next ? 1 : -1)
        guard spaces.indices.contains(targetIndex) else { return nil }
        return spaces[targetIndex]
    }

    mutating func record(target: UInt64, display: String, spaces: [UInt64], now: TimeInterval) {
        predictions[display] = Prediction(spaces: spaces, target: target, expires: now + 0.5)
    }

    mutating func reset() { predictions.removeAll(keepingCapacity: true) }
}
