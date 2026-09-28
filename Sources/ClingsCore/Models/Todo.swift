// Todo.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The list bucket a todo lives in (Things' `start` column).
public enum TodoStart: String, Codable, Sendable {
    case inbox
    case anytime
    case someday
}

/// A todo item from Things 3.
///
/// Represents a single task with metadata including title, notes, status,
/// deadline, tags, and organizational hierarchy (project/area).
public struct Todo: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var notes: String?
    public var status: Status
    public var deadlineDate: Date?
    public var tags: [Tag]
    public var project: Project?
    public var area: Area?
    public var checklistItems: [ChecklistItem]
    public var startDate: Date?
    public var repeatingTemplate: String?
    /// True for the hidden template row that spawns repeating instances.
    public var isRepeatingTemplate: Bool
    public var creationDate: Date
    public var modificationDate: Date
    public var scheduledDate: Date?
    public var heading: String?
    public var headingId: String?
    /// Inbox/Anytime/Someday bucket; nil when read through JXA.
    public var start: TodoStart?
    /// Scheduled for This Evening.
    public var isEvening: Bool
    /// Reminder time (hour, minute) on the scheduled day.
    public var reminderTime: DateComponents?
    /// When the todo was completed or canceled (nil while open).
    public var completionDate: Date?

    public init(
        id: String,
        name: String,
        notes: String? = nil,
        status: Status = .open,
        deadlineDate: Date? = nil,
        tags: [Tag] = [],
        project: Project? = nil,
        area: Area? = nil,
        checklistItems: [ChecklistItem] = [],
        startDate: Date? = nil,
        repeatingTemplate: String? = nil,
        isRepeatingTemplate: Bool = false,
        creationDate: Date = Date(),
        modificationDate: Date = Date(),
        scheduledDate: Date? = nil,
        heading: String? = nil,
        headingId: String? = nil,
        start: TodoStart? = nil,
        isEvening: Bool = false,
        reminderTime: DateComponents? = nil,
        completionDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.status = status
        self.deadlineDate = deadlineDate
        self.tags = tags
        self.project = project
        self.area = area
        self.checklistItems = checklistItems
        self.startDate = startDate
        self.repeatingTemplate = repeatingTemplate
        self.isRepeatingTemplate = isRepeatingTemplate
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.scheduledDate = scheduledDate
        self.heading = heading
        self.headingId = headingId
        self.start = start
        self.isEvening = isEvening
        self.reminderTime = reminderTime
        self.completionDate = completionDate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case notes
        case status
        case deadlineDate = "dueDate"
        case tags
        case project
        case area
        case checklistItems
        case startDate
        case repeatingTemplate
        case isRepeatingTemplate
        case creationDate
        case modificationDate
        case scheduledDate
        case heading
        case headingId
        case start
        case isEvening
        case reminderTime
        case completionDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)

        // Handle status as string from JXA
        if let statusString = try? container.decode(String.self, forKey: .status) {
            status = Status(thingsStatus: statusString) ?? .open
        } else {
            status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .open
        }

        deadlineDate = try container.decodeIfPresent(Date.self, forKey: .deadlineDate)
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags) ?? []
        project = try container.decodeIfPresent(Project.self, forKey: .project)
        area = try container.decodeIfPresent(Area.self, forKey: .area)
        checklistItems = try container.decodeIfPresent([ChecklistItem].self, forKey: .checklistItems) ?? []
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        repeatingTemplate = try container.decodeIfPresent(String.self, forKey: .repeatingTemplate)
        isRepeatingTemplate = try container.decodeIfPresent(Bool.self, forKey: .isRepeatingTemplate) ?? false
        creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate) ?? Date()
        modificationDate = try container.decodeIfPresent(Date.self, forKey: .modificationDate) ?? Date()
        scheduledDate = try container.decodeIfPresent(Date.self, forKey: .scheduledDate)
        heading = try container.decodeIfPresent(String.self, forKey: .heading)
        headingId = try container.decodeIfPresent(String.self, forKey: .headingId)
        start = try container.decodeIfPresent(TodoStart.self, forKey: .start)
        isEvening = try container.decodeIfPresent(Bool.self, forKey: .isEvening) ?? false
        reminderTime = try container.decodeIfPresent(DateComponents.self, forKey: .reminderTime)
        completionDate = try container.decodeIfPresent(Date.self, forKey: .completionDate)
    }

    // MARK: - Computed Properties

    public var isCompleted: Bool { status == .completed }
    public var isCanceled: Bool { status == .canceled }
    public var isOpen: Bool { status == .open }
    public var isRecurring: Bool { isRepeatingTemplate || repeatingTemplate != nil }

    /// Whether the task is overdue (deadline day has passed and it is still open).
    /// Deadlines are calendar days, so a task due today is not overdue yet.
    public var isOverdue: Bool {
        guard status == .open, let deadline = deadlineDate else { return false }
        return deadline < Calendar.current.startOfDay(for: Date())
    }

    /// Human-readable summary for display.
    public var summary: String {
        var parts: [String] = [name]
        if let project = project {
            parts.append("[\(project.name)]")
        }
        if !tags.isEmpty {
            parts.append(tags.map { "#\($0.name)" }.joined(separator: " "))
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Todo, rhs: Todo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Filterable Conformance

extension Todo: Filterable {
    public func fieldValue(_ field: String) -> FieldValue? {
        switch field.lowercased() {
        case "id":
            return .string(id)
        case "name", "title":
            return .string(name)
        case "notes":
            return .optionalString(notes)
        case "status":
            return .string(status.rawValue)
        case "deadline", "deadlinedate", "due", "duedate":
            return .optionalDate(deadlineDate)
        case "startdate":
            return .optionalDate(startDate)
        case "recurring":
            return .bool(isRecurring)
        case "tags":
            return .stringList(tags.map { $0.name })
        case "project":
            return .optionalString(project?.name)
        case "area":
            return .optionalString(area?.name)
        case "heading":
            return .optionalString(heading)
        case "when", "scheduled":
            return .optionalDate(scheduledDate)
        case "created", "creationdate":
            return .date(creationDate)
        case "modified", "modificationdate":
            return .date(modificationDate)
        default:
            return nil
        }
    }
}
