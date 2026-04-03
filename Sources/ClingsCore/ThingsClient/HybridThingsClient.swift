// HybridThingsClient.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Hybrid Things client that uses SQLite for fast reads and JXA/AppleScript for writes.
public final class HybridThingsClient: ThingsClientProtocol, @unchecked Sendable {
    private let database: ThingsDatabase
    private let jxaBridge: JXABridge

    public init(databasePath: String? = nil) throws {
        self.database = try ThingsDatabase(databasePath: databasePath)
        self.jxaBridge = JXABridge()
    }

    // MARK: - Reads (via SQLite - fast)

    public func fetchList(_ list: ListView, limit: Int? = nil) async throws -> [Todo] {
        try database.fetchList(list, limit: limit)
    }

    public func fetchAllOpen() async throws -> [Todo] {
        try database.fetchAllOpen()
    }

    public func fetchProjects() async throws -> [Project] {
        try database.fetchProjects()
    }

    public func fetchAreas() async throws -> [Area] {
        try database.fetchAreas()
    }

    public func fetchTags() async throws -> [Tag] {
        try database.fetchTags()
    }

    public func fetchHeadings(projectId: String) async throws -> [Heading] {
        try database.fetchHeadings(projectId: projectId)
    }

    public func fetchTodo(id: String) async throws -> Todo {
        try database.fetchTodo(id: id)
    }

    public func fetchRecent(since: Date) async throws -> [Todo] {
        try database.fetchRecent(since: since)
    }

    public func search(query: String, limit: Int = 100) async throws -> [Todo] {
        try database.search(query: query, limit: limit)
    }

    // MARK: - Writes (via JXA - safe)

    public func createTodo(
        name: String,
        notes: String?,
        when: Date?,
        deadline: Date?,
        tags: [String],
        project: String?,
        area: String?,
        checklistItems: [String]
    ) async throws -> String {
        let script = JXAScripts.createTodoAppleScript(
            name: name,
            notes: notes,
            when: when,
            deadline: deadline,
            project: project,
            area: area,
            checklistItems: checklistItems
        )

        let id: String
        do {
            id = try await jxaBridge.executeAppleScript(script)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as JXAError {
            throw ThingsError.jxaError(error)
        }

        guard !id.isEmpty else {
            throw ThingsError.operationFailed("Failed to create todo - no ID returned")
        }

        if !tags.isEmpty {
            let tagScript = JXAScripts.setTodoTagsAppleScript(id: id, tags: tags)
            do {
                _ = try await jxaBridge.executeAppleScript(tagScript)
            } catch let error as JXAError {
                throw ThingsError.jxaError(error)
            }
        }

        return id
    }

    public func createProject(
        name: String,
        notes: String?,
        when: Date?,
        deadline: Date?,
        tags: [String],
        area: String?
    ) async throws -> String {
        let script = JXAScripts.createProject(
            name: name,
            notes: notes,
            when: when,
            deadline: deadline,
            area: area
        )

        let result = try await jxaBridge.executeJSON(script, as: CreationResult.self)
        if !result.success {
            throw ThingsError.operationFailed(result.error ?? "Unknown error")
        }
        guard let id = result.id else {
            throw ThingsError.operationFailed("Missing created project ID")
        }

        if !tags.isEmpty {
            let tagScript = JXAScripts.setProjectTagsAppleScript(id: id, tags: tags)
            do {
                _ = try await jxaBridge.executeAppleScript(tagScript)
            } catch let error as JXAError {
                throw ThingsError.jxaError(error)
            }
        }

        return id
    }

    public func completeTodo(id: String) async throws {
        let script = JXAScripts.completeTodo(id: id)
        let result = try await jxaBridge.executeJSON(script, as: MutationResult.self)
        if !result.success {
            throw ThingsError.operationFailed(result.error ?? "Unknown error")
        }
    }

    public func reopenTodo(id: String) async throws {
        let script = JXAScripts.reopenTodo(id: id)
        let result = try await jxaBridge.executeJSON(script, as: MutationResult.self)
        if !result.success {
            throw ThingsError.operationFailed(result.error ?? "Unknown error")
        }
    }

    public func cancelTodo(id: String) async throws {
        let script = JXAScripts.cancelTodo(id: id)
        let result = try await jxaBridge.executeJSON(script, as: MutationResult.self)
        if !result.success {
            throw ThingsError.operationFailed(result.error ?? "Unknown error")
        }
    }

    public func deleteTodo(id: String) async throws {
        let script = JXAScripts.deleteTodo(id: id)
        let result = try await jxaBridge.executeJSON(script, as: MutationResult.self)
        if !result.success {
            throw ThingsError.operationFailed(result.error ?? "Unknown error")
        }
    }

    public func moveTodo(id: String, toProject projectName: String) async throws {
        let script = JXAScripts.moveTodo(id: id, toProject: projectName)
        let result = try await jxaBridge.executeJSON(script, as: MutationResult.self)
        if !result.success {
            throw ThingsError.operationFailed(result.error ?? "Unknown error")
        }
    }

    public func updateTodo(id: String, name: String?, notes: String?, deadlineDate: Date?, tags: [String]?) async throws {
        if name != nil || notes != nil || deadlineDate != nil {
            let script = JXAScripts.updateTodo(id: id, name: name, notes: notes, dueDate: deadlineDate, tags: nil)
            let result = try await jxaBridge.executeJSON(script, as: MutationResult.self)
            if !result.success {
                throw ThingsError.operationFailed(result.error ?? "Unknown error")
            }
        }

        if let tags = tags {
            let tagScript = JXAScripts.setTodoTagsAppleScript(id: id, tags: tags)
            do {
                _ = try await jxaBridge.executeAppleScript(tagScript)
            } catch let error as JXAError {
                throw ThingsError.jxaError(error)
            }
        }
    }

    public func updateProject(id: String, name: String?, notes: String?, deadlineDate: Date?, tags: [String]?) async throws {
        if name != nil || notes != nil || deadlineDate != nil {
            let script = JXAScripts.updateProject(id: id, name: name, notes: notes, dueDate: deadlineDate)
            let result = try await jxaBridge.executeJSON(script, as: MutationResult.self)
            if !result.success {
                throw ThingsError.operationFailed(result.error ?? "Unknown error")
            }
        }

        if let tags = tags {
            let tagScript = JXAScripts.setProjectTagsAppleScript(id: id, tags: tags)
            do {
                _ = try await jxaBridge.executeAppleScript(tagScript)
            } catch let error as JXAError {
                throw ThingsError.jxaError(error)
            }
        }
    }

    // MARK: - Tag Management

    public func createTag(name: String) async throws -> Tag {
        let script = JXAScripts.createTagAppleScript(name: name)
        do {
            let tagId = try await jxaBridge.executeAppleScript(script)
            return Tag(id: tagId, name: name)
        } catch let error as JXAError {
            throw ThingsError.jxaError(error)
        }
    }

    public func deleteTag(name: String) async throws {
        let script = JXAScripts.deleteTagAppleScript(name: name)
        do {
            _ = try await jxaBridge.executeAppleScript(script)
        } catch let error as JXAError {
            throw ThingsError.jxaError(error)
        }
    }

    public func renameTag(oldName: String, newName: String) async throws {
        let script = JXAScripts.renameTagAppleScript(oldName: oldName, newName: newName)
        do {
            _ = try await jxaBridge.executeAppleScript(script)
        } catch let error as JXAError {
            throw ThingsError.jxaError(error)
        }
    }

    // MARK: - Open (disabled)

    public nonisolated func openInThings(id: String) throws {
        throw ThingsError.invalidState("Open command is disabled: URL schemes are not allowed.")
    }

    public nonisolated func openInThings(list: ListView) throws {
        throw ThingsError.invalidState("Open command is disabled: URL schemes are not allowed.")
    }
}

/// Factory to create the appropriate Things client.
public enum ThingsClientFactory {
    /// Override client for testing. When set, `create()` returns this instead.
    nonisolated(unsafe) public static var override: (any ThingsClientProtocol)?

    /// Create a Things client - tries hybrid first, falls back to JXA-only.
    ///
    /// When an explicit `databasePath` is provided, failure is thrown rather
    /// than silently falling back to JXA-only. Auto-discovery failures still
    /// fall back gracefully.
    public static func create(databasePath: String? = nil) throws -> any ThingsClientProtocol {
        if let override { return override }

        if databasePath != nil {
            return try HybridThingsClient(databasePath: databasePath)
        }
        do {
            return try HybridThingsClient()
        } catch {
            return ThingsClient()
        }
    }
}
