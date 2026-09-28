// ThingsURLScheme.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A deadline change: set to a calendar day, or clear it.
///
/// Clearing only works through the URL scheme; AppleScript and JXA both
/// reject `missing value`/`null` for `due date`.
public enum DeadlineChange: Equatable, Sendable {
    case set(DateComponents)
    case clear
}

/// A checklist item with its completion state, for replacing a whole checklist.
public struct ChecklistEntry: Codable, Equatable, Sendable {
    public var title: String
    public var completed: Bool

    public init(title: String, completed: Bool = false) {
        self.title = title
        self.completed = completed
    }
}

/// Attributes for a Things JSON `update` of a to-do. Only non-nil fields are sent.
public struct TodoUpdateAttributes: Equatable, Sendable {
    public var title: String?
    public var notes: String?
    public var prependNotes: String?
    public var appendNotes: String?
    public var when: WhenSpec?
    public var deadline: DeadlineChange?
    /// Replaces all tags.
    public var tags: [String]?
    public var addTags: [String]?
    /// Project or area ID. Setting it without `headingId` moves the to-do to the project root.
    public var listId: String?
    /// Project or area title, when the ID is unknown.
    public var list: String?
    public var headingId: String?
    /// Heading title within the to-do's current project.
    public var heading: String?
    /// Replaces the whole checklist, keeping each item's completion state. `[]` clears it.
    public var checklist: [ChecklistEntry]?
    public var appendChecklist: [String]?
    public var prependChecklist: [String]?

    public init() {}

    public var isEmpty: Bool { jsonAttributes().isEmpty }

    func jsonAttributes() -> [String: Any] {
        var result: [String: Any] = [:]
        result["title"] = title
        result["notes"] = notes
        result["prepend-notes"] = prependNotes
        result["append-notes"] = appendNotes
        result["when"] = when?.urlValue
        result["deadline"] = deadline.map(ThingsURLScheme.deadlineValue)
        result["tags"] = tags
        result["add-tags"] = addTags
        result["list-id"] = listId
        result["list"] = list
        result["heading-id"] = headingId
        result["heading"] = heading
        result["checklist-items"] = checklist.map(ThingsURLScheme.checklistObjects)
        result["append-checklist-items"] = appendChecklist.map { ThingsURLScheme.checklistObjects($0.map { ChecklistEntry(title: $0) }) }
        result["prepend-checklist-items"] = prependChecklist.map { ThingsURLScheme.checklistObjects($0.map { ChecklistEntry(title: $0) }) }
        return result
    }
}

/// Attributes for a Things JSON `update` of a project. Only non-nil fields are sent.
public struct ProjectUpdateAttributes: Equatable, Sendable {
    public var title: String?
    public var notes: String?
    public var prependNotes: String?
    public var appendNotes: String?
    public var when: WhenSpec?
    public var deadline: DeadlineChange?
    public var tags: [String]?
    public var addTags: [String]?
    public var areaId: String?

    public init() {}

    public var isEmpty: Bool { jsonAttributes().isEmpty }

    func jsonAttributes() -> [String: Any] {
        var result: [String: Any] = [:]
        result["title"] = title
        result["notes"] = notes
        result["prepend-notes"] = prependNotes
        result["append-notes"] = appendNotes
        result["when"] = when?.urlValue
        result["deadline"] = deadline.map(ThingsURLScheme.deadlineValue)
        result["tags"] = tags
        result["add-tags"] = addTags
        result["area-id"] = areaId
        return result
    }
}

/// Pure builders for Things URL scheme commands. Opening the URL is left to the caller
/// so every builder can be unit tested without launching Things.
///
/// Updates go through the `json` command: it covers everything `update` does and also
/// checklist items with their completion state, which undo needs to restore a to-do.
/// Updates are applied asynchronously by Things, typically within a few seconds.
///
/// Payload shapes were verified against Things 3.24 and differ from the published docs:
/// `add-tags` must be an array of titles and `append-`/`prepend-checklist-items` arrays of
/// checklist-item objects. The documented string forms are rejected with an error dialog.
/// `tags: []` does not clear tags; use AppleScript for that.
public enum ThingsURLScheme {
    /// Built-in list IDs accepted by `things:///show?id=`.
    public static let builtInListIds: Set<String> = [
        "inbox", "today", "anytime", "upcoming", "someday", "logbook",
        "tomorrow", "deadlines", "repeating", "all-projects", "logged-projects",
    ]

    public static func updateTodo(id: String, attributes: TodoUpdateAttributes, authToken: String) throws -> String {
        try updateTodos([(id, attributes)], authToken: authToken)
    }

    /// One `json` call updating several to-dos. Things accepts up to 250 items per 10 seconds.
    public static func updateTodos(_ updates: [(id: String, attributes: TodoUpdateAttributes)], authToken: String) throws -> String {
        let operations: [[String: Any]] = updates.map { update in
            ["type": "to-do", "operation": "update", "id": update.id, "attributes": update.attributes.jsonAttributes()]
        }
        return try jsonURL(operations, authToken: authToken)
    }

    public static func updateProject(id: String, attributes: ProjectUpdateAttributes, authToken: String) throws -> String {
        let operation: [String: Any] = [
            "type": "project", "operation": "update", "id": id, "attributes": attributes.jsonAttributes(),
        ]
        return try jsonURL([operation], authToken: authToken)
    }

    /// Reveal a to-do, project, area or built-in list in Things. Needs no auth token.
    public static func show(id: String) throws -> String {
        try url("show", [URLQueryItem(name: "id", value: id)])
    }

    /// Reveal an area, project, tag or list by name, optionally filtered by tags.
    public static func show(query: String, filterTags: [String] = []) throws -> String {
        var items = [URLQueryItem(name: "query", value: query)]
        if !filterTags.isEmpty {
            items.append(URLQueryItem(name: "filter", value: filterTags.joined(separator: ",")))
        }
        return try url("show", items)
    }

    /// Duplicate a to-do. Only the `update` command supports this; repeating to-dos cannot be duplicated.
    public static func duplicateTodo(id: String, authToken: String) throws -> String {
        try url("update", [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "duplicate", value: "true"),
            URLQueryItem(name: "auth-token", value: authToken),
        ])
    }

    static func checklistObjects(_ entries: [ChecklistEntry]) -> [[String: Any]] {
        entries.map { entry in
            ["type": "checklist-item", "attributes": ["title": entry.title, "completed": entry.completed]]
        }
    }

    static func deadlineValue(_ change: DeadlineChange) -> String {
        switch change {
        case .clear:
            return ""
        case .set(let components):
            return WhenSpec.day(components).urlValue
        }
    }

    private static func jsonURL(_ operations: [[String: Any]], authToken: String) throws -> String {
        // Sorted keys keep URLs deterministic for tests; Things ignores key order.
        let data = try JSONSerialization.data(withJSONObject: operations, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ThingsError.operationFailed("Failed to encode Things JSON payload")
        }
        return try url("json", [
            URLQueryItem(name: "data", value: json),
            URLQueryItem(name: "auth-token", value: authToken),
        ])
    }

    private static func url(_ command: String, _ items: [URLQueryItem]) throws -> String {
        guard var components = URLComponents(string: "things:///\(command)") else {
            throw ThingsError.operationFailed("Internal error: failed to parse Things URL base")
        }
        components.queryItems = items
        guard let url = components.url?.absoluteString else {
            throw ThingsError.operationFailed("Failed to construct Things \(command) URL")
        }
        return url
    }
}

// MARK: - Skipping no-op writes

extension TodoUpdateAttributes {
    /// Drop attributes the to-do already satisfies. Things ignores a write that changes
    /// nothing (its modification date stays put), so sending one would look like a
    /// rejected update. Appends and prepends always change something and are kept.
    public func removingSatisfied(by current: TodoSnapshot, now: Date = Date()) -> TodoUpdateAttributes {
        var result = self
        if result.title == current.title { result.title = nil }
        if result.notes == current.notes { result.notes = nil }
        if let when = result.when, when.isSatisfied(by: current, now: now) { result.when = nil }
        switch result.deadline {
        case .clear?:
            if current.deadline == nil { result.deadline = nil }
        case .set(let day)?:
            if current.deadline == day { result.deadline = nil }
        case nil:
            break
        }
        if let tags = result.tags, Set(tags) == Set(current.tags) { result.tags = nil }
        if let addTags = result.addTags, Set(addTags).isSubset(of: Set(current.tags)) { result.addTags = nil }
        // `list-id` also decides the heading (alone it means "project root"), so it is
        // only dropped when both already match.
        if let listId = result.listId {
            if listId == (current.projectId ?? current.areaId) && result.headingId == current.headingId {
                result.listId = nil
                result.headingId = nil
            }
        } else if let headingId = result.headingId, headingId == current.headingId {
            result.headingId = nil
        }
        if let checklist = result.checklist, checklist == current.checklist { result.checklist = nil }
        return result
    }
}

extension WhenSpec {
    /// Whether the to-do is already scheduled this way.
    public func isSatisfied(by current: TodoSnapshot, now: Date = Date()) -> Bool {
        let today = ThingsDateConverter.calendar.dateComponents([.year, .month, .day], from: now)
        switch self {
        case .someday:
            return current.start == .someday && current.startDay == nil
        case .anytime:
            return current.start == .anytime && current.startDay == nil
        case .today:
            return current.startDay == today && !current.isEvening
        case .evening:
            return current.startDay == today && current.isEvening
        case .day(let components):
            return current.startDay == DateComponents(year: components.year, month: components.month, day: components.day)
        case .dayAndTime(let components):
            return current.startDay == DateComponents(year: components.year, month: components.month, day: components.day)
                && current.reminderTime == DateComponents(hour: components.hour, minute: components.minute)
        }
    }
}
