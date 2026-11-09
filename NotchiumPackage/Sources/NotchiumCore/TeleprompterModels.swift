import Foundation

public enum TeleprompterMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case voiceFollow, voiceGated, fixedSpeed

    public var id: Self { self }
    public var title: String {
        switch self {
        case .voiceFollow: "Voice Follow"
        case .voiceGated: "Fixed Speed + Voice Pause"
        case .fixedSpeed: "Fixed Speed"
        }
    }
    public var usesMicrophone: Bool { self != .fixedSpeed }
}

public struct TeleprompterScript: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var text: String

    public init(id: UUID, title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }
}

/// Indices refer only to the immutable source text held by the corresponding alignment.
public struct TeleprompterWord: Identifiable, Equatable, Sendable {
    public let id: Int
    public let text: String
    public let range: Range<String.Index>
    public let paragraphIndex: Int
}

public struct TeleprompterParagraph: Identifiable, Equatable, Sendable {
    public let id: Int
    public let text: String
    public let range: Range<String.Index>
    public let wordRange: Range<Int>
}

public struct TeleprompterMatch: Equatable, Sendable {
    /// Exclusive script-word boundary, in 0...wordCount.
    public let nextWordIndex: Int
    public let matchedWordRange: Range<Int>
    public let score: Double
}
