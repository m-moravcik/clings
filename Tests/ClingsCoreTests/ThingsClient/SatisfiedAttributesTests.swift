// SatisfiedAttributesTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import ClingsCore

/// Things does not touch a to-do (or its modification date) for a write that
/// changes nothing, so clings drops already-satisfied attributes before sending.
@Suite("TodoUpdateAttributes.removingSatisfied")
struct SatisfiedAttributesTests {
    static let today = ThingsDateConverter.calendar.dateComponents([.year, .month, .day], from: Date())

    static func current(
        title: String = "Call",
        notes: String = "n",
        start: TodoStart = .anytime,
        startDay: DateComponents? = nil,
        isEvening: Bool = false,
        reminderTime: DateComponents? = nil,
        deadline: DateComponents? = nil,
        tags: [String] = ["home"],
        projectId: String? = "p1",
        areaId: String? = nil,
        headingId: String? = nil,
        checklist: [ChecklistEntry] = []
    ) -> TodoSnapshot {
        TodoSnapshot(
            title: title, notes: notes, status: .open, start: start, startDay: startDay,
            isEvening: isEvening, reminderTime: reminderTime, deadline: deadline, tags: tags,
            projectId: projectId, areaId: areaId, headingId: headingId, checklist: checklist
        )
    }

    @Test func dropsFieldsThatAlreadyMatch() {
        var attributes = TodoUpdateAttributes()
        attributes.title = "Call"
        attributes.notes = "n"
        attributes.deadline = .clear
        attributes.listId = "p1"
        attributes.checklist = []
        attributes.when = .anytime

        #expect(attributes.removingSatisfied(by: Self.current()).isEmpty)
    }

    @Test func keepsFieldsThatDiffer() {
        var attributes = TodoUpdateAttributes()
        attributes.title = "Call mom"
        attributes.deadline = .set(DateComponents(year: 2026, month: 12, day: 24))
        attributes.headingId = "h1"

        let remaining = attributes.removingSatisfied(by: Self.current())
        #expect(remaining.title == "Call mom")
        #expect(remaining.deadline == .set(DateComponents(year: 2026, month: 12, day: 24)))
        #expect(remaining.headingId == "h1")
    }

    @Test func keepsListWhenHeadingChanges() {
        // list-id alone would drop the heading, so both travel together.
        var attributes = TodoUpdateAttributes()
        attributes.listId = "p1"
        attributes.headingId = "h2"

        let remaining = attributes.removingSatisfied(by: Self.current(headingId: "h1"))
        #expect(remaining.listId == "p1")
        #expect(remaining.headingId == "h2")
    }

    @Test func alwaysKeepsAppendsAndPrepends() {
        var attributes = TodoUpdateAttributes()
        attributes.appendNotes = "x"
        attributes.prependChecklist = ["y"]

        let remaining = attributes.removingSatisfied(by: Self.current())
        #expect(remaining.appendNotes == "x")
        #expect(remaining.prependChecklist == ["y"])
    }

    @Test func dropsTagsAlreadyPresent() {
        var attributes = TodoUpdateAttributes()
        attributes.addTags = ["home"]
        #expect(attributes.removingSatisfied(by: Self.current()).isEmpty)

        attributes.addTags = ["home", "work"]
        #expect(attributes.removingSatisfied(by: Self.current()).addTags == ["home", "work"])
    }

    @Test func whenMatchesByBucketDayEveningAndReminder() {
        let day = DateComponents(year: 2026, month: 11, day: 15)
        var attributes = TodoUpdateAttributes()

        attributes.when = .someday
        #expect(attributes.removingSatisfied(by: Self.current(start: .someday)).isEmpty)
        #expect(!attributes.removingSatisfied(by: Self.current(start: .someday, startDay: day)).isEmpty)

        attributes.when = .day(day)
        #expect(attributes.removingSatisfied(by: Self.current(start: .someday, startDay: day)).isEmpty)

        attributes.when = .dayAndTime(DateComponents(year: 2026, month: 11, day: 15, hour: 9, minute: 30))
        #expect(!attributes.removingSatisfied(by: Self.current(start: .someday, startDay: day)).isEmpty)
        #expect(attributes.removingSatisfied(by: Self.current(
            start: .someday, startDay: day, reminderTime: DateComponents(hour: 9, minute: 30)
        )).isEmpty)

        attributes.when = .evening
        #expect(!attributes.removingSatisfied(by: Self.current(startDay: Self.today)).isEmpty)
        #expect(attributes.removingSatisfied(by: Self.current(startDay: Self.today, isEvening: true)).isEmpty)

        attributes.when = .today
        #expect(attributes.removingSatisfied(by: Self.current(startDay: Self.today)).isEmpty)
    }

    @Test func checklistComparesTitlesAndCompletion() {
        var attributes = TodoUpdateAttributes()
        attributes.checklist = [ChecklistEntry(title: "A", completed: true)]

        #expect(attributes.removingSatisfied(by: Self.current(checklist: [ChecklistEntry(title: "A", completed: true)])).isEmpty)
        #expect(!attributes.removingSatisfied(by: Self.current(checklist: [ChecklistEntry(title: "A")])).isEmpty)
    }
}
