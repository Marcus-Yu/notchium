import Foundation
import NotchiumCore

/// SpeechTranscriber publishes unfinished trailing words such as “unanim” or “Dec”.
/// Only completed context is eligible for progress; a fragment is never a new match.
enum TeleprompterPartialMatch {
    static func completedPrefix(in text: String, alignment: TeleprompterAlignment,
                                near position: Int, confirmedWord: Int) -> TeleprompterMatch? {
        let suffix = String(text.suffix(2_048)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = suffix.range(of: "[\\p{L}\\p{N}’']+$", options: .regularExpression),
              range.lowerBound > suffix.startIndex,
              let match = alignment.match(transcript: String(suffix[..<range.lowerBound]), near: position),
              match.nextWordIndex >= confirmedWord,
              match.nextWordIndex < alignment.wordCount else { return nil }
        let fragment = normalized(String(suffix[range]))
        let expected = normalized(alignment.words[match.nextWordIndex].text)
        guard !fragment.isEmpty, fragment.count < expected.count, expected.hasPrefix(fragment) else { return nil }
        return match
    }

    private static func normalized(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "’", with: "'")
    }
}
