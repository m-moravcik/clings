// HeadingValidationTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import ClingsCLI
@testable import ClingsCore

// MARK: - Minimal mock returning configurable headings

private final class HeadingMock: ThingsClientProtocol, @unchecked Sendable {
    var headings: [Heading] = []
    var throwInvalidState = false

    func fetchHeadings(projectId: String) async throws -> [Heading] {
        if throwInvalidState {
            throw ThingsError.invalidState("fetchHeadings requires SQLite access (HybridThingsClient)")
        }
        return headings
    }

    // Unused protocol requirements
    func fetchList(_ list: ListView, limit: Int?) async throws -> [Todo] { [] }
    func fetchProjects() async throws -> [Project] { [] }
    func fetchAreas() async throws -> [Area] { [] }
    func fetchTags() async throws -> [ClingsCore.Tag] { [] }
    func fetchAllOpen() async throws -> [Todo] { [] }
    func fetchRecent(since: Date) async throws -> [Todo] { [] }
    func fetchTodo(id: String) async throws -> Todo { throw ThingsError.notFound(id) }
    func createTodo(name: String, notes: String?, when: Date?, deadline: Date?, tags: [String],
                    project: String?, area: String?, checklistItems: [String]) async throws -> String { "" }
    func createProject(name: String, notes: String?, when: Date?, deadline: Date?,
                       tags: [String], area: String?) async throws -> String { "" }
    func completeTodo(id: String) async throws {}
    func reopenTodo(id: String) async throws {}
    func cancelTodo(id: String) async throws {}
    func deleteTodo(id: String) async throws {}
    func moveTodo(id: String, toProject: String) async throws {}
    func updateTodo(id: String, name: String?, notes: String?, deadlineDate: Date?, tags: [String]?) async throws {}
    func updateProject(id: String, name: String?, notes: String?, deadlineDate: Date?, tags: [String]?) async throws {}
    func search(query: String, limit: Int) async throws -> [Todo] { [] }
    func createTag(name: String) async throws -> ClingsCore.Tag { ClingsCore.Tag(id: "", name: name) }
    func deleteTag(name: String) async throws {}
    func renameTag(oldName: String, newName: String) async throws {}
    func openInThings(id: String) throws {}
    func openInThings(list: ListView) throws {}
}

@Suite("AddCommand heading validation")
struct HeadingValidationTests {
    private func heading(_ title: String) -> Heading {
        Heading(id: UUID().uuidString, title: title, projectId: "proj")
    }

    @Test func passesWhenHeadingExists() async throws {
        let mock = HeadingMock()
        mock.headings = [heading("Week 1"), heading("Week 2")]
        // Should not throw.
        try await AddCommand.validateHeadingExists("Week 1", inProject: "P", using: mock)
    }

    @Test func throwsWhenHeadingMissing() async throws {
        let mock = HeadingMock()
        mock.headings = [heading("Week 1")]
        await #expect(throws: ThingsError.self) {
            try await AddCommand.validateHeadingExists("Week 9", inProject: "P", using: mock)
        }
    }

    @Test func throwsWhenProjectHasNoHeadings() async throws {
        let mock = HeadingMock()
        mock.headings = []
        await #expect(throws: ThingsError.self) {
            try await AddCommand.validateHeadingExists("Week 1", inProject: "P", using: mock)
        }
    }

    @Test func proceedsWhenDatabaseUnavailable() async throws {
        let mock = HeadingMock()
        mock.throwInvalidState = true
        // invalidState (JXA-only client) is swallowed: validation is skipped, no throw.
        try await AddCommand.validateHeadingExists("Week 1", inProject: "P", using: mock)
    }

    @Test func matchIsCaseAndWhitespaceSensitive() async throws {
        let mock = HeadingMock()
        mock.headings = [heading("Week 1")]
        // Exact match only — "week 1" must not match "Week 1".
        await #expect(throws: ThingsError.self) {
            try await AddCommand.validateHeadingExists("week 1", inProject: "P", using: mock)
        }
    }
}
