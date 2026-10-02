import Foundation

public enum CaffeineDuration: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 15, thirtyMinutes = 30, oneHour = 60, twoHours = 120

    public var id: Int { rawValue }
    public var duration: Duration { .seconds(rawValue * 60) }
    public var title: String {
        switch self {
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        }
    }
}
