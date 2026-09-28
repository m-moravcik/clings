// ThingsDateConverter.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Converts between Things 3's bitwise-packed date INTEGER and Swift Date/DateComponents.
///
/// Things 3 stores `deadline` and `startDate` as packed integers with this bit layout:
///
///     Bits 26..16: year  (11 bits, supports up to 2047)
///     Bits 15..12: month (4 bits, 1-12)
///     Bits 11..7:  day   (5 bits, 1-31)
///     Bits 6..0:   padding (always zero)
///
/// This is NOT a timestamp. Other date fields (`creationDate`, `userModificationDate`,
/// `stopDate`) use standard Unix timestamps (seconds since 1970-01-01).
public enum ThingsDateConverter {

    // MARK: - Bit Masks & Shifts

    private static let monthMask: Int = 0x0000_F000  // bits 15..12
    private static let dayMask:   Int = 0x0000_0F80  // bits 11..7

    private static let yearShift  = 16
    private static let monthShift = 12
    private static let dayShift   = 7

    /// Years at or beyond this value are sentinels, not real dates. Repeating
    /// templates with a relative deadline store year 4001 in `deadline`.
    private static let sentinelYear = 4000

    /// The bit fields always hold Gregorian components, whatever calendar the user picked.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }

    // MARK: - Decoding

    /// Unpack a Things 3 packed date integer into DateComponents.
    public static func decode(_ packedDate: Int) -> DateComponents? {
        let year  = packedDate >> yearShift
        let month = (packedDate & monthMask) >> monthShift
        let day   = (packedDate & dayMask)   >> dayShift

        guard year > 0, year < sentinelYear, (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }

        return DateComponents(year: year, month: month, day: day)
    }

    /// Unpack a Things 3 packed date integer into a Date (local midnight).
    public static func decodeToDate(_ packedDate: Int) -> Date? {
        guard let components = decode(packedDate) else { return nil }
        return calendar.date(from: components)
    }

    // MARK: - Encoding

    /// Pack year/month/day into a Things 3 date integer.
    public static func encode(year: Int, month: Int, day: Int) -> Int {
        (year << yearShift) | (month << monthShift) | (day << dayShift)
    }

    /// Pack a Date into a Things 3 date integer.
    public static func encodeDate(_ date: Date) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            assertionFailure("Failed to extract date components from \(date)")
            return 0
        }
        return encode(year: year, month: month, day: day)
    }

    // MARK: - Reminder Time

    /// Unpack `reminderTime` (`hour << 26 | minute << 20`) into hour and minute.
    public static func decodeTime(_ packedTime: Int) -> DateComponents? {
        let hour = packedTime >> 26
        let minute = (packedTime >> 20) & 0x3F
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return DateComponents(hour: hour, minute: minute)
    }

    /// Pack hour and minute into a `reminderTime` value.
    public static func encodeTime(hour: Int, minute: Int) -> Int {
        (hour << 26) | (minute << 20)
    }
}
