import Foundation

/// A bounded, content-based matcher. Microphone levels alone never advance a script.
/// Recreate this value only when the immutable reading snapshot changes.
public struct TeleprompterAlignment: Sendable {
    public let text: String
    public let words: [TeleprompterWord]
    public let paragraphs: [TeleprompterParagraph]
    public var wordCount: Int { words.count }

    private struct Unit: Sendable {
        let value: String
        let wordIndex: Int
    }
    private let units: [Unit]

    public init(text: String) {
        self.text = text
        var words: [TeleprompterWord] = []
        var paragraphs: [TeleprompterParagraph] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byParagraphs) { _, range, _, _ in
            let firstWord = words.count
            let paragraphIndex = paragraphs.count
            for wordRange in Self.wordRanges(in: text, range: range) {
                words.append(.init(id: words.count, text: String(text[wordRange]), range: wordRange,
                                   paragraphIndex: paragraphIndex))
            }
            paragraphs.append(.init(id: paragraphIndex, text: String(text[range]), range: range,
                                    wordRange: firstWord..<words.count))
        }
        self.words = words
        self.paragraphs = paragraphs
        units = words.flatMap { word in
            Self.normalizedUnits(word.text).map { Unit(value: $0, wordIndex: word.id) }
        }
    }

    /// Low-latency startup at an explicit reading position. Every recognized unit
    /// must match that exact prefix; this grants no search or skipping authority.
    public func matchOpening(transcript: String, at position: Int, allowTrailingPartial: Bool) -> TeleprompterMatch? {
        guard words.indices.contains(position), transcript.count <= 2_048 else { return nil }
        let spoken = Self.wordRanges(in: transcript, range: transcript.startIndex..<transcript.endIndex)
            .flatMap { Self.normalizedUnits(String(transcript[$0])) }
        let heard = Self.canonicalSpeechUnits(spoken)
        let reference = Array(units.filter { $0.wordIndex >= position && $0.wordIndex < position + 4 })
        guard !heard.isEmpty, heard.count <= reference.count else { return nil }
        var completed = heard.count
        for index in heard.indices where heard[index] != reference[index].value {
            guard allowTrailingPartial, index == heard.count - 1,
                  reference[index].value.hasPrefix(heard[index]) else { return nil }
            completed -= 1
        }
        guard completed > 0 else { return nil }
        let end = reference[completed - 1].wordIndex + 1
        // A spoken fragment of a multi-unit number is not the complete printed word.
        guard end <= position + 3,
              completed == reference.count || reference[completed].wordIndex >= end else { return nil }
        return TeleprompterMatch(nextWordIndex: end, matchedWordRange: position..<end, score: 1)
    }

    /// `position` is the exclusive spoken-word boundary. Ordinary updates search nearby;
    /// a unique, much longer phrase can recover after a skipped heading or delayed batch.
    public func match(transcript: String, near position: Int) -> TeleprompterMatch? {
        guard !units.isEmpty else { return nil }
        // Providers may send long revised segments. Bound both normalization and alignment.
        let suffix = String(transcript.suffix(2_048))
        let spoken = Self.wordRanges(in: suffix, range: suffix.startIndex..<suffix.endIndex)
            .suffix(24).flatMap { Self.normalizedUnits(String(suffix[$0])) }
        let heard = Array(Self.canonicalSpeechUnits(spoken).suffix(18))
        let minimumEvidence = min(3, units.count)
        guard heard.count >= minimumEvidence else { return nil }
        let cursor = min(max(position, 0), words.count)
        let lower = max(0, cursor - 12)
        let upper = min(words.count, cursor + 36)
        let reference = units.filter { lower <= $0.wordIndex && $0.wordIndex < upper }
        guard !reference.isEmpty else { return nil }

        var best: (match: TeleprompterMatch, rank: Double)?
        // Try suffixes so a digression followed by an on-script phrase can reacquire.
        for length in minimumEvidence...heard.count {
            let query = Array(heard.suffix(length))
            for candidate in Self.align(query, against: reference, minimumEvidence: minimumEvidence) {
                let start = reference[candidate.start].wordIndex
                let end = reference[candidate.end - 1].wordIndex + 1
                let isJump = start > cursor + 8 || end > cursor + 18
                guard !isJump || (candidate.exact >= 5 && candidate.score >= 0.90) else { continue }
                let distance = abs(end - cursor)
                let rank = candidate.score + Double(min(candidate.exact, 12)) * 0.025
                    - Double(distance) * 0.006
                let match = TeleprompterMatch(nextWordIndex: end, matchedWordRange: start..<end,
                                             score: candidate.score)
                if best == nil || rank > best!.rank + 0.000_001
                    || (abs(rank - best!.rank) <= 0.000_001 && end < best!.match.nextWordIndex) {
                    best = (match, rank)
                }
            }
        }
        if let best { return best.match }
        return recover(heard: heard, after: cursor)
    }

    /// Longer ASR segments can arrive after the normal window has been passed. Anchor
    /// on the exact trailing phrase, then verify the complete context before reanchoring.
    /// A short or duplicated phrase never receives this wider search authority.
    private func recover(heard: [String], after cursor: Int) -> TeleprompterMatch? {
        guard heard.count >= 8, units.count >= 8 else { return nil }
        let anchor = Array(heard.suffix(2))
        var ends: [Int] = []
        for index in 1..<units.count where units[index].wordIndex >= cursor {
            if units[index - 1].value == anchor[0], units[index].value == anchor[1] {
                ends.append(index + 1)
                // Common repeated endings need more speech before a safe reanchor.
                if ends.count > 32 { return nil }
            }
        }
        var matches: [Int: (match: TeleprompterMatch, rank: Double)] = [:]
        for end in ends {
            let lower = max(0, end - heard.count - 6)
            let reference = Array(units[lower..<end])
            for length in 8...heard.count {
                for candidate in Self.align(Array(heard.suffix(length)), against: reference, minimumEvidence: 8)
                    where candidate.end == reference.count && candidate.score >= 0.88 {
                    let startWord = reference[candidate.start].wordIndex
                    let endWord = reference[candidate.end - 1].wordIndex + 1
                    guard endWord > cursor, endWord - startWord >= 6, candidate.informative >= 3 else { continue }
                    let match = TeleprompterMatch(nextWordIndex: endWord,
                        matchedWordRange: startWord..<endWord, score: candidate.score)
                    let rank = candidate.score + Double(min(candidate.exact, 18)) * 0.025
                    if matches[endWord].map({ rank > $0.rank }) ?? true { matches[endWord] = (match, rank) }
                }
            }
        }
        let ranked = matches.values.sorted { $0.rank > $1.rank }
        guard let best = ranked.first else { return nil }
        if ranked.count > 1, best.rank - ranked[1].rank < 0.04 { return nil }
        return best.match
    }

    private struct Cell {
        var cost: Double
        var start: Int
        var exact: Int
        var informative: Int
    }
    private struct Candidate {
        let start: Int
        let end: Int
        let exact: Int
        let informative: Int
        let score: Double
    }

    /// Semi-global weighted edit alignment: reference prefixes are free, but every
    /// recognized suffix word must be explained. The final word must match lexically
    /// or have a one-letter correction supported by at least four exact context units.
    private static func align(_ query: [String], against reference: [Unit], minimumEvidence: Int) -> [Candidate] {
        var previous = (0...reference.count).map { Cell(cost: 0, start: $0, exact: 0, informative: 0) }
        var candidates: [Candidate] = []
        for (queryIndex, value) in query.enumerated() {
            var current = [Cell(cost: previous[0].cost + insertionCost(value), start: 0, exact: 0, informative: 0)]
            for referenceIndex in reference.indices {
                let expected = reference[referenceIndex].value
                let exact = expected == value
                let substitution = exact ? 0 : substitutionCost(value, expected)
                var diagonal = previous[referenceIndex]
                diagonal.cost += substitution
                if exact {
                    diagonal.exact += 1
                    if !commonWords.contains(value) { diagonal.informative += 1 }
                }
                var insertion = previous[referenceIndex + 1]
                insertion.cost += insertionCost(value)
                var deletion = current[referenceIndex]
                deletion.cost += 0.85
                let selected = [diagonal, insertion, deletion].min {
                    if abs($0.cost - $1.cost) > 0.000_001 { return $0.cost < $1.cost }
                    return $0.exact > $1.exact
                }!
                current.append(selected)

                let anchoredCorrection = substitution <= 0.4 && query.count >= 5 && diagonal.exact >= 4
                guard queryIndex == query.count - 1, exact || anchoredCorrection,
                      diagonal.exact >= minimumEvidence, diagonal.informative > 0 else { continue }
                let span = referenceIndex + 1 - diagonal.start
                let score = 1 - diagonal.cost / Double(max(query.count, span))
                guard span > 0, score >= 0.82 else { continue }
                candidates.append(.init(start: diagonal.start, end: referenceIndex + 1,
                                        exact: diagonal.exact, informative: diagonal.informative, score: score))
            }
            previous = current
        }
        return candidates
    }

    private static func insertionCost(_ word: String) -> Double {
        fillers.contains(word) ? 0.25 : 1
    }

    private static func substitutionCost(_ lhs: String, _ rhs: String) -> Double {
        // A conservative plural mismatch is useful; arbitrary phonetic similarities are
        // deliberately not guessed because false progress is worse than holding.
        if lhs.count > 3, rhs.count > 3, lhs + "s" == rhs || rhs + "s" == lhs { return 0.4 }
        if lhs.count >= 5, rhs.count >= 5, isSingleLetterDifference(lhs, rhs) { return 0.4 }
        return 1
    }

    private static func isSingleLetterDifference(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs), right = Array(rhs)
        guard abs(left.count - right.count) <= 1 else { return false }
        var l = 0, r = 0, differences = 0
        while l < left.count, r < right.count {
            if left[l] == right[r] { l += 1; r += 1; continue }
            differences += 1
            guard differences <= 1 else { return false }
            if left.count >= right.count { l += 1 }
            if right.count >= left.count { r += 1 }
        }
        return differences + (left.count - l) + (right.count - r) <= 1
    }

    private static func wordRanges(in text: String, range: Range<String.Index>) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var index = range.lowerBound
        while index < range.upperBound {
            guard text[index].isLetter || text[index].isNumber else {
                index = text.index(after: index)
                continue
            }
            let start = index
            index = text.index(after: index)
            while index < range.upperBound {
                let character = text[index]
                if character.isLetter || character.isNumber {
                    index = text.index(after: index)
                    continue
                }
                let next = text.index(after: index)
                let previous = text.index(before: index)
                let isApostrophe = (character == "'" || character == "’")
                    && next < range.upperBound && text[next].isLetter && text[previous].isLetter
                let isNumberSeparator = (character == "." || character == ",")
                    && next < range.upperBound && text[next].isNumber && text[previous].isNumber
                guard isApostrophe || isNumberSeparator else { break }
                index = next
            }
            result.append(start..<index)
        }
        return result
    }

    private static func normalizedUnits(_ word: String) -> [String] {
        let value = word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "’", with: "'")
        if let contraction = contractions[value] { return contraction }
        if let ordinal = ordinals[value] { return numberWords(ordinal) }
        for suffix in ["st", "nd", "rd", "th"] where value.hasSuffix(suffix) {
            if let ordinal = Int(value.dropLast(suffix.count)), (0...9_999).contains(ordinal) {
                return numberWords(ordinal)
            }
        }
        let numeric = value.replacingOccurrences(of: ",", with: "")
        if numeric.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(numeric), number <= 9_999 {
            return numberWords(number)
        }
        let decimal = numeric.split(separator: ".", omittingEmptySubsequences: false)
        if decimal.count == 2, let whole = Int(decimal[0]), whole <= 9_999, !decimal[1].isEmpty,
           decimal[1].allSatisfy({ $0.isASCII && $0.isNumber }) {
            return numberWords(whole) + ["point"] + decimal[1].compactMap { $0.wholeNumberValue }.flatMap(numberWords)
        }
        return [value]
    }

    /// Dates commonly arrive as “seventeen seventy six” while the script contains 1776.
    /// Canonicalize those year forms to the same cardinal units as printed numbers.
    private static func canonicalSpeechUnits(_ input: [String]) -> [String] {
        let century = ["seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20]
        let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
                    "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
        let ones = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                    "six": 6, "seven": 7, "eight": 8, "nine": 9]
        var result: [String] = []
        var index = 0
        while index < input.count {
            if index + 1 < input.count, let first = century[input[index]], let last = tens[input[index + 1]] {
                var year = first * 100 + last
                var consumed = 2
                if index + 2 < input.count, let final = ones[input[index + 2]] { year += final; consumed = 3 }
                result.append(contentsOf: numberWords(year))
                index += consumed
            } else {
                result.append(input[index])
                index += 1
            }
        }
        return result
    }

    private static func numberWords(_ number: Int) -> [String] {
        let small = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                     "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        if number < 20 { return [small[number]] }
        if number < 100 { return [tens[number / 10]] + (number % 10 == 0 ? [] : numberWords(number % 10)) }
        if number < 1_000 { return numberWords(number / 100) + ["hundred"] + (number % 100 == 0 ? [] : numberWords(number % 100)) }
        return numberWords(number / 1_000) + ["thousand"] + (number % 1_000 == 0 ? [] : numberWords(number % 1_000))
    }

    private static let fillers: Set<String> = ["um", "uh", "erm", "hmm"]
    private static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6,
        "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12,
        "thirteenth": 13, "fourteenth": 14, "fifteenth": 15, "sixteenth": 16,
        "seventeenth": 17, "eighteenth": 18, "nineteenth": 19, "twentieth": 20
    ]
    private static let commonWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "i", "we", "you", "he", "she", "it", "they", "us", "our", "your",
        "my", "his", "her", "their", "to", "of", "in", "on", "at", "for", "with", "is", "are", "am", "was", "were",
        "be", "been", "have", "has", "had", "do", "does", "did", "this", "that", "these", "those", "as", "from", "by",
        "so", "can", "will", "would", "should", "could", "not", "if", "then", "than", "just", "let", "go"
    ]
    private static let contractions: [String: [String]] = [
        "i'm": ["i", "am"], "i've": ["i", "have"], "i'll": ["i", "will"], "i'd": ["i", "would"],
        "we're": ["we", "are"], "we've": ["we", "have"], "we'll": ["we", "will"], "we'd": ["we", "would"],
        "you're": ["you", "are"], "you've": ["you", "have"], "you'll": ["you", "will"],
        "they're": ["they", "are"], "they've": ["they", "have"], "they'll": ["they", "will"],
        "it's": ["it", "is"], "that's": ["that", "is"], "there's": ["there", "is"], "let's": ["let", "us"],
        "don't": ["do", "not"], "doesn't": ["does", "not"], "didn't": ["did", "not"],
        "isn't": ["is", "not"], "aren't": ["are", "not"], "wasn't": ["was", "not"], "weren't": ["were", "not"],
        "can't": ["can", "not"], "cannot": ["can", "not"], "won't": ["will", "not"],
        "couldn't": ["could", "not"], "wouldn't": ["would", "not"], "shouldn't": ["should", "not"]
    ]
}
