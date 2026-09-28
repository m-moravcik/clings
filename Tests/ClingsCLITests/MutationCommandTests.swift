// MutationCommandTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import ClingsCLI
@testable import ClingsCore

// These tests extend the serialized "Command Execution" suite: they share the
// global client override and stdout capture, so they must not run in parallel.

final class URLRecorder: @unchecked Sendable {
    var urls: [String] = []
}

/// Run `body` with URL opening captured and a fixed (or missing) auth token.
private func withURLScheme(
    token: String? = "tok",
    outcome: ChangeConfirmation.Outcome = .applied,
    _ body: () async throws -> Void
) async throws -> [String] {
    let recorder = URLRecorder()
    try await CommandRuntime.$openURLScheme.withValue({ url in recorder.urls.append(url) }) {
        try await CommandRuntime.$watchForChange.withValue({ _ in { outcome } }) {
            try await CommandRuntime.$loadAuthToken.withValue({
                guard let token else { throw ThingsError.invalidState("no token") }
                return token
            }) {
                try await body()
            }
        }
    }
    return recorder.urls
}

/// Attributes of the single operation in a `things:///json` URL.
private func jsonAttributes(_ url: String) throws -> (id: String?, attributes: [String: Any]) {
    let components = try #require(URLComponents(string: url))
    let data = try #require(components.queryItems?.first { $0.name == "data" }?.value)
    let operations = try #require(try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [[String: Any]])
    let operation = try #require(operations.first)
    return (operation["id"] as? String, try #require(operation["attributes"] as? [String: Any]))
}

private func firstUpdate(_ urls: [String]) throws -> (id: String?, attributes: [String: Any]) {
    guard let url = urls.first else { throw ThingsError.invalidState("no URL was opened") }
    return try jsonAttributes(url)
}

private func firstQuery(_ urls: [String]) throws -> [String: String] {
    guard let url = urls.first else { throw ThingsError.invalidState("no URL was opened") }
    return try query(url)
}

private func query(_ url: String) throws -> [String: String] {
    let components = try #require(URLComponents(string: url))
    var map: [String: String] = [:]
    for item in components.queryItems ?? [] { map[item.name] = item.value }
    return map
}

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    ThingsDateConverter.calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
}

private let project = Project(id: "P1", name: "Alpha", status: .open)
private let openTodo = Todo(
    id: "todo-1", name: "Buy milk", notes: "2%", status: .open, tags: [Tag(name: "home")],
    project: project, start: .anytime
)
private let doneTodo = Todo(id: "todo-done", name: "Done task", status: .completed, start: .anytime)

private func latestUndo() throws -> [UndoEntry] {
    try #require(UndoRecorder.storeOverride).latestGroup()
}

extension CommandExecutionTests {

    // MARK: - add

    @Test func addPrintsCreatedId() async throws {
        _ = setupMock()
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try AddCommand.parse(["Buy bread"])
            try await cmd.run()
        }

        #expect(output.contains("mock-0"))
    }

    @Test func addJSONIncludesId() async throws {
        _ = setupMock()
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try AddCommand.parse(["Buy bread", "--json"])
            try await cmd.run()
        }

        #expect(output.contains("\"id\" : \"mock-0\""))
    }

    @Test func addRejectsUnparseableWhenWithoutCreating() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }

        await #expect(throws: (any Error).self) {
            var cmd = try AddCommand.parse(["Task", "--when", "blorp"])
            try await cmd.run()
        }
        #expect(mock.createdTodos.isEmpty)
    }

    @Test func addRejectsUnparseableDeadlineWithoutCreating() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }

        await #expect(throws: (any Error).self) {
            var cmd = try AddCommand.parse(["Task", "--deadline", "whenever"])
            try await cmd.run()
        }
        #expect(mock.createdTodos.isEmpty)
    }

    @Test func addPassesIsoWhenAndDeadline() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try AddCommand.parse(["Task", "--when", "2026-11-15", "--deadline", "2026-12-24"])
            try await cmd.run()
        }

        let args = try #require(mock.createdTodoArgs.first)
        #expect(args.when == day(2026, 11, 15))
        #expect(args.deadline == day(2026, 12, 24))
    }

    @Test func addSomedayMovesToSomedayList() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try AddCommand.parse(["Task", "--when", "someday"])
            try await cmd.run()
        }

        #expect(mock.movedToList.map(\.list) == ["Someday"])
        #expect(mock.createdTodoArgs.first?.when == nil)
    }

    @Test func addEveningAppliesURLUpdateAfterCreating() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }

        let urls = try await withURLScheme {
            _ = try await capture {
                var cmd = try AddCommand.parse(["Task", "--when", "evening"])
                try await cmd.run()
            }
        }

        #expect(mock.createdTodos.count == 1)
        let update = try firstUpdate(urls)
        #expect(update.id == "mock-0")
        #expect(update.attributes["when"] as? String == "evening")
    }

    @Test func addWithReminderTimeSendsDayAndTime() async throws {
        _ = setupMock()
        defer { ThingsClientFactory.override = nil }

        let urls = try await withURLScheme {
            _ = try await capture {
                var cmd = try AddCommand.parse(["Task", "--when", "2026-10-01@14:00"])
                try await cmd.run()
            }
        }

        #expect(try firstUpdate(urls).attributes["when"] as? String == "2026-10-01@14:00")
    }

    @Test func addUnderHeadingUsesHeadingId() async throws {
        let mock = setupMock {
            $0.headingsByProject["Alpha"] = [Heading(id: "H1", title: "Week 1", projectId: "P1")]
        }
        defer { ThingsClientFactory.override = nil }

        let urls = try await withURLScheme {
            _ = try await capture {
                var cmd = try AddCommand.parse(["Task", "--project", "Alpha", "--heading", "Week 1"])
                try await cmd.run()
            }
        }

        #expect(mock.createdTodoArgs.first?.project == "Alpha")
        let update = try firstUpdate(urls)
        #expect(update.attributes["heading-id"] as? String == "H1")
    }

    @Test func addChecklistGoesThroughURLSchemeNotAppleScript() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }

        let urls = try await withURLScheme {
            _ = try await capture {
                var cmd = try AddCommand.parse(["Pack - socks - shoes"])
                try await cmd.run()
            }
        }

        #expect(mock.createdTodoArgs.first?.checklistItems == [])
        let items = try #require(try firstUpdate(urls).attributes["checklist-items"] as? [[String: Any]])
        #expect(items.count == 2)
    }

    @Test func addFailsBeforeCreatingWhenTokenMissing() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }

        await #expect(throws: (any Error).self) {
            _ = try await withURLScheme(token: nil) {
                var cmd = try AddCommand.parse(["Task", "--when", "evening"])
                try await cmd.run()
            }
        }
        #expect(mock.createdTodos.isEmpty)
    }

    @Test func addRecordsUndoEntry() async throws {
        _ = setupMock()
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try AddCommand.parse(["Task"])
            try await cmd.run()
        }

        let entry = try #require(try latestUndo().first)
        #expect(entry.operation == .create)
        #expect(entry.todoId == "mock-0")
    }

    // MARK: - update

    @Test func updateRecordsSnapshotForUndo() async throws {
        let mock = setupMock { $0.todoById["todo-1"] = openTodo }
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try UpdateCommand.parse(["todo-1", "--name", "Buy oat milk"])
            try await cmd.run()
        }

        #expect(mock.updatedTodos.first?.name == "Buy oat milk")
        let entry = try #require(try latestUndo().first)
        #expect(entry.operation == .update)
        #expect(entry.snapshot?.title == "Buy milk")
        #expect(entry.snapshot?.projectId == "P1")
    }

    @Test func updateWhenWithTimeSendsReminder() async throws {
        _ = setupMock { $0.todoById["todo-1"] = openTodo }
        defer { ThingsClientFactory.override = nil }

        let urls = try await withURLScheme {
            _ = try await capture {
                var cmd = try UpdateCommand.parse(["todo-1", "--when", "2026-10-01@14:00"])
                try await cmd.run()
            }
        }

        let update = try firstUpdate(urls)
        #expect(update.id == "todo-1")
        #expect(update.attributes["when"] as? String == "2026-10-01@14:00")
    }

    @Test func updateFailsWhenThingsIgnoresTheChange() async throws {
        _ = setupMock { $0.todoById["todo-1"] = openTodo }
        defer { ThingsClientFactory.override = nil }

        await #expect(throws: (any Error).self) {
            _ = try await withURLScheme(outcome: .notApplied) {
                _ = try await capture {
                    var cmd = try UpdateCommand.parse(["todo-1", "--append-notes", "x"])
                    try await cmd.run()
                }
            }
        }
    }

    @Test func addReportsIdWhenFollowUpIsIgnored() async throws {
        _ = setupMock()
        defer { ThingsClientFactory.override = nil }

        await #expect {
            _ = try await withURLScheme(outcome: .notApplied) {
                _ = try await capture {
                    var cmd = try AddCommand.parse(["Task", "--when", "evening"])
                    try await cmd.run()
                }
            }
        } throws: { error in
            error.localizedDescription.contains("mock-0")
        }
    }

    @Test func updateAppendsNotesAndAddsTags() async throws {
        _ = setupMock { $0.todoById["todo-1"] = openTodo }
        defer { ThingsClientFactory.override = nil }

        let urls = try await withURLScheme {
            _ = try await capture {
                var cmd = try UpdateCommand.parse([
                    "todo-1", "--append-notes", "more", "--prepend-notes", "top", "--add-tags", "a", "b",
                ])
                try await cmd.run()
            }
        }

        let attributes = try firstUpdate(urls).attributes
        #expect(attributes["append-notes"] as? String == "more")
        #expect(attributes["prepend-notes"] as? String == "top")
        #expect(attributes["add-tags"] as? [String] == ["a", "b"])
    }

    @Test func updateClearDeadlineSendsEmptyValue() async throws {
        var withDeadline = openTodo
        withDeadline.deadlineDate = day(2026, 12, 24)
        _ = setupMock { $0.todoById["todo-1"] = withDeadline }
        defer { ThingsClientFactory.override = nil }

        let urls = try await withURLScheme {
            _ = try await capture {
                var cmd = try UpdateCommand.parse(["todo-1", "--clear-deadline"])
                try await cmd.run()
            }
        }

        #expect(try firstUpdate(urls).attributes["deadline"] as? String == "")
    }

    @Test func updateRejectsDeadlineTogetherWithClearDeadline() async throws {
        _ = setupMock { $0.todoById["todo-1"] = openTodo }
        defer { ThingsClientFactory.override = nil }

        await #expect(throws: (any Error).self) {
            var cmd = try UpdateCommand.parse(["todo-1", "--deadline", "2026-12-24", "--clear-deadline"])
            try await cmd.run()
        }
    }

    @Test func updateAcceptsDeadlineInNaturalLanguage() async throws {
        let mock = setupMock { $0.todoById["todo-1"] = openTodo }
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try UpdateCommand.parse(["todo-1", "--deadline", "2026-12-24"])
            try await cmd.run()
        }

        #expect(mock.updatedTodos.first?.deadline == day(2026, 12, 24))
    }

    // MARK: - complete / cancel / reopen / delete

    @Test func completeRecordsUndo() async throws {
        _ = setupMock { $0.todoById["todo-1"] = openTodo }
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try CompleteCommand.parse(["todo-1"])
            try await cmd.run()
        }

        #expect(try latestUndo().first?.operation == .complete)
    }

    @Test func reopenRecordsPreviousStatus() async throws {
        _ = setupMock { $0.todoById["todo-done"] = doneTodo }
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try ReopenCommand.parse(["todo-done"])
            try await cmd.run()
        }

        let entry = try #require(try latestUndo().first)
        #expect(entry.operation == .reopen)
        #expect(entry.snapshot?.status == .completed)
    }

    @Test func deleteRecordsSnapshot() async throws {
        let mock = setupMock { $0.todoById["todo-1"] = openTodo }
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try DeleteCommand.parse(["todo-1"])
            try await cmd.run()
        }

        #expect(mock.deletedIds == ["todo-1"])
        let entry = try #require(try latestUndo().first)
        #expect(entry.operation == .delete)
        #expect(entry.snapshot?.start == .anytime)
    }

    // MARK: - undo

    @Test func undoCreateTrashesTheTodo() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }
        try UndoRecorder.storeOverride?.record([
            UndoEntry(batchId: nil, operation: .create, todoId: "new-1", title: "New", snapshot: nil),
        ])

        _ = try await capture {
            var cmd = try UndoCommand.parse([])
            try await cmd.run()
        }

        #expect(mock.deletedIds == ["new-1"])
        #expect(try latestUndo().isEmpty)
    }

    @Test func undoBatchReopensEveryTodo() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }
        let batch = UUID()
        try UndoRecorder.storeOverride?.record([
            UndoEntry(batchId: batch, operation: .complete, todoId: "a", title: "A", snapshot: nil),
            UndoEntry(batchId: batch, operation: .complete, todoId: "b", title: "B", snapshot: nil),
        ])

        _ = try await capture {
            var cmd = try UndoCommand.parse([])
            try await cmd.run()
        }

        #expect(Set(mock.reopenedIds) == ["a", "b"])
    }

    @Test func undoUpdateRestoresThroughURLScheme() async throws {
        _ = setupMock()
        defer { ThingsClientFactory.override = nil }
        try UndoRecorder.storeOverride?.record([
            UndoEntry(batchId: nil, operation: .update, todoId: "todo-1", title: "Buy milk",
                      snapshot: TodoSnapshot(todo: openTodo)),
        ])

        let urls = try await withURLScheme {
            _ = try await capture {
                var cmd = try UndoCommand.parse([])
                try await cmd.run()
            }
        }

        let update = try firstUpdate(urls)
        #expect(update.id == "todo-1")
        #expect(update.attributes["title"] as? String == "Buy milk")
        #expect(update.attributes["list-id"] as? String == "P1")
    }

    @Test func undoOfAnUnchangedTodoSendsNothing() async throws {
        _ = setupMock { $0.todoById["todo-1"] = openTodo }
        defer { ThingsClientFactory.override = nil }
        try UndoRecorder.storeOverride?.record([
            UndoEntry(batchId: nil, operation: .update, todoId: "todo-1", title: "Buy milk",
                      snapshot: TodoSnapshot(todo: openTodo)),
        ])

        let urls = try await withURLScheme(outcome: .notApplied) {
            _ = try await capture {
                var cmd = try UndoCommand.parse([])
                try await cmd.run()
            }
        }

        #expect(urls.isEmpty)
        #expect(try latestUndo().isEmpty)
    }

    @Test func updateSkipsChangesThatAlreadyHold() async throws {
        _ = setupMock { $0.todoById["todo-1"] = openTodo }
        defer { ThingsClientFactory.override = nil }

        let urls = try await withURLScheme(outcome: .notApplied) {
            _ = try await capture {
                var cmd = try UpdateCommand.parse(["todo-1", "--add-tags", "home"])
                try await cmd.run()
            }
        }

        #expect(urls.isEmpty)
    }

    @Test func undoDeleteMovesTodoBackToItsList() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }
        try UndoRecorder.storeOverride?.record([
            UndoEntry(batchId: nil, operation: .delete, todoId: "todo-1", title: "Buy milk",
                      snapshot: TodoSnapshot(todo: openTodo)),
        ])

        _ = try await capture {
            var cmd = try UndoCommand.parse([])
            try await cmd.run()
        }

        #expect(mock.movedToList.map(\.list) == ["Anytime"])
    }

    @Test func undoKeepsEntryWhenAStepFails() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }
        try UndoRecorder.storeOverride?.record([
            UndoEntry(batchId: nil, operation: .complete, todoId: "a", title: "A", snapshot: nil),
        ])
        mock.errorToThrow = ThingsError.operationFailed("boom")

        await #expect(throws: (any Error).self) {
            _ = try await capture {
                var cmd = try UndoCommand.parse([])
                try await cmd.run()
            }
        }
        #expect(try latestUndo().map(\.todoId) == ["a"])
    }

    @Test func undoShowDoesNotApply() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }
        try UndoRecorder.storeOverride?.record([
            UndoEntry(batchId: nil, operation: .complete, todoId: "a", title: "A", snapshot: nil),
        ])

        let output = try await capture {
            var cmd = try UndoCommand.parse(["--show"])
            try await cmd.run()
        }

        #expect(mock.reopenedIds.isEmpty)
        #expect(output.contains("complete"))
        #expect(try latestUndo().count == 1)
    }

    @Test func undoWithEmptyHistorySaysSo() async throws {
        _ = setupMock()
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try UndoCommand.parse([])
            try await cmd.run()
        }

        #expect(output.contains("Nothing to undo"))
    }

    // MARK: - bulk

    @Test func bulkCompleteRecordsOneBatch() async throws {
        _ = setupMock {
            $0.todosForList[.today] = [
                Todo(id: "a", name: "A", start: .anytime), Todo(id: "b", name: "B", start: .anytime),
            ]
        }
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try BulkCompleteCommand.parse(["--yes"])
            try await cmd.run()
        }

        let group = try latestUndo()
        #expect(Set(group.map(\.todoId)) == ["a", "b"])
        #expect(Set(group.compactMap(\.batchId)).count == 1)
    }

    // MARK: - duplicate / open / project update

    @Test func duplicateOpensUpdateURL() async throws {
        _ = setupMock()
        defer { ThingsClientFactory.override = nil }

        let urls = try await withURLScheme {
            _ = try await capture {
                var cmd = try DuplicateCommand.parse(["todo-1"])
                try await cmd.run()
            }
        }

        let items = try firstQuery(urls)
        #expect(items["duplicate"] == "true")
        #expect(items["id"] == "todo-1")
    }

    @Test(arguments: [
        (["today"], "id", "today"),
        (["HQxc3aEk6ADGJUTyCQ6Gso"], "id", "HQxc3aEk6ADGJUTyCQ6Gso"),
        (["Work"], "query", "Work"),
    ])
    func openRevealsTarget(arguments: [String], key: String, value: String) async throws {
        _ = setupMock()
        defer { ThingsClientFactory.override = nil }

        let urls = try await withURLScheme(token: nil) {
            _ = try await capture {
                var cmd = try OpenCommand.parse(arguments)
                try await cmd.run()
            }
        }

        let url = try #require(urls.first)
        #expect(url.hasPrefix("things:///show?"))
        #expect(try query(url)[key] == value)
    }

    @Test func openWithTagFilter() async throws {
        _ = setupMock()
        defer { ThingsClientFactory.override = nil }

        let urls = try await withURLScheme(token: nil) {
            _ = try await capture {
                var cmd = try OpenCommand.parse(["Work", "--filter", "urgent", "home"])
                try await cmd.run()
            }
        }

        #expect(try firstQuery(urls)["filter"] == "urgent,home")
    }

    @Test func projectUpdateSchedulesAndMovesThroughURLScheme() async throws {
        _ = setupMock()
        defer { ThingsClientFactory.override = nil }

        let urls = try await withURLScheme {
            _ = try await capture {
                var cmd = try ProjectUpdateCommand.parse([
                    "P1", "--when", "someday", "--append-notes", "more", "--add-tags", "x",
                ])
                try await cmd.run()
            }
        }

        let update = try firstUpdate(urls)
        #expect(update.id == "P1")
        #expect(update.attributes["when"] as? String == "someday")
        #expect(update.attributes["append-notes"] as? String == "more")
        #expect(update.attributes["add-tags"] as? [String] == ["x"])
    }
}
