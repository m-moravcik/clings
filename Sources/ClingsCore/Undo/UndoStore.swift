// UndoStore.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A mutation clings can reverse.
public enum UndoOperation: String, Codable, Equatable, Sendable {
    case create
    case update
    case complete
    case cancel
    case reopen
    case delete
}

/// Everything needed to put a to-do back the way it was.
public struct TodoSnapshot: Codable, Equatable, Sendable {
    public var title: String
    public var notes: String
    public var status: Status
    public var start: TodoStart?
    /// Scheduled calendar day (year, month, day).
    public var startDay: DateComponents?
    public var isEvening: Bool
    public var reminderTime: DateComponents?
    /// Deadline calendar day (year, month, day).
    public var deadline: DateComponents?
    public var tags: [String]
    public var projectId: String?
    /// The to-do's own area (nil when it lives in a project).
    public var areaId: String?
    public var headingId: String?
    public var checklist: [ChecklistEntry]

    public init(
        title: String,
        notes: String,
        status: Status,
        start: TodoStart?,
        startDay: DateComponents?,
        isEvening: Bool,
        reminderTime: DateComponents?,
        deadline: DateComponents?,
        tags: [String],
        projectId: String?,
        areaId: String?,
        headingId: String?,
        checklist: [ChecklistEntry]
    ) {
        self.title = title
        self.notes = notes
        self.status = status
        self.start = start
        self.startDay = startDay
        self.isEvening = isEvening
        self.reminderTime = reminderTime
        self.deadline = deadline
        self.tags = tags
        self.projectId = projectId
        self.areaId = areaId
        self.headingId = headingId
        self.checklist = checklist
    }

    public init(todo: Todo) {
        let calendar = ThingsDateConverter.calendar
        let day: (Date) -> DateComponents = { calendar.dateComponents([.year, .month, .day], from: $0) }
        self.init(
            title: todo.name,
            notes: todo.notes ?? "",
            status: todo.status,
            start: todo.start,
            startDay: todo.startDate.map(day),
            isEvening: todo.isEvening,
            reminderTime: todo.reminderTime,
            deadline: todo.deadlineDate.map(day),
            tags: todo.tags.map(\.name),
            projectId: todo.project?.id,
            areaId: todo.area?.id,
            headingId: todo.headingId,
            checklist: todo.checklistItems.map { ChecklistEntry(title: $0.name, completed: $0.completed) }
        )
    }
}

/// One recorded mutation. Entries sharing a `batchId` (a bulk command) are undone together.
public struct UndoEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let batchId: UUID?
    public let operation: UndoOperation
    public let todoId: String
    public let title: String
    /// State before the mutation; required to undo update, delete and reopen.
    public let snapshot: TodoSnapshot?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        batchId: UUID?,
        operation: UndoOperation,
        todoId: String,
        title: String,
        snapshot: TodoSnapshot?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.batchId = batchId
        self.operation = operation
        self.todoId = todoId
        self.title = title
        self.snapshot = snapshot
        self.createdAt = createdAt
    }
}

/// Undo history persisted as JSON. The file holds task titles and notes, so it is
/// written owner-only (0600) like the auth token.
public struct UndoStore: Sendable {
    public static let maxEntries = 50

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The store under the clings config directory (`~/.config/clings/undo-history.json`).
    public static func standard() throws -> UndoStore {
        UndoStore(fileURL: try ClingsConfig.fileURL(named: "undo-history.json"))
    }

    /// All entries, newest first.
    public func entries() throws -> [UndoEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([UndoEntry].self, from: Data(contentsOf: fileURL))
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    public func record(_ newEntries: [UndoEntry]) throws {
        guard !newEntries.isEmpty else { return }
        let entries = Array((newEntries + (try self.entries()))
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.maxEntries))
        try save(entries)
    }

    /// The newest entry together with the rest of its batch.
    public func latestGroup() throws -> [UndoEntry] {
        let entries = try self.entries()
        guard let latest = entries.first else { return [] }
        guard let batchId = latest.batchId else { return [latest] }
        return entries.filter { $0.batchId == batchId }
    }

    public func remove(entryIds: Set<UUID>) throws {
        try save(try entries().filter { !entryIds.contains($0.id) })
    }

    private func save(_ entries: [UndoEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
