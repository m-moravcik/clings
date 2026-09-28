// UndoPlanner.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A single write that reverses part of a recorded mutation.
public enum UndoStep: Equatable, Sendable {
    case trash(todoId: String)
    case reopen(todoId: String)
    case complete(todoId: String)
    case cancel(todoId: String)
    /// AppleScript move to "Inbox", "Anytime" or "Someday". Also restores from the Trash.
    case moveToList(todoId: String, list: String)
    /// AppleScript tag replacement; unlike the URL scheme it can also clear all tags.
    case setTags(todoId: String, tags: [String])
    /// URL scheme update (needs the auth token).
    case update(todoId: String, attributes: TodoUpdateAttributes)
}

/// Turns undo entries into concrete steps. Pure, so the restore logic is testable
/// without Things.
///
/// Why the steps look the way they do (verified against Things 3.24):
/// - only a move to the Inbox detaches a to-do from its project; Anytime/Someday keep it
/// - a trashed to-do keeps its project, and a list move brings it back (reopened)
/// - `list-id` without `heading-id` drops the heading, so both are always sent
/// - clearing a deadline is only possible through the URL scheme
/// - clearing tags is only possible through AppleScript (`tags: []` is ignored)
/// - scheduling a plain day keeps an existing reminder; a pass through Someday clears it
public enum UndoPlanner {
    /// - Parameter current: the to-do as it is now. When given, a restore only sends what
    ///   differs, so a no-op never reaches Things (which would not confirm it).
    public static func steps(for entry: UndoEntry, current: TodoSnapshot? = nil) throws -> [UndoStep] {
        let id = entry.todoId
        switch entry.operation {
        case .create:
            return [.trash(todoId: id)]
        case .complete, .cancel:
            return [.reopen(todoId: id)]
        case .reopen:
            switch try snapshot(of: entry).status {
            case .completed: return [.complete(todoId: id)]
            case .canceled: return [.cancel(todoId: id)]
            case .open: return []
            }
        case .delete:
            return untrashSteps(id: id, snapshot: try snapshot(of: entry))
        case .update:
            return restoreSteps(id: id, snapshot: try snapshot(of: entry), current: current)
        }
    }

    public static func requiresAuthToken(_ steps: [UndoStep]) -> Bool {
        steps.contains { if case .update = $0 { return true } else { return false } }
    }

    private static func snapshot(of entry: UndoEntry) throws -> TodoSnapshot {
        guard let snapshot = entry.snapshot else {
            throw ThingsError.invalidState("Undo entry for \(entry.operation.rawValue) \(entry.todoId) has no snapshot")
        }
        return snapshot
    }

    /// Trash keeps every field, so a list move is enough unless the to-do was scheduled.
    private static func untrashSteps(id: String, snapshot: TodoSnapshot) -> [UndoStep] {
        var steps: [UndoStep] = [.moveToList(todoId: id, list: listName(snapshot.start))]
        if snapshot.startDay != nil, let when = when(for: snapshot) {
            var attributes = TodoUpdateAttributes()
            attributes.when = when
            steps.append(.update(todoId: id, attributes: attributes))
        }
        // Leaving the Trash reopens the to-do; put a logged one back in the Logbook.
        switch snapshot.status {
        case .completed: steps.append(.complete(todoId: id))
        case .canceled: steps.append(.cancel(todoId: id))
        case .open: break
        }
        return steps
    }

    private static func restoreSteps(id: String, snapshot: TodoSnapshot, current: TodoSnapshot?) -> [UndoStep] {
        var steps: [UndoStep] = []
        var attributes = TodoUpdateAttributes()
        attributes.title = snapshot.title
        attributes.notes = snapshot.notes
        attributes.deadline = snapshot.deadline.map { .set($0) } ?? .clear
        attributes.checklist = snapshot.checklist

        // Steps that reset the schedule force `when` to be sent even if it matched before.
        var scheduleReset = false

        if let listId = snapshot.projectId ?? snapshot.areaId {
            attributes.listId = listId
            attributes.headingId = snapshot.headingId
            attributes.when = when(for: snapshot)
        } else {
            // Loose to-do: the Inbox move is the only way to drop a project or area.
            let currentHasContainer = current.map { $0.projectId != nil || $0.areaId != nil } ?? true
            let needsInbox = current == nil || currentHasContainer
                || (snapshot.start == .inbox && current?.start != .inbox)
            if needsInbox {
                steps.append(.moveToList(todoId: id, list: "Inbox"))
                scheduleReset = true
            }
            if snapshot.start != .inbox {
                if snapshot.startDay == nil {
                    let needsBucket = needsInbox || current?.start != snapshot.start || current?.startDay != nil
                    if needsBucket {
                        steps.append(.moveToList(todoId: id, list: listName(snapshot.start)))
                    }
                } else {
                    attributes.when = when(for: snapshot)
                }
            }
        }

        if current == nil || Set(current?.tags ?? []) != Set(snapshot.tags) {
            steps.append(.setTags(todoId: id, tags: snapshot.tags))
        }

        let clearsReminder = snapshot.startDay != nil && snapshot.reminderTime == nil
            && (current == nil || current?.reminderTime != nil)
        if clearsReminder {
            // A plain day keeps whatever reminder the to-do has now; Someday clears it.
            var clearReminder = TodoUpdateAttributes()
            clearReminder.when = .someday
            steps.append(.update(todoId: id, attributes: clearReminder))
            scheduleReset = true
        }

        if let current {
            let restoredWhen = attributes.when
            attributes = attributes.removingSatisfied(by: current)
            if scheduleReset {
                attributes.when = restoredWhen
            }
        }
        if !attributes.isEmpty {
            steps.append(.update(todoId: id, attributes: attributes))
        }
        return steps
    }

    private static func when(for snapshot: TodoSnapshot) -> WhenSpec? {
        if let day = snapshot.startDay {
            if let time = snapshot.reminderTime {
                var components = day
                components.hour = time.hour
                components.minute = time.minute
                return .dayAndTime(components)
            }
            let today = ThingsDateConverter.calendar.dateComponents([.year, .month, .day], from: Date())
            if snapshot.isEvening && day == today {
                return .evening
            }
            return .day(day)
        }
        switch snapshot.start {
        case .someday: return .someday
        case .anytime: return .anytime
        case .inbox, nil: return nil
        }
    }

    private static func listName(_ start: TodoStart?) -> String {
        switch start {
        case .inbox: return "Inbox"
        case .someday: return "Someday"
        case .anytime, nil: return "Anytime"
        }
    }
}
