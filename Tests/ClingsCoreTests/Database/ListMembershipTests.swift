// ListMembershipTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import ClingsCore

/// Verifies that list membership mirrors what Things 3 itself shows.
///
/// The rules were derived by diffing clings output against the lists Things
/// returns over AppleScript on a real database (Things 3.24):
/// - repeating templates (`rt1_recurrenceRule` set) only show up in Upcoming
/// - descendants of Someday, completed or trashed projects are hidden, both
///   when filed directly under the project and when filed under a heading
/// - Someday lists only loose todos, never todos inside projects
/// - Upcoming also lists Anytime todos with a future deadline
final class ListMembershipTests: XCTestCase {

    private var builder: TestDatabaseBuilder!

    override func setUpWithError() throws {
        builder = try TestDatabaseBuilder()
    }

    override func tearDown() {
        builder = nil
    }

    private func database() throws -> ThingsDatabase {
        try ThingsDatabase(databasePath: builder.path)
    }

    private func ids(_ list: ListView) throws -> Set<String> {
        Set(try database().fetchList(list).map(\.id))
    }

    private func packed(daysFromToday offset: Int) -> Int {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return ThingsDateConverter.encodeDate(date)
    }

    // MARK: - Repeating templates

    func testRepeatingTemplateAppearsInUpcoming() throws {
        builder.addTask(uuid: "tmpl", title: "Call mom", start: 2, isRepeatingTemplate: true)

        XCTAssertTrue(try ids(.upcoming).contains("tmpl"))
    }

    func testRepeatingTemplateIsHiddenFromOtherLists() throws {
        builder.addTask(uuid: "tmpl", title: "Call mom", start: 2, isRepeatingTemplate: true)
        builder.addTask(uuid: "tmpl-anytime", title: "Water plants", start: 1, isRepeatingTemplate: true)

        for list in [ListView.inbox, .today, .anytime, .someday] {
            let listIds = try ids(list)
            XCTAssertFalse(listIds.contains("tmpl"), "template leaked into \(list)")
            XCTAssertFalse(listIds.contains("tmpl-anytime"), "template leaked into \(list)")
        }
    }

    func testRepeatingTemplateIsRecurring() throws {
        builder.addTask(uuid: "tmpl", title: "Call mom", start: 2, isRepeatingTemplate: true)

        XCTAssertTrue(try database().fetchTodo(id: "tmpl").isRecurring)
    }

    func testRepeatingTemplateSentinelDeadlineIsIgnored() throws {
        // Templates with a relative deadline store year 4001 as a sentinel.
        builder.addTask(
            uuid: "tmpl", title: "Pay rent", start: 2,
            deadline: ThingsDateConverter.encode(year: 4001, month: 1, day: 1),
            isRepeatingTemplate: true
        )

        let todo = try database().fetchTodo(id: "tmpl")
        XCTAssertNil(todo.deadlineDate)
        XCTAssertFalse(todo.isOverdue)
    }

    // MARK: - Someday projects

    func testTodoInSomedayProjectIsHiddenFromAnytime() throws {
        builder.addTask(uuid: "proj", title: "Later project", type: 1, start: 2)
        builder.addTask(uuid: "child", title: "Child", start: 1, project: "proj")

        XCTAssertFalse(try ids(.anytime).contains("child"))
    }

    func testTodoUnderHeadingOfSomedayProjectIsHiddenFromAnytime() throws {
        builder.addTask(uuid: "proj", title: "Later project", type: 1, start: 2)
        builder.addTask(uuid: "head", title: "Phase 1", type: 2, start: 1, project: "proj")
        builder.addTask(uuid: "child", title: "Child", start: 1, heading: "head")

        XCTAssertFalse(try ids(.anytime).contains("child"))
    }

    func testTodoInActiveProjectAppearsInAnytime() throws {
        builder.addTask(uuid: "proj", title: "Active project", type: 1, start: 1)
        builder.addTask(uuid: "child", title: "Child", start: 1, project: "proj")

        XCTAssertTrue(try ids(.anytime).contains("child"))
    }

    // MARK: - Closed and trashed projects

    func testTodoInTrashedProjectIsHiddenFromOpenLists() throws {
        builder.addTask(uuid: "proj", title: "Trashed project", type: 1, trashed: 1, start: 1)
        builder.addTask(uuid: "child", title: "Child", start: 1, project: "proj")

        XCTAssertFalse(try ids(.anytime).contains("child"))
        XCTAssertFalse(try database().fetchAllOpen().contains { $0.id == "child" })
        XCTAssertFalse(try database().search(query: "Child").contains { $0.id == "child" })
    }

    func testTodoUnderHeadingOfTrashedProjectIsHiddenFromOpenLists() throws {
        builder.addTask(uuid: "proj", title: "Trashed project", type: 1, trashed: 1, start: 1)
        builder.addTask(uuid: "head", title: "Phase 1", type: 2, start: 1, project: "proj")
        builder.addTask(uuid: "child", title: "Child", start: 1, heading: "head")

        XCTAssertFalse(try ids(.anytime).contains("child"))
        XCTAssertFalse(try database().search(query: "Child").contains { $0.id == "child" })
    }

    func testOpenTodoInCompletedProjectIsHiddenFromAnytime() throws {
        builder.addTask(uuid: "proj", title: "Done project", type: 1, status: 3, start: 1)
        builder.addTask(uuid: "child", title: "Child", start: 1, project: "proj")

        XCTAssertFalse(try ids(.anytime).contains("child"))
    }

    // MARK: - Someday

    func testSomedayExcludesTodosInsideProjects() throws {
        builder.addTask(uuid: "proj", title: "Active project", type: 1, start: 1)
        builder.addTask(uuid: "head", title: "Phase 1", type: 2, start: 1, project: "proj")
        builder.addTask(uuid: "direct", title: "Direct", start: 2, project: "proj")
        builder.addTask(uuid: "under-heading", title: "Under heading", start: 2, heading: "head")
        builder.addTask(uuid: "loose", title: "Loose", start: 2)

        let someday = try ids(.someday)
        XCTAssertEqual(someday, ["loose"])
    }

    func testSomedayExcludesScheduledTodos() throws {
        builder.addTask(uuid: "scheduled", title: "Scheduled", start: 2, startDate: packed(daysFromToday: 5))

        XCTAssertFalse(try ids(.someday).contains("scheduled"))
        XCTAssertTrue(try ids(.upcoming).contains("scheduled"))
    }

    // MARK: - Upcoming

    func testUpcomingIncludesAnytimeTodoWithFutureDeadline() throws {
        builder.addTask(uuid: "due-later", title: "Due later", start: 1, deadline: packed(daysFromToday: 10))

        XCTAssertTrue(try ids(.upcoming).contains("due-later"))
    }

    func testUpcomingExcludesAnytimeTodoWithPastDeadline() throws {
        builder.addTask(uuid: "overdue", title: "Overdue", start: 1, deadline: packed(daysFromToday: -3))

        XCTAssertFalse(try ids(.upcoming).contains("overdue"))
    }

    // MARK: - Today

    func testTodayIncludesScheduledTodoWhoseDateHasArrived() throws {
        // Things flips start 2 -> 1 at day rollover; until it runs, the row keeps start = 2.
        builder.addTask(uuid: "arrived", title: "Arrived", start: 2, startDate: packed(daysFromToday: 0))

        XCTAssertTrue(try ids(.today).contains("arrived"))
    }

    func testTodayIncludesTodoWithDueDeadline() throws {
        builder.addTask(uuid: "due", title: "Due", start: 1, deadline: packed(daysFromToday: 0))

        XCTAssertTrue(try ids(.today).contains("due"))
    }

    // MARK: - Heading to project resolution

    func testTodoUnderHeadingResolvesParentProject() throws {
        builder.addTask(uuid: "proj", title: "Month #3", type: 1, start: 1)
        builder.addTask(uuid: "head", title: "Family", type: 2, start: 1, project: "proj")
        builder.addTask(uuid: "child", title: "Child", start: 1, heading: "head")

        let fetched = try database().fetchTodo(id: "child")
        XCTAssertEqual(fetched.project?.name, "Month #3")
        XCTAssertEqual(fetched.heading, "Family")

        let listed = try database().fetchList(.anytime).first { $0.id == "child" }
        XCTAssertEqual(listed?.project?.name, "Month #3")
    }

    // MARK: - Scheduling details

    func testTodoExposesStartEveningReminderAndHeadingId() throws {
        builder.addTask(uuid: "proj", title: "Project", type: 1, start: 1)
        builder.addTask(uuid: "head", title: "Phase 1", type: 2, start: 1, project: "proj")
        builder.addTask(
            uuid: "child", title: "Child", start: 1, startDate: packed(daysFromToday: 0),
            heading: "head", startBucket: 1, reminderTime: (9 << 26) | (30 << 20)
        )
        builder.addTask(uuid: "later", title: "Later", start: 2)
        builder.addTask(uuid: "inbox", title: "Inbox", start: 0)

        let child = try database().fetchTodo(id: "child")
        XCTAssertEqual(child.start, .anytime)
        XCTAssertTrue(child.isEvening)
        XCTAssertEqual(child.reminderTime, DateComponents(hour: 9, minute: 30))
        XCTAssertEqual(child.headingId, "head")
        XCTAssertEqual(try database().fetchTodo(id: "later").start, .someday)
        XCTAssertEqual(try database().fetchTodo(id: "inbox").start, .inbox)
        XCTAssertNil(try database().fetchTodo(id: "inbox").reminderTime)
        XCTAssertFalse(try database().fetchTodo(id: "inbox").isEvening)
    }

    // MARK: - Completion date

    func testLogbookExposesCompletionDate() throws {
        builder.addTask(uuid: "done", title: "Done", status: 3, start: 1, stopDate: 1_790_000_000.5)
        builder.addTask(uuid: "open", title: "Open", start: 1)

        let done = try XCTUnwrap(try database().fetchList(.logbook).first { $0.id == "done" })
        XCTAssertEqual(done.completionDate, Date(timeIntervalSince1970: 1_790_000_000.5))
        XCTAssertNil(try database().fetchTodo(id: "open").completionDate)
    }

    // MARK: - Modification date

    func testModificationDateOfTodoAndProject() throws {
        builder.addTask(uuid: "todo", title: "Todo", start: 1, userModificationDate: 1_790_000_000.25)
        builder.addTask(uuid: "proj", title: "Project", type: 1, start: 1, userModificationDate: 1_790_000_001.5)

        XCTAssertEqual(try database().modificationDate(of: "todo"), Date(timeIntervalSince1970: 1_790_000_000.25))
        XCTAssertEqual(try database().modificationDate(of: "proj"), Date(timeIntervalSince1970: 1_790_000_001.5))
        XCTAssertNil(try database().modificationDate(of: "missing"))
    }

    func testIsTrashed() throws {
        builder.addTask(uuid: "live", title: "Live", start: 1)
        builder.addTask(uuid: "binned", title: "Binned", trashed: 1, start: 1)

        XCTAssertFalse(try database().isTrashed("live"))
        XCTAssertTrue(try database().isTrashed("binned"))
        XCTAssertFalse(try database().isTrashed("missing"))
    }

    // MARK: - Name to ID resolution

    func testResolveProjectIdPrefersOpenProjectWithSameTitle() throws {
        builder.addTask(uuid: "old", title: "Month #3", type: 1, status: 3, start: 1)
        builder.addTask(uuid: "tmpl", title: "Month #3", type: 1, start: 2, isRepeatingTemplate: true)
        builder.addTask(uuid: "trashed", title: "Month #3", type: 1, trashed: 1, start: 1)
        builder.addTask(uuid: "current", title: "Month #3", type: 1, start: 1)

        XCTAssertEqual(try database().resolveProjectId("Month #3"), "current")
    }

    func testResolveProjectIdIgnoresTrashedProjectsAndTemplates() throws {
        builder.addTask(uuid: "trashed", title: "Gone", type: 1, trashed: 1, start: 1)
        builder.addTask(uuid: "tmpl", title: "Weekly", type: 1, start: 2, isRepeatingTemplate: true)

        // A todo filed into a trashed project would be invisible everywhere.
        XCTAssertNil(try database().resolveProjectId("Gone"))
        XCTAssertNil(try database().resolveProjectId("trashed"))
        XCTAssertNil(try database().resolveProjectId("Weekly"))
    }

    func testResolveProjectIdAcceptsId() throws {
        builder.addTask(uuid: "P1", title: "Project", type: 1, start: 1)

        XCTAssertEqual(try database().resolveProjectId("P1"), "P1")
    }

    func testResolveProjectIdReturnsNilForUnknown() throws {
        builder.addTask(uuid: "todo", title: "Not a project", start: 1)

        XCTAssertNil(try database().resolveProjectId("Nope"))
        XCTAssertNil(try database().resolveProjectId("todo"))
    }

    func testResolveAreaIdByTitleOrId() throws {
        builder.addArea(uuid: "A1", title: "Work")

        XCTAssertEqual(try database().resolveAreaId("Work"), "A1")
        XCTAssertEqual(try database().resolveAreaId("A1"), "A1")
        XCTAssertNil(try database().resolveAreaId("Home"))
    }

    func testResolveHeadingIdWithinProject() throws {
        builder.addTask(uuid: "P1", title: "Project", type: 1, start: 1)
        builder.addTask(uuid: "P2", title: "Other", type: 1, start: 1)
        builder.addTask(uuid: "H1", title: "Week 1", type: 2, start: 1, project: "P1")
        builder.addTask(uuid: "H2", title: "Week 1", type: 2, start: 1, project: "P2")

        XCTAssertEqual(try database().resolveHeadingId("Week 1", projectId: "P2"), "H2")
        XCTAssertEqual(try database().resolveHeadingId("H1", projectId: "P1"), "H1")
        XCTAssertNil(try database().resolveHeadingId("Week 9", projectId: "P1"))
    }

    // MARK: - Projects

    func testFetchProjectsExcludesRepeatingProjectTemplates() throws {
        builder.addTask(uuid: "proj-tmpl", title: "Weekly review", type: 1, start: 2, isRepeatingTemplate: true)
        builder.addTask(uuid: "proj-inst", title: "Weekly review", type: 1, start: 1)

        let projectIds = try database().fetchProjects().map(\.id)
        XCTAssertEqual(projectIds, ["proj-inst"])
    }
}
