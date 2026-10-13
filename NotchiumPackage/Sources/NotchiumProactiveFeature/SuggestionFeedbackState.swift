import Foundation
import NotchiumCore

public struct SuggestionExposureRecord: Equatable, Sendable {
    public let exposure: SuggestionExposure
    public internal(set) var wasOpened = false
    public internal(set) var response: SuggestionResponse?
    public internal(set) var snoozedUntil: ProactiveTime?
    public internal(set) var suppressesOccurrence = false

    init(exposure: SuggestionExposure) { self.exposure = exposure }
}

public struct SuggestionCategoryFeedback: Equatable, Sendable {
    public internal(set) var positiveWeight = SuggestionPolicyDefaults.initialWeight
    public internal(set) var negativeWeight = SuggestionPolicyDefaults.initialWeight
    public internal(set) var distinctDismissals = 0
    public internal(set) var distinctIgnores = 0
    public internal(set) var isDisabled = false
    public internal(set) var cooldown: SuggestionCooldown?
    public var affinity: Double { positiveWeight / (positiveWeight + negativeWeight) }

    public init() {}
}

/// Bounded, content-free state. No Codable yet: Stage 25A has no persistence contract.
/// Safety receipts are never silently evicted, including when learning is reset.
public struct SuggestionFeedbackState: Equatable, Sendable {
    public internal(set) var exposures: [SuggestionExposureRecord] = []
    public internal(set) var globalCooldown: SuggestionCooldown?
    public internal(set) var wallTimeFloor: Date?
    private var categories: [SuggestionCategory: SuggestionCategoryFeedback] = [:]

    public init() {}

    public internal(set) subscript(category: SuggestionCategory) -> SuggestionCategoryFeedback {
        get { categories[category] ?? SuggestionCategoryFeedback() }
        set { categories[category] = newValue }
    }

    public var hasReceiptCapacity: Bool { exposures.count < SuggestionPolicyDefaults.maximumFeedbackReceipts }

    public func isSuppressed(_ key: SuggestionKey) -> Bool {
        exposures.contains { $0.exposure.identity.key == key && $0.suppressesOccurrence }
    }

    func hasOpenExposure(_ key: SuggestionKey) -> Bool {
        exposures.contains { $0.exposure.identity.key == key && $0.response == nil }
    }

    mutating func observe(_ time: ProactiveTime) {
        wallTimeFloor = max(wallTimeFloor ?? time.wallDate, time.wallDate)
    }
}
