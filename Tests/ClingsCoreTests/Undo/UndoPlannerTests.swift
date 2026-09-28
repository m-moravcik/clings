// UndoPlannerTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import ClingsCore

@Suite("UndoPlanner")
struct UndoPlannerTests {
    static func snapshot(
        status: Status = .open,
        start: TodoStart = .anytime,
        startDay: DateComponents? = nil,
        isEvening: Bool = false,
        reminderTime: DateComponents? = nil,
        deadline: DateComponents? = nil,
        projectId: String? = nil,
        areaId: String? = nil,
        headingId: String? = nil
    ) -> TodoSnapshot {
        TodoSnapshot(
            title: "Call", notes: "n", status: status, start: start, startDay: startDay,
            isEvening: isEvening, reminderTime: reminderTime, deadline: deadline,
            tags: ["home"], projectId: projectId, areaId: areaId, headingId: headingId,
            checklist: [ChecklistEntry(title: "A", completed: true)]
        )
    }

    static func entry(_ operation: UndoOperation, _ snapshot: TodoSnapshot? = nil) -> UndoEntry {
        UndoEntry(batchId: nil, operation: operation, todoId: "t1", title: "Call", snapshot: snapshot)
    }

    /// Attributes of the final update step, which carries the restored state.
    static func update(in steps: [UndoStep]) -> TodoUpdateAttributes? {
        for step in steps.reversed() {
            if case .update(_, let attributes) = step { return attributes }
        }
        return nil
    }

    @Test func createIsUndoneByTrashing() throws {
        #expect(try UndoPlanner.steps(for: Self.entry(.create)) == [.trash(todoId: "t1")])
    }

    @Test(arguments: [UndoOperation.complete, .cancel])
    func completeAndCancelAreUndoneByReopening(operation: UndoOperation) throws {
        #expect(try UndoPlanner.steps(for: Self.entry(operation, Self.snapshot())) == [.reopen(todoId: "t1")])
    }

    @Test func reopenIsUndoneByRestoringPreviousStatus() throws {
        #expect(try UndoPlanner.steps(for: Self.entry(.reopen, Self.snapshot(status: .completed)))
                == [.complete(todoId: "t1")])
        #expect(try UndoPlanner.steps(for: Self.entry(.reopen, Self.snapshot(status: .canceled)))
                == [.cancel(todoId: "t1")])
    }

    @Test func snapshotRequiredForRestoringOperations() {
        #expect(throws: (any Error).self) { try UndoPlanner.steps(for: Self.entry(.update)) }
        #expect(throws: (any Error).self) { try UndoPlanner.steps(for: Self.entry(.delete)) }
    }

    @Suite("Delete")
    struct Delete {
        @Test(arguments: [(TodoStart.inbox, "Inbox"), (.anytime, "Anytime"), (.someday, "Someday")])
        func movesBackToOriginalList(start: TodoStart, list: String) throws {
            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(.delete, UndoPlannerTests.snapshot(start: start)))
            #expect(steps == [.moveToList(todoId: "t1", list: list)])
            #expect(!UndoPlanner.requiresAuthToken(steps))
        }

        @Test(arguments: [(Status.completed, UndoStep.complete(todoId: "t1")), (.canceled, .cancel(todoId: "t1"))])
        func restoresLoggedStatusAfterUntrashing(status: Status, expected: UndoStep) throws {
            // Moving out of the Trash reopens the to-do (verified against Things 3.24).
            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(.delete, UndoPlannerTests.snapshot(status: status)))
            #expect(steps == [.moveToList(todoId: "t1", list: "Anytime"), expected])
        }

        @Test func restoresScheduleAfterUntrashing() throws {
            let day = DateComponents(year: 2026, month: 11, day: 15)
            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(
                .delete, UndoPlannerTests.snapshot(start: .someday, startDay: day)
            ))

            #expect(steps.first == .moveToList(todoId: "t1", list: "Someday"))
            var expected = TodoUpdateAttributes()
            expected.when = .day(day)
            #expect(UndoPlannerTests.update(in: steps) == expected)
        }
    }

    @Suite("Update")
    struct Update {
        @Test func sendsNothingWhenTheTodoAlreadyMatches() throws {
            let snapshot = UndoPlannerTests.snapshot(projectId: "p1")
            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(.update, snapshot), current: snapshot)
            #expect(steps.isEmpty)
        }

        @Test func sendsOnlyWhatChanged() throws {
            let snapshot = UndoPlannerTests.snapshot(projectId: "p1")
            var current = snapshot
            current.title = "Renamed"
            current.tags = ["home", "extra"]

            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(.update, snapshot), current: current)
            var expected = TodoUpdateAttributes()
            expected.title = "Call"
            #expect(steps == [.setTags(todoId: "t1", tags: ["home"]), .update(todoId: "t1", attributes: expected)])
        }

        @Test func clearsReminderOnlyWhenOneIsSet() throws {
            let day = DateComponents(year: 2026, month: 11, day: 15)
            let snapshot = UndoPlannerTests.snapshot(start: .someday, startDay: day, projectId: "p1")
            var current = snapshot
            current.reminderTime = DateComponents(hour: 8, minute: 15)

            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(.update, snapshot), current: current)
            var clear = TodoUpdateAttributes()
            clear.when = .someday
            var restore = TodoUpdateAttributes()
            restore.when = .day(day)
            #expect(steps == [.update(todoId: "t1", attributes: clear), .update(todoId: "t1", attributes: restore)])
        }

        @Test func restoresEveryFieldInsideAProject() throws {
            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(
                .update, UndoPlannerTests.snapshot(projectId: "p1", headingId: "h1")
            ))

            let attributes = try #require(UndoPlannerTests.update(in: steps))
            #expect(attributes.title == "Call")
            #expect(attributes.notes == "n")
            // `tags: []` does not clear tags through the json command; AppleScript does.
            #expect(attributes.tags == nil)
            #expect(steps.contains(.setTags(todoId: "t1", tags: ["home"])))
            #expect(attributes.deadline == .clear)
            #expect(attributes.listId == "p1")
            #expect(attributes.headingId == "h1")
            #expect(attributes.when == .anytime)
            #expect(attributes.checklist == [ChecklistEntry(title: "A", completed: true)])
            #expect(UndoPlanner.requiresAuthToken(steps))
        }

        @Test func areaIsUsedAsListWhenNoProject() throws {
            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(.update, UndoPlannerTests.snapshot(areaId: "a1")))
            #expect(UndoPlannerTests.update(in: steps)?.listId == "a1")
        }

        @Test func looseInboxTodoIsDetachedThroughInbox() throws {
            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(.update, UndoPlannerTests.snapshot(start: .inbox)))

            #expect(steps.first == .moveToList(todoId: "t1", list: "Inbox"))
            let attributes = try #require(UndoPlannerTests.update(in: steps))
            #expect(attributes.listId == nil)
            #expect(attributes.when == nil)
        }

        @Test func looseSomedayTodoGoesThroughInboxThenSomeday() throws {
            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(.update, UndoPlannerTests.snapshot(start: .someday)))

            #expect(Array(steps.prefix(2)) == [
                .moveToList(todoId: "t1", list: "Inbox"),
                .moveToList(todoId: "t1", list: "Someday"),
            ])
        }

        @Test func restoresDeadlineDay() throws {
            let deadline = DateComponents(year: 2026, month: 12, day: 24)
            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(
                .update, UndoPlannerTests.snapshot(deadline: deadline, projectId: "p1")
            ))
            #expect(UndoPlannerTests.update(in: steps)?.deadline == .set(deadline))
        }

        @Test func clearsReminderBeforeRestoringAPlainDay() throws {
            // Setting only a day keeps any reminder Things already has; moving through
            // Someday clears it (verified against Things 3.24).
            let day = DateComponents(year: 2026, month: 11, day: 15)
            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(
                .update, UndoPlannerTests.snapshot(start: .someday, startDay: day, projectId: "p1")
            ))

            var clear = TodoUpdateAttributes()
            clear.when = .someday
            let clearIndex = try #require(steps.firstIndex(of: .update(todoId: "t1", attributes: clear)))
            let restoreIndex = try #require(steps.lastIndex { step in
                if case .update(_, let attributes) = step { return attributes.when == .day(day) }
                return false
            })
            #expect(clearIndex < restoreIndex)
        }

        @Test func restoresReminderTime() throws {
            let day = DateComponents(year: 2026, month: 10, day: 1)
            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(.update, UndoPlannerTests.snapshot(
                startDay: day, reminderTime: DateComponents(hour: 9, minute: 30), projectId: "p1"
            )))
            #expect(UndoPlannerTests.update(in: steps)?.when
                    == .dayAndTime(DateComponents(year: 2026, month: 10, day: 1, hour: 9, minute: 30)))
        }

        @Test func restoresEveningForToday() throws {
            let today = ThingsDateConverter.calendar.dateComponents([.year, .month, .day], from: Date())
            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(.update, UndoPlannerTests.snapshot(
                startDay: today, isEvening: true, projectId: "p1"
            )))
            #expect(UndoPlannerTests.update(in: steps)?.when == .evening)
        }

        @Test func restoresSomedayBucketInsideProject() throws {
            let steps = try UndoPlanner.steps(for: UndoPlannerTests.entry(
                .update, UndoPlannerTests.snapshot(start: .someday, projectId: "p1")
            ))
            #expect(UndoPlannerTests.update(in: steps)?.when == .someday)
        }
    }
}
