// ThingsDatabaseTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import ClingsCore

/// Integration tests that run real ThingsDatabase queries against controlled SQLite data.
///
/// These tests verify that every query in ThingsDatabase correctly filters,
/// joins, and decodes rows from the Things 3 schema.
final class ThingsDatabaseTests: XCTestCase {

    private var builder: TestDatabaseBuilder!
    private var db: ThingsDatabase!

    override func setUpWithError() throws {
        builder = try TestDatabaseBuilder()
        DatabaseTestFixtures.populateComprehensive(builder)
        db = try ThingsDatabase(databasePath: builder.path)
    }

    override func tearDown() {
        db = nil
        builder = nil
    }

    // MARK: - Inbox

    func testFetchInboxReturnsOnlyInboxTodos() throws {
        let todos = try db.fetchList(.inbox)

        XCTAssertTrue(todos.contains { $0.id == DatabaseTestFixtures.inboxTaskId })
        // Today tasks should not appear in inbox
        XCTAssertFalse(todos.contains { $0.id == DatabaseTestFixtures.todayTaskId })
        // Trashed items excluded
        XCTAssertFalse(todos.contains { $0.id == DatabaseTestFixtures.trashedTaskId })
        // Completed items excluded
        XCTAssertFalse(todos.contains { $0.id == DatabaseTestFixtures.completedTaskId })
        // Projects excluded (type=1)
        XCTAssertFalse(todos.contains { $0.id == DatabaseTestFixtures.projectId })
        // Headings excluded (type=2)
        XCTAssertFalse(todos.contains { $0.id == DatabaseTestFixtures.headingId })
    }

    // MARK: - Today

    func testFetchTodayReturnsTodayTodos() throws {
        let todos = try db.fetchList(.today)
        let ids = todos.map(\.id)

        // start=1 todos should appear
        XCTAssertTrue(ids.contains(DatabaseTestFixtures.todayTaskId))
        // startDate == today should also appear
        XCTAssertTrue(ids.contains(DatabaseTestFixtures.todayStartDateId))
        // Inbox should not appear
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.inboxTaskId))
        // Someday should not appear
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.somedayTaskId))
        // Trashed excluded
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.trashedTaskId))
    }

    // MARK: - Upcoming

    func testFetchUpcomingReturnsFutureStartDates() throws {
        let todos = try db.fetchList(.upcoming)
        let ids = todos.map(\.id)

        XCTAssertTrue(ids.contains(DatabaseTestFixtures.upcomingTaskId))
        // Today's startDate should NOT appear in upcoming
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.todayStartDateId))
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.todayTaskId))
    }

    // MARK: - Anytime

    func testFetchAnytimeReturnsStart1WithoutFutureDate() throws {
        let todos = try db.fetchList(.anytime)
        let ids = todos.map(\.id)

        XCTAssertTrue(ids.contains(DatabaseTestFixtures.anytimeTaskId))
        // Today tasks (with startDate) should NOT appear in anytime
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.todayTaskId))
        // Upcoming (future startDate) should not appear
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.upcomingTaskId))
        // Inbox excluded
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.inboxTaskId))
        // Someday excluded
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.somedayTaskId))
    }

    // MARK: - Someday

    func testFetchSomedayReturnsStart2Only() throws {
        let todos = try db.fetchList(.someday)
        let ids = todos.map(\.id)

        XCTAssertTrue(ids.contains(DatabaseTestFixtures.somedayTaskId))
        // Verify non-someday items are excluded
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.todayTaskId))
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.inboxTaskId))
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.completedTaskId))
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.trashedTaskId))
    }

    // MARK: - Logbook

    func testFetchLogbookReturnsCompletedOnly() throws {
        let todos = try db.fetchList(.logbook)
        let ids = todos.map(\.id)

        XCTAssertTrue(ids.contains(DatabaseTestFixtures.completedTaskId))
        // Canceled tasks have status=2, logbook is status=3
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.canceledTaskId))
        // Open tasks excluded
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.todayTaskId))
    }

    // MARK: - Trash

    func testFetchTrashReturnsTrashedOnly() throws {
        let todos = try db.fetchList(.trash)
        let ids = todos.map(\.id)

        XCTAssertTrue(ids.contains(DatabaseTestFixtures.trashedTaskId))
        // Verify non-trashed items are excluded
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.todayTaskId))
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.completedTaskId))
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.inboxTaskId))
    }

    // MARK: - Trashed Exclusion

    func testTrashedItemsExcludedFromAllNonTrashLists() throws {
        let lists: [ListView] = [.inbox, .today, .upcoming, .anytime, .someday, .logbook]

        for list in lists {
            let todos = try db.fetchList(list)
            XCTAssertFalse(
                todos.contains { $0.id == DatabaseTestFixtures.trashedTaskId },
                "Trashed item appeared in \(list)"
            )
        }
    }

    // MARK: - Canceled Item Exclusion

    func testCanceledItemsExcludedFromOpenLists() throws {
        let lists: [ListView] = [.inbox, .today, .upcoming, .anytime, .someday]

        for list in lists {
            let todos = try db.fetchList(list)
            XCTAssertFalse(
                todos.contains { $0.id == DatabaseTestFixtures.canceledTaskId },
                "Canceled item appeared in \(list)"
            )
        }
    }

    // MARK: - Fetch Single Todo

    func testFetchTodoResolvesProjectAndArea() throws {
        let todo = try db.fetchTodo(id: DatabaseTestFixtures.projectTaskId)

        XCTAssertEqual(todo.name, "Write README")
        XCTAssertNotNil(todo.project)
        XCTAssertEqual(todo.project?.name, "Ship v1.0")
        XCTAssertEqual(todo.project?.area?.name, "Work")
    }

    func testFetchTodoResolvesArea() throws {
        let todo = try db.fetchTodo(id: DatabaseTestFixtures.areaTaskId)

        XCTAssertEqual(todo.area?.name, "Work")
        XCTAssertEqual(todo.area?.id, DatabaseTestFixtures.areaId)
    }

    func testFetchTodoNotFoundThrows() throws {
        XCTAssertThrowsError(try db.fetchTodo(id: "nonexistent-id")) { error in
            XCTAssertTrue(error is ThingsError, "Expected ThingsError, got \(type(of: error))")
        }
    }

    func testFetchTodoWithProjectIdThrowsNotFound() throws {
        // fetchTodo filters type = 0 (todos only), so projects (type=1) are excluded
        XCTAssertThrowsError(try db.fetchTodo(id: DatabaseTestFixtures.projectId)) { error in
            XCTAssertTrue(error is ThingsError, "Expected ThingsError, got \(type(of: error))")
        }
    }

    // MARK: - Tags

    func testFetchTodoResolvesTags() throws {
        let todo = try db.fetchTodo(id: DatabaseTestFixtures.taggedTaskId)

        XCTAssertEqual(todo.tags.count, 2)
        let tagNames = todo.tags.map(\.name).sorted()
        XCTAssertEqual(tagNames, ["low-priority", "urgent"])
    }

    func testFetchTagsReturnsAllTags() throws {
        let tags = try db.fetchTags()

        XCTAssertTrue(tags.count >= 2)
        let names = tags.map(\.name)
        XCTAssertTrue(names.contains("urgent"))
        XCTAssertTrue(names.contains("low-priority"))
    }

    // MARK: - Checklist Items

    func testChecklistItemsLoadInOrder() throws {
        let todo = try db.fetchTodo(id: DatabaseTestFixtures.checklistTaskId)

        XCTAssertEqual(todo.checklistItems.count, 3)
        XCTAssertEqual(todo.checklistItems[0].name, "Run tests")
        XCTAssertEqual(todo.checklistItems[0].completed, true)
        XCTAssertEqual(todo.checklistItems[1].name, "Update docs")
        XCTAssertEqual(todo.checklistItems[1].completed, false)
        XCTAssertEqual(todo.checklistItems[2].name, "Tag release")
        XCTAssertEqual(todo.checklistItems[2].completed, false)
    }

    // MARK: - Recurring

    func testRecurringTodoHasIsRecurringTrue() throws {
        let todo = try db.fetchTodo(id: DatabaseTestFixtures.recurringTaskId)

        XCTAssertTrue(todo.isRecurring)
        XCTAssertEqual(todo.repeatingTemplate, "template-001")
    }

    func testNonRecurringTodoHasIsRecurringFalse() throws {
        let todo = try db.fetchTodo(id: DatabaseTestFixtures.todayTaskId)

        XCTAssertFalse(todo.isRecurring)
        XCTAssertNil(todo.repeatingTemplate)
    }

    // MARK: - Packed Date Decoding

    func testDeadlineDecodesCorrectly() throws {
        let todo = try db.fetchTodo(id: DatabaseTestFixtures.overdueTaskId)

        XCTAssertNotNil(todo.deadlineDate)
        // The deadline was set to 30 days ago
        XCTAssertTrue(todo.isOverdue)
    }

    func testFutureDeadlineDecodesCorrectly() throws {
        let todo = try db.fetchTodo(id: DatabaseTestFixtures.futureDeadlineId)

        XCTAssertNotNil(todo.deadlineDate)
        XCTAssertFalse(todo.isOverdue)
    }

    func testStartDateDecodesCorrectly() throws {
        let todo = try db.fetchTodo(id: DatabaseTestFixtures.upcomingTaskId)

        XCTAssertNotNil(todo.startDate)
        // Should be ~30 days from now
        let daysFromNow = Calendar.current.dateComponents(
            [.day], from: Date(), to: todo.startDate!
        ).day ?? 0
        XCTAssertTrue(daysFromNow >= 29 && daysFromNow <= 31)
    }

    // MARK: - Search

    func testSearchMatchesTitle() throws {
        let results = try db.search(query: "standup")

        XCTAssertTrue(results.contains { $0.id == DatabaseTestFixtures.recurringTaskId })
    }

    func testSearchMatchesNotes() throws {
        let results = try db.search(query: "failing tests")

        XCTAssertTrue(results.contains { $0.id == DatabaseTestFixtures.inboxTaskId })
    }

    func testSearchExcludesTrashedItems() throws {
        let results = try db.search(query: "Trashed")

        XCTAssertFalse(results.contains { $0.id == DatabaseTestFixtures.trashedTaskId })
    }

    // MARK: - Projects

    func testFetchProjectsReturnsType1Only() throws {
        let projects = try db.fetchProjects()
        let ids = projects.map(\.id)

        XCTAssertTrue(ids.contains(DatabaseTestFixtures.projectId))
        // Regular todos (type=0) excluded
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.todayTaskId))
        // Headings (type=2) excluded
        XCTAssertFalse(ids.contains(DatabaseTestFixtures.headingId))
    }

    func testFetchProjectResolvesArea() throws {
        let projects = try db.fetchProjects()
        let project = projects.first { $0.id == DatabaseTestFixtures.projectId }

        XCTAssertNotNil(project)
        XCTAssertEqual(project?.area?.name, "Work")
    }

    // MARK: - Areas

    func testFetchAreasReturnsAll() throws {
        let areas = try db.fetchAreas()

        XCTAssertTrue(areas.contains { $0.id == DatabaseTestFixtures.areaId })
        XCTAssertEqual(areas.first { $0.id == DatabaseTestFixtures.areaId }?.name, "Work")
    }

    // MARK: - Unicode

    func testUnicodeTitleHandledCorrectly() throws {
        let todo = try db.fetchTodo(id: DatabaseTestFixtures.unicodeTaskId)

        XCTAssertTrue(todo.name.contains("\u{1F41B}"))
        XCTAssertNotNil(todo.notes)
        XCTAssertTrue(todo.notes!.contains("\u{4F60}\u{597D}"))
    }

    // MARK: - Edge Cases

    func testEmptyNotesReturnedAsEmptyString() throws {
        let todo = try db.fetchTodo(id: DatabaseTestFixtures.emptyNotesTaskId)

        // Empty string should come through as "" rather than nil
        XCTAssertEqual(todo.notes, "")
    }

    func testLongNotesReturnedFully() throws {
        let todo = try db.fetchTodo(id: DatabaseTestFixtures.longNotesTaskId)

        XCTAssertNotNil(todo.notes)
        XCTAssertTrue(todo.notes!.count > 2000)
    }

    func testCreationDatePopulated() throws {
        let todo = try db.fetchTodo(id: DatabaseTestFixtures.todayTaskId)

        // Should be a reasonable recent date (within last hour)
        let age = Date().timeIntervalSince(todo.creationDate)
        XCTAssertTrue(age < 3600, "Creation date seems too old: \(age)s ago")
    }

    // MARK: - Database Path

    func testDatabasePathProperty() throws {
        XCTAssertEqual(db.path, builder.path)
    }

    // MARK: - fetchHeadings

    /// Builds a fresh DB with one project (long, space-free name) holding two headings.
    ///
    /// The builder must outlive the returned database: its `deinit` deletes the
    /// temp file, so the caller has to keep the returned builder alive.
    private func makeHeadingFixture() throws
        -> (builder: TestDatabaseBuilder, db: ThingsDatabase, projectId: String, projectName: String) {
        let b = try TestDatabaseBuilder()
        let projectName = "CLINGS_VERIFY2_1780760768" // long, no spaces — the regression case
        let projectId = b.addTask(title: projectName, type: 1)
        b.addTask(uuid: "h-1", title: "Týždeň 1", type: 2, project: projectId, index: 0)
        b.addTask(uuid: "h-2", title: "Týždeň 2", type: 2, project: projectId, index: 1)
        let database = try ThingsDatabase(databasePath: b.path)
        return (b, database, projectId, projectName)
    }

    func testFetchHeadingsByUUID() throws {
        let (builder, database, projectId, _) = try makeHeadingFixture()
        withExtendedLifetime(builder) {
            let headings = try? database.fetchHeadings(projectId: projectId)
            XCTAssertEqual(headings?.map(\.title), ["Týždeň 1", "Týždeň 2"])
        }
    }

    /// Regression: a long single-word project name was misclassified as a UUID,
    /// so name resolution never ran and fetchHeadings returned nothing.
    func testFetchHeadingsByLongSpacelessName() throws {
        let (builder, database, _, projectName) = try makeHeadingFixture()
        XCTAssertFalse(projectName.contains(" "))
        XCTAssertGreaterThanOrEqual(projectName.count, 20)

        try withExtendedLifetime(builder) {
            let headings = try database.fetchHeadings(projectId: projectName)
            XCTAssertEqual(headings.map(\.title), ["Týždeň 1", "Týždeň 2"])
        }
    }

    func testFetchHeadingsUnknownProjectReturnsEmpty() throws {
        let (builder, database, _, _) = try makeHeadingFixture()
        try withExtendedLifetime(builder) {
            let headings = try database.fetchHeadings(projectId: "does-not-exist")
            XCTAssertTrue(headings.isEmpty)
        }
    }
}
