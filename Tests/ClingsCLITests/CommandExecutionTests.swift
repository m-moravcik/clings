// CommandExecutionTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import ClingsCLI
@testable import ClingsCore

// MARK: - Test Mock

/// Lightweight mock for command execution tests.
private final class CommandMock: ThingsClientProtocol, @unchecked Sendable {
    var todosForList: [ListView: [Todo]] = [:]
    var todoById: [String: Todo] = [:]
    var searchResults: [Todo] = []
    var projects: [Project] = []
    var areas: [Area] = []
    var tags: [ClingsCore.Tag] = []
    var errorToThrow: Error?

    private(set) var fetchedLists: [ListView] = []
    private(set) var completedIds: [String] = []
    private(set) var canceledIds: [String] = []
    private(set) var reopenedIds: [String] = []
    private(set) var deletedIds: [String] = []
    private(set) var searchQueries: [String] = []
    private(set) var createdTodos: [(name: String, id: String)] = []

    func fetchList(_ list: ListView, limit: Int? = nil) async throws -> [Todo] {
        if let error = errorToThrow { throw error }
        fetchedLists.append(list)
        let todos = todosForList[list] ?? []
        if let limit { return Array(todos.prefix(limit)) }
        return todos
    }

    func fetchAllOpen() async throws -> [Todo] {
        if let error = errorToThrow { throw error }
        var todos: [Todo] = []
        for list in [ListView.today, .inbox, .upcoming, .anytime, .someday] {
            todos.append(contentsOf: todosForList[list] ?? [])
        }
        return todos
    }

    func fetchProjects() async throws -> [Project] {
        if let error = errorToThrow { throw error }
        return projects
    }

    func fetchAreas() async throws -> [Area] {
        if let error = errorToThrow { throw error }
        return areas
    }

    func fetchTags() async throws -> [ClingsCore.Tag] {
        if let error = errorToThrow { throw error }
        return tags
    }

    func fetchHeadings(projectId: String) async throws -> [Heading] { [] }

    func fetchRecent(since: Date) async throws -> [Todo] {
        if let error = errorToThrow { throw error }
        return searchResults
    }

    func fetchTodo(id: String) async throws -> Todo {
        if let error = errorToThrow { throw error }
        guard let todo = todoById[id] else { throw ThingsError.notFound(id) }
        return todo
    }

    func createTodo(name: String, notes: String?, when: Date?, deadline: Date?,
                    tags: [String], project: String?, area: String?,
                    checklistItems: [String]) async throws -> String {
        if let error = errorToThrow { throw error }
        let id = "mock-\(createdTodos.count)"
        createdTodos.append((name, id))
        return id
    }

    func createProject(name: String, notes: String?, when: Date?, deadline: Date?,
                       tags: [String], area: String?) async throws -> String {
        if let error = errorToThrow { throw error }
        return "mock-proj"
    }

    func completeTodo(id: String) async throws {
        if let error = errorToThrow { throw error }
        completedIds.append(id)
    }

    func reopenTodo(id: String) async throws {
        if let error = errorToThrow { throw error }
        reopenedIds.append(id)
    }

    func cancelTodo(id: String) async throws {
        if let error = errorToThrow { throw error }
        canceledIds.append(id)
    }

    func deleteTodo(id: String) async throws {
        if let error = errorToThrow { throw error }
        deletedIds.append(id)
    }

    func moveTodo(id: String, toProject: String) async throws {
        if let error = errorToThrow { throw error }
    }

    func updateTodo(id: String, name: String?, notes: String?,
                    deadlineDate: Date?, tags: [String]?) async throws {
        if let error = errorToThrow { throw error }
    }

    func updateProject(id: String, name: String?, notes: String?,
                       deadlineDate: Date?, tags: [String]?) async throws {
        if let error = errorToThrow { throw error }
    }

    func search(query: String, limit: Int = 100) async throws -> [Todo] {
        if let error = errorToThrow { throw error }
        searchQueries.append(query)
        return Array(searchResults.prefix(limit))
    }

    func createTag(name: String) async throws -> ClingsCore.Tag {
        ClingsCore.Tag(id: "mock-tag", name: name)
    }

    func deleteTag(name: String) async throws {}
    func renameTag(oldName: String, newName: String) async throws {}
    func openInThings(id: String) throws {}
    func openInThings(list: ListView) throws {}
}

// MARK: - Test Fixtures

private let sampleTag = ClingsCore.Tag(id: "tag-1", name: "work")
private let sampleArea = Area(id: "area-1", name: "Work", tags: [])
private let sampleProject = Project(
    id: "proj-1", name: "Alpha", notes: nil, status: .open,
    area: sampleArea, tags: [], deadlineDate: nil, creationDate: Date()
)
private let sampleTodo = Todo(
    id: "todo-1", name: "Buy milk", notes: "2%", status: .open,
    deadlineDate: nil, tags: [sampleTag], project: sampleProject,
    area: sampleArea, checklistItems: [],
    creationDate: Date(), modificationDate: Date()
)
private let sampleTodo2 = Todo(
    id: "todo-2", name: "Write tests", notes: nil, status: .open,
    deadlineDate: Date(), tags: [], project: nil,
    area: nil, checklistItems: [],
    creationDate: Date(), modificationDate: Date()
)
private let completedTodo = Todo(
    id: "todo-done", name: "Done task", notes: nil, status: .completed,
    deadlineDate: nil, tags: [], project: nil, area: nil, checklistItems: [],
    creationDate: Date(), modificationDate: Date()
)

// MARK: - Helper

/// Capture stdout from a block. NOT safe for parallel use.
private func capture(_ block: () async throws -> Void) async rethrows -> String {
    let pipe = Pipe()
    let original = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    try await block()
    fflush(stdout)
    dup2(original, STDOUT_FILENO)
    close(original)
    pipe.fileHandleForWriting.closeFile()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

private func setupMock(_ configure: (CommandMock) -> Void = { _ in }) -> CommandMock {
    let mock = CommandMock()
    configure(mock)
    ThingsClientFactory.override = mock
    return mock
}

// MARK: - All Command Execution Tests (serialized to avoid stdout capture races)

@Suite("Command Execution", .serialized)
struct CommandExecutionTests {

    // MARK: - List Commands

    @Test func todayFetchesAndOutputs() async throws {
        let mock = setupMock { $0.todosForList[.today] = [sampleTodo, sampleTodo2] }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try TodayCommand.parse([])
            try await cmd.run()
        }

        #expect(mock.fetchedLists == [.today])
        #expect(output.contains("Buy milk"))
        #expect(output.contains("Write tests"))
    }

    @Test func todayJSON() async throws {
        _ = setupMock { $0.todosForList[.today] = [sampleTodo] }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try TodayCommand.parse(["--json"])
            try await cmd.run()
        }

        #expect(output.contains("\"count\" : 1"))
        #expect(output.contains("Buy milk"))
    }

    @Test func inboxFetchesCorrectList() async throws {
        let mock = setupMock { $0.todosForList[.inbox] = [sampleTodo] }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try InboxCommand.parse([])
            try await cmd.run()
        }

        #expect(mock.fetchedLists == [.inbox])
        #expect(output.contains("Buy milk"))
    }

    @Test func logbookRespectsLimit() async throws {
        let todos = (0..<10).map { i in
            Todo(id: "done-\(i)", name: "Done \(i)", notes: nil, status: .completed,
                 deadlineDate: nil, tags: [], project: nil, area: nil, checklistItems: [],
                 creationDate: Date(), modificationDate: Date())
        }
        _ = setupMock { $0.todosForList[.logbook] = todos }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try LogbookCommand.parse(["--limit", "3"])
            try await cmd.run()
        }

        #expect(output.contains("Done 0"))
        #expect(output.contains("Done 2"))
        #expect(!output.contains("Done 3"))
    }

    @Test func emptyListNoTodoMarker() async throws {
        _ = setupMock { $0.todosForList[.upcoming] = [] }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try UpcomingCommand.parse([])
            try await cmd.run()
        }

        #expect(!output.contains("☐"))
    }

    @Test func projectsOutput() async throws {
        _ = setupMock { $0.projects = [sampleProject] }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try ProjectsCommand.parse([])
            try await cmd.run()
        }

        #expect(output.contains("Alpha"))
    }

    @Test func areasOutput() async throws {
        _ = setupMock { $0.areas = [sampleArea] }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try AreasCommand.parse([])
            try await cmd.run()
        }

        #expect(output.contains("Work"))
    }

    // MARK: - Mutations

    @Test func completeById() async throws {
        let mock = setupMock { $0.todoById["todo-1"] = sampleTodo }
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try CompleteCommand.parse(["todo-1"])
            try await cmd.run()
        }

        #expect(mock.completedIds == ["todo-1"])
    }

    @Test func cancelById() async throws {
        let mock = setupMock { $0.todoById["todo-1"] = sampleTodo }
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try CancelCommand.parse(["todo-1"])
            try await cmd.run()
        }

        #expect(mock.canceledIds == ["todo-1"])
    }

    @Test func reopenById() async throws {
        let mock = setupMock { $0.todoById["todo-done"] = completedTodo }
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try ReopenCommand.parse(["todo-done"])
            try await cmd.run()
        }

        #expect(mock.reopenedIds == ["todo-done"])
    }

    @Test func deleteById() async throws {
        let mock = setupMock { $0.todoById["todo-1"] = sampleTodo }
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try DeleteCommand.parse(["todo-1"])
            try await cmd.run()
        }

        #expect(mock.deletedIds == ["todo-1"])
    }

    @Test func completeWithoutIdOrTitleThrows() async throws {
        _ = setupMock()
        defer { ThingsClientFactory.override = nil }

        await #expect(throws: Error.self) {
            _ = try await capture {
                // No ID and no --title should throw validation error
                var cmd = try CompleteCommand.parse([])
                try await cmd.run()
            }
        }
    }

    // MARK: - Search

    @Test func searchQueriesClient() async throws {
        let mock = setupMock { $0.searchResults = [sampleTodo] }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try SearchCommand.parse(["milk"])
            try await cmd.run()
        }

        #expect(mock.searchQueries == ["milk"])
        #expect(output.contains("Buy milk"))
    }

    @Test func searchRespectsLimit() async throws {
        _ = setupMock { $0.searchResults = [sampleTodo, sampleTodo2] }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try SearchCommand.parse(["test", "--limit", "1"])
            try await cmd.run()
        }

        #expect(output.contains("Buy milk"))
        #expect(!output.contains("Write tests"))
    }

    @Test func searchJSON() async throws {
        _ = setupMock { $0.searchResults = [sampleTodo] }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try SearchCommand.parse(["milk", "--json"])
            try await cmd.run()
        }

        #expect(output.contains("\"name\" : \"Buy milk\""))
    }

    // MARK: - Show

    @Test func showDisplaysTodo() async throws {
        _ = setupMock { $0.todoById["todo-1"] = sampleTodo }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try ShowCommand.parse(["todo-1"])
            try await cmd.run()
        }

        #expect(output.contains("Buy milk"))
    }

    @Test func showJSON() async throws {
        _ = setupMock { $0.todoById["todo-1"] = sampleTodo }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try ShowCommand.parse(["todo-1", "--json"])
            try await cmd.run()
        }

        #expect(output.contains("\"id\" : \"todo-1\""))
    }

    @Test func showNotFoundThrows() async throws {
        _ = setupMock()
        defer { ThingsClientFactory.override = nil }

        await #expect(throws: Error.self) {
            _ = try await capture {
                var cmd = try ShowCommand.parse(["nonexistent"])
                try await cmd.run()
            }
        }
    }

    // MARK: - Filter

    @Test func filterByStatusOpen() async throws {
        _ = setupMock {
            $0.todosForList[.today] = [sampleTodo]
            $0.todosForList[.inbox] = [sampleTodo2]
        }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try FilterCommand.parse(["status = open"])
            try await cmd.run()
        }

        #expect(output.contains("Buy milk"))
        #expect(output.contains("Write tests"))
    }

    @Test func filterByTag() async throws {
        _ = setupMock { $0.todosForList[.today] = [sampleTodo, sampleTodo2] }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try FilterCommand.parse(["tags CONTAINS 'work'"])
            try await cmd.run()
        }

        #expect(output.contains("Buy milk"))
        #expect(!output.contains("Write tests"))
    }

    @Test func filterNoMatches() async throws {
        _ = setupMock { $0.todosForList[.today] = [sampleTodo] }
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try FilterCommand.parse(["status = completed"])
            try await cmd.run()
        }

        #expect(!output.contains("Buy milk"))
    }

    // MARK: - Add

    @Test func addCreatesTask() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }

        let output = try await capture {
            var cmd = try AddCommand.parse(["Buy groceries"])
            try await cmd.run()
        }

        #expect(mock.createdTodos.count == 1)
        #expect(mock.createdTodos[0].name == "Buy groceries")
        #expect(output.contains("Buy groceries"))
    }

    @Test func addWithNotes() async throws {
        let mock = setupMock()
        defer { ThingsClientFactory.override = nil }

        _ = try await capture {
            var cmd = try AddCommand.parse(["Task", "--notes", "Details"])
            try await cmd.run()
        }

        #expect(mock.createdTodos.count == 1)
    }

    // MARK: - Error Propagation

    @Test func listPropagatesError() async throws {
        _ = setupMock { $0.errorToThrow = ThingsError.operationFailed("DB down") }
        defer { ThingsClientFactory.override = nil }

        await #expect(throws: Error.self) {
            _ = try await capture {
                var cmd = try TodayCommand.parse([])
                try await cmd.run()
            }
        }
    }

    @Test func searchPropagatesError() async throws {
        _ = setupMock { $0.errorToThrow = ThingsError.operationFailed("Fail") }
        defer { ThingsClientFactory.override = nil }

        await #expect(throws: Error.self) {
            _ = try await capture {
                var cmd = try SearchCommand.parse(["test"])
                try await cmd.run()
            }
        }
    }
}
