import Foundation

/// Conservative English temporal suffixes only: prose elsewhere is never removed.
/// Calendar arithmetic uses the supplied user's calendar and time zone.
struct ReminderNaturalLanguageParser {
    struct Suggestion {
        let date: Date
        let includesTime: Bool
        let hasDate: Bool
        let title: String
        let signature: String
        let preservesTime: Bool
    }

    private let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    private static let timePattern = #"(?i)(?<![\w:/+.-])(?:\d{1,3}(?::\d{1,3})?\s*[ap]m|\d{1,3}:\d{1,3})(?![\w:])"#
    private static let datePattern = #"(?i)(?<![\w/])(?:(?:(?:this|next)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|today|tomorrow|(?:january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sep|october|oct|november|nov|december|dec)\s+\d{1,2}(?:,?\s+\d{4})?|\d{1,2}/\d{1,2}(?:/\d{4})?)(?![\w/])"#

    func parse(_ text: String, now: Date, calendar: Calendar = .current) -> Suggestion? {
        let source = text as NSString
        var end = (text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) as NSString).length
        var ranges: [NSRange] = []
        var time: (hour: Int, minute: Int)?
        let times = matches(Self.timePattern, text)
        var invalidTime = false
        if let match = times.last, NSMaxRange(match.range) == end {
            time = parseTime(source.substring(with: match.range))
            invalidTime = time == nil
            let start = prefixEnd(source, before: match.range.location, allowing: ["at"])
            if time != nil { ranges.append(NSRange(location: start, length: end - start)) }
            end = start
        }
        var day: Date?
        var dayIdentity = ""
        let dates = matches(Self.datePattern, source.substring(to: end))
        if let match = dates.last, NSMaxRange(match.range) == end {
            let preceding = source.substring(to: match.range.location)
                .split(whereSeparator: \.isWhitespace).last?.lowercased()
            // Do not reinterpret an unsupported qualifier as a bare weekday.
            guard !["last", "every", "each", "not", "this", "next"].contains(preceding ?? "") else { return nil }
            guard let parsed = parseDay(source.substring(with: match.range), now: now, calendar: calendar) else { return nil }
            day = parsed
            dayIdentity = source.substring(with: match.range).lowercased().filter { !$0.isWhitespace }
            let start = prefixEnd(source, before: match.range.location, allowing: ["on"])
            ranges.append(NSRange(location: start, length: end - start))
            end = start
        }
        guard day != nil || time != nil else { return nil }
        let remaining = source.substring(to: end)
        if day == nil && (remaining.range(of: #"\d/\d|\b(?:next|this|at)$"#, options: [.regularExpression, .caseInsensitive]) != nil) { return nil }
        var result = day ?? calendar.startOfDay(for: now)
        if let time {
            let components = DateComponents(hour: time.hour, minute: time.minute, second: 0)
            if day == nil {
                // Next real occurrence, including DST gaps/folds; never in the past.
                guard let next = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) else { return nil }
                result = next
            } else {
                guard let timed = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: result),
                      calendar.isDate(timed, inSameDayAs: result),
                      calendar.component(.hour, from: timed) == time.hour,
                      calendar.component(.minute, from: timed) == time.minute else { return nil }
                result = timed
            }
        }
        let cleaned = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            cleaned.replaceCharacters(in: range, with: "")
        }
        let title = (cleaned as String).trimmingCharacters(in: .whitespacesAndNewlines)
        // Semantic identity means harmless formatting changes never defeat a manual edit.
        let timeIdentity = time.map { "\($0.hour):\($0.minute)" } ?? ""
        return Suggestion(date: result, includesTime: time != nil, hasDate: day != nil,
                          title: title,
                          signature: dayIdentity + "|" + timeIdentity,
                          preservesTime: invalidTime)
    }

    private func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern).matches(in: text, range: NSRange(text.startIndex..., in: text))) ?? []
    }

    private func prefixEnd(_ source: NSString, before position: Int, allowing connectors: [String]) -> Int {
        var prefix = source.substring(to: position).trimmingCharacters(in: .whitespacesAndNewlines)
        if let word = prefix.split(whereSeparator: \.isWhitespace).last, connectors.contains(word.lowercased()) {
            prefix = String(prefix.dropLast(word.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Preserve leading whitespace offsets (NSString ranges are UTF-16, not character counts).
        let original = source.substring(to: position)
        let trailing = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingLength = (original as NSString).range(of: trailing).location
        return prefix.isEmpty ? 0 : leadingLength + (prefix as NSString).length
    }

    private func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
        let value = text.lowercased().filter { !$0.isWhitespace }
        let hasPeriod = value.hasSuffix("am") || value.hasSuffix("pm")
        let numbers = (hasPeriod ? String(value.dropLast(2)) : value).split(separator: ":", omittingEmptySubsequences: false)
        guard let first = numbers.first, first.count <= 2, let hour = Int(first),
              numbers.count <= 2 else { return nil }
        let minute = numbers.count == 2 ? Int(numbers[1]) : 0
        guard let minute, (0...59).contains(minute),
              numbers.count == 1 || numbers[1].count == 2 else { return nil }
        if hasPeriod {
            guard (1...12).contains(hour) else { return nil }
            return (hour % 12 + (value.hasSuffix("pm") ? 12 : 0), minute)
        }
        guard (0...23).contains(hour) else { return nil }
        return (hour, minute)
    }

    private func parseDay(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let value = text.lowercased()
        let today = calendar.startOfDay(for: now)
        if value == "today" { return today }
        if value == "tomorrow" { return calendar.date(byAdding: .day, value: 1, to: today) }
        let words = value.split(whereSeparator: \.isWhitespace).map(String.init)
        if let last = words.last, let index = Self.weekdays.firstIndex(of: last) {
            let weekday = index + 1
            let current = calendar.component(.weekday, from: today)
            if words.first == "next" {
                guard let week = calendar.dateInterval(of: .weekOfYear, for: today),
                      let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: week.start) else { return nil }
                return calendar.date(byAdding: .day, value: (weekday - calendar.firstWeekday + 7) % 7, to: nextWeek)
            }
            let distance = (weekday - current + 7) % 7
            return calendar.date(byAdding: .day, value: distance == 0 && words.first != "this" ? 7 : distance, to: today)
        }
        let pieces = value.replacingOccurrences(of: ",", with: "").split { $0.isWhitespace || $0 == "/" }.map(String.init)
        guard pieces.count == 2 || pieces.count == 3 else { return nil }
        let month = Int(pieces[0]) ?? Self.months.firstIndex(where: { $0 == pieces[0] || String($0.prefix(3)) == pieces[0] }).map { $0 + 1 }
        guard let month, let day = Int(pieces[1]), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let explicitYear = pieces.count == 3
        let year = explicitYear ? Int(pieces[2]) : calendar.component(.year, from: now)
        guard let year else { return nil }
        func validated(_ year: Int) -> Date? {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.year, from: date) == year,
                  calendar.component(.month, from: date) == month,
                  calendar.component(.day, from: date) == day else { return nil }
            return date
        }
        guard var date = validated(year) else { return nil }
        if !explicitYear && date < today {
            guard let future = validated(year + 1) else { return nil }
            date = future
        }
        // Use native detection when its interpretation agrees with our explicit components.
        // Detector relative dates depend on wall time; deterministic calendar rules handle those.
        if explicitYear, let match = detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.range.length == (text as NSString).length, let detected = match.date,
           calendar.isDate(detected, inSameDayAs: date) { return calendar.startOfDay(for: detected) }
        return date
    }
}
