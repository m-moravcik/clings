// WhenSpecTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import ClingsCore

@Suite("WhenSpec")
struct WhenSpecTests {
    private func day(_ offset: Int) -> DateComponents {
        let calendar = ThingsDateConverter.calendar
        let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) ?? Date()
        return calendar.dateComponents([.year, .month, .day], from: date)
    }

    @Suite("Buckets")
    struct Buckets {
        @Test(arguments: ["today", "Today", "dnes"])
        func today(input: String) {
            #expect(WhenSpec.parse(input) == .today)
        }

        @Test(arguments: ["evening", "tonight", "večer"])
        func evening(input: String) {
            #expect(WhenSpec.parse(input) == .evening)
        }

        @Test func anytime() {
            #expect(WhenSpec.parse("anytime") == .anytime)
        }

        @Test func someday() {
            #expect(WhenSpec.parse("someday") == .someday)
        }
    }

    @Suite("Days")
    struct Days {
        @Test func isoDay() {
            let spec = WhenSpec.parse("2026-11-15")
            #expect(spec == .day(DateComponents(year: 2026, month: 11, day: 15)))
            #expect(spec?.urlValue == "2026-11-15")
        }

        @Test func relativeDay() {
            #expect(WhenSpec.parse("tomorrow") == .day(WhenSpecTests().day(1)))
        }

        @Test func padsSingleDigitUrlValue() {
            #expect(WhenSpec.day(DateComponents(year: 2026, month: 3, day: 7)).urlValue == "2026-03-07")
        }
    }

    @Suite("Day and time")
    struct DayAndTime {
        @Test func isoDayWithTime() {
            let spec = WhenSpec.parse("2026-10-01@14:00")
            #expect(spec == .dayAndTime(DateComponents(year: 2026, month: 10, day: 1, hour: 14, minute: 0)))
            #expect(spec?.urlValue == "2026-10-01@14:00")
        }

        @Test func twelveHourClock() {
            let spec = WhenSpec.parse("2026-10-01@9:30pm")
            #expect(spec == .dayAndTime(DateComponents(year: 2026, month: 10, day: 1, hour: 21, minute: 30)))
        }

        @Test func relativeDayWithTime() {
            let tomorrow = WhenSpecTests().day(1)
            let spec = WhenSpec.parse("tomorrow@7:05")
            #expect(spec == .dayAndTime(DateComponents(
                year: tomorrow.year, month: tomorrow.month, day: tomorrow.day, hour: 7, minute: 5
            )))
            #expect(spec?.urlValue.hasSuffix("@07:05") == true)
        }

        @Test(arguments: ["2026-10-01@25:00", "2026-10-01@12:61", "2026-10-01@", "2026-10-01@noon", "blorp@10:00"])
        func rejectsInvalid(input: String) {
            #expect(WhenSpec.parse(input) == nil)
        }
    }

    @Test func rejectsGarbage() {
        #expect(WhenSpec.parse("blorp") == nil)
        #expect(WhenSpec.parse("") == nil)
    }

    @Suite("Scheduled day")
    struct ScheduledDay {
        @Test func todayAndEveningScheduleForToday() {
            #expect(WhenSpec.today.scheduledDay() == WhenSpecTests().day(0))
            #expect(WhenSpec.evening.scheduledDay() == WhenSpecTests().day(0))
        }

        @Test func bucketsHaveNoDay() {
            #expect(WhenSpec.anytime.scheduledDay() == nil)
            #expect(WhenSpec.someday.scheduledDay() == nil)
        }

        @Test func dayAndTimeDropsTheTime() {
            let spec = WhenSpec.dayAndTime(DateComponents(year: 2026, month: 10, day: 1, hour: 14, minute: 0))
            #expect(spec.scheduledDay() == DateComponents(year: 2026, month: 10, day: 1))
        }
    }

    @Suite("URL-only values")
    struct URLOnly {
        @Test func eveningAndTimeNeedURLScheme() {
            #expect(WhenSpec.evening.requiresURLScheme)
            #expect(WhenSpec.dayAndTime(DateComponents(year: 2026, month: 1, day: 1, hour: 9, minute: 0)).requiresURLScheme)
        }

        @Test func plainDaysAndBucketsDoNot() {
            #expect(!WhenSpec.today.requiresURLScheme)
            #expect(!WhenSpec.someday.requiresURLScheme)
            #expect(!WhenSpec.day(DateComponents(year: 2026, month: 1, day: 1)).requiresURLScheme)
        }
    }

    @Suite("Deadline day")
    struct Deadline {
        @Test func parsesIsoDay() {
            #expect(WhenSpec.parseDay("2026-12-24") == DateComponents(year: 2026, month: 12, day: 24))
        }

        @Test func parsesRelativeDay() {
            #expect(WhenSpec.parseDay("tomorrow") == WhenSpecTests().day(1))
        }

        @Test func rejectsGarbage() {
            #expect(WhenSpec.parseDay("whenever") == nil)
        }
    }
}
