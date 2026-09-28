// WhenSpec.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A parsed `--when` value: a Things list bucket, a calendar day, or a day with
/// a reminder time.
///
/// Accepted input: `today`, `evening`/`tonight`, `anytime`, `someday`, any day
/// `DateParser` understands (`2026-11-15`, `tomorrow`, `next friday`), and a
/// day followed by `@HH:MM` or `@9:30pm` to also set a reminder.
public enum WhenSpec: Equatable, Sendable {
    case today
    case evening
    case anytime
    case someday
    /// A calendar day (year, month, day).
    case day(DateComponents)
    /// A calendar day plus reminder time (year, month, day, hour, minute).
    case dayAndTime(DateComponents)

    public static func parse(_ input: String) -> WhenSpec? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch trimmed.lowercased() {
        case "today", "dnes":
            return .today
        case "evening", "tonight", "this evening", "večer", "vecer":
            return .evening
        case "anytime":
            return .anytime
        case "someday":
            return .someday
        default:
            break
        }

        if let at = trimmed.lastIndex(of: "@") {
            let dayPart = String(trimmed[..<at])
            let timePart = String(trimmed[trimmed.index(after: at)...])
            guard var components = parseDay(dayPart), let time = parseTime(timePart) else {
                return nil
            }
            components.hour = time.hour
            components.minute = time.minute
            return .dayAndTime(components)
        }

        return parseDay(trimmed).map { .day($0) }
    }

    /// Parse a calendar day (used for deadlines too). Returns year, month, day only.
    public static func parseDay(_ input: String) -> DateComponents? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let date = DateParser.shared.parse(trimmed) else { return nil }
        return ThingsDateConverter.calendar.dateComponents([.year, .month, .day], from: date)
    }

    /// Parse `14:00`, `7:05`, `9pm` or `9:30pm` into hour and minute.
    static func parseTime(_ input: String) -> (hour: Int, minute: Int)? {
        let lower = input.trimmingCharacters(in: .whitespaces).lowercased()
        let pattern = #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let hourRange = Range(match.range(at: 1), in: lower),
              var hour = Int(lower[hourRange]) else {
            return nil
        }

        var minute = 0
        if let minuteRange = Range(match.range(at: 2), in: lower) {
            minute = Int(lower[minuteRange]) ?? -1
        }

        if let meridiemRange = Range(match.range(at: 3), in: lower) {
            guard (1...12).contains(hour) else { return nil }
            let isPM = lower[meridiemRange] == "pm"
            hour = (hour % 12) + (isPM ? 12 : 0)
        }

        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    /// The value for the Things URL scheme `when` parameter.
    public var urlValue: String {
        switch self {
        case .today: return "today"
        case .evening: return "evening"
        case .anytime: return "anytime"
        case .someday: return "someday"
        case .day(let components):
            return Self.dayString(components)
        case .dayAndTime(let components):
            let time = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
            return "\(Self.dayString(components))@\(time)"
        }
    }

    /// The calendar day to schedule on, or nil for the Anytime/Someday buckets.
    public func scheduledDay(now: Date = Date()) -> DateComponents? {
        switch self {
        case .today, .evening:
            return ThingsDateConverter.calendar.dateComponents([.year, .month, .day], from: now)
        case .anytime, .someday:
            return nil
        case .day(let components), .dayAndTime(let components):
            return DateComponents(year: components.year, month: components.month, day: components.day)
        }
    }

    /// Whether this value carries a reminder time (projects cannot have one).
    public var isReminder: Bool {
        if case .dayAndTime = self { return true }
        return false
    }

    /// Evening and reminder times can only be set through the URL scheme
    /// (AppleScript has no property for either), which needs an auth token.
    public var requiresURLScheme: Bool {
        switch self {
        case .evening, .dayAndTime: return true
        case .today, .anytime, .someday, .day: return false
        }
    }

    private static func dayString(_ components: DateComponents) -> String {
        String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
