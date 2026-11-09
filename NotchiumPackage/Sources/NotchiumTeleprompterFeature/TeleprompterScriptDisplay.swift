import NotchiumCore
import SwiftUI

/// Match normalization never changes punctuation or symbols in the displayed script.
enum TeleprompterScriptDisplay {
    struct Fragment: Equatable {
        let text: String
        let wordIndex: Int
        let isWord: Bool
    }

    static func line(alignment: TeleprompterAlignment, words: Range<Int>, currentWord: Int) -> AttributedString {
        var result = AttributedString()
        for fragment in fragments(alignment: alignment, words: words) {
            var text = AttributedString(fragment.text)
            text.foregroundColor = fragment.wordIndex < currentWord ? .white.opacity(0.4) : .white
            if fragment.isWord, fragment.wordIndex == currentWord { text.underlineStyle = .single }
            result.append(text)
        }
        return result
    }

    static func fragments(alignment: TeleprompterAlignment, words: Range<Int>) -> [Fragment] {
        guard !words.isEmpty, words.lowerBound >= 0, words.upperBound <= alignment.wordCount else { return [] }
        let source = alignment.text
        let start = boundary(before: words.lowerBound, alignment: alignment)
        let end = boundary(before: words.upperBound, alignment: alignment)
        var cursor = start
        var result: [Fragment] = []
        for index in words {
            let word = alignment.words[index]
            result.append(.init(text: String(source[cursor..<word.range.lowerBound]), wordIndex: index, isWord: false))
            result.append(.init(text: String(source[word.range]), wordIndex: index, isWord: true))
            cursor = word.range.upperBound
        }
        result.append(.init(text: String(source[cursor..<end]), wordIndex: words.upperBound - 1, isWord: false))
        return result
    }

    private static func boundary(before index: Int, alignment: TeleprompterAlignment) -> String.Index {
        if index == 0 { return alignment.text.startIndex }
        if index == alignment.wordCount { return alignment.text.endIndex }
        let nextWord = alignment.words[index]
        if nextWord.paragraphIndex != alignment.words[index - 1].paragraphIndex {
            return alignment.paragraphs[nextWord.paragraphIndex].range.lowerBound
        }
        let previous = alignment.words[index - 1].range.upperBound
        let next = alignment.words[index].range.lowerBound
        let delimiter = alignment.text[previous..<next]
        if let whitespace = delimiter.lastIndex(where: { $0.isWhitespace }) {
            return alignment.text.index(after: whitespace)
        }
        return previous
    }
}
