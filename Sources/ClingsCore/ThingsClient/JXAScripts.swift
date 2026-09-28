// JXAScripts.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Refers to a Things project or area either by ID or by title.
public enum ThingsItemRef: Equatable, Sendable {
    case id(String)
    case name(String)

    /// AppleScript specifier such as `project id "X"` or `area "Work"`.
    func appleScriptSpecifier(_ className: String) -> String {
        switch self {
        case .id(let id): return "\(className) id \"\(id.appleScriptEscaped)\""
        case .name(let name): return "\(className) \"\(name.appleScriptEscaped)\""
        }
    }
}

/// JavaScript for Automation (JXA) script templates for Things 3.
public enum JXAScripts {

    // MARK: - List Queries

    /// Fetch all todos from a specific list view.
    public static func fetchList(_ listName: String) -> String {
        """
        (() => {
            const app = Application('Things3');
            const list = app.lists.byName('\(listName.jxaEscaped)');
            const todos = list.toDos();

            return JSON.stringify(todos.map(todo => {
                let proj = null;
                try {
                    const p = todo.project();
                    if (p && p.id()) {
                        proj = { id: p.id(), name: p.name() };
                    }
                } catch (e) {}

                let ar = null;
                try {
                    const a = todo.area();
                    if (a && a.id()) {
                        ar = { id: a.id(), name: a.name() };
                    }
                } catch (e) {}

                // Get checklist items safely
                let checklist = [];
                try {
                    const items = todo.checklistItems();
                    if (items && items.length > 0) {
                        checklist = items.map(ci => ({
                            id: ci.id(),
                            name: ci.name(),
                            completed: ci.status() === 'completed'
                        }));
                    }
                } catch (e) {}

                const creationDate = todo.creationDate();
                const modificationDate = todo.modificationDate();

                return {
                    id: todo.id(),
                    name: todo.name(),
                    notes: todo.notes() || null,
                    status: todo.status(),
                    dueDate: todo.dueDate() ? todo.dueDate().toISOString() : null,
                    tags: todo.tags().map(t => ({ id: t.id(), name: t.name() })),
                    project: proj,
                    area: ar,
                    checklistItems: checklist,
                    creationDate: creationDate.toISOString(),
                    modificationDate: (modificationDate ? modificationDate.toISOString() : creationDate.toISOString())
                };
            }));
        })()
        """
    }

    /// Fetch a single todo by ID.
    public static func fetchTodo(id: String) -> String {
        """
        (() => {
            const app = Application('Things3');
            const todo = app.toDos.byId('\(id.jxaEscaped)');

            if (!todo.exists()) {
                return JSON.stringify({ error: 'Todo not found', id: '\(id.jxaEscaped)' });
            }

            let proj = null;
            try {
                const p = todo.project();
                if (p && p.id()) {
                    proj = { id: p.id(), name: p.name() };
                }
            } catch (e) {}

            let ar = null;
            try {
                const a = todo.area();
                if (a && a.id()) {
                    ar = { id: a.id(), name: a.name() };
                }
            } catch (e) {}

            // Get checklist items safely
            let checklist = [];
            try {
                const items = todo.checklistItems();
                if (items && items.length > 0) {
                    checklist = items.map(ci => ({
                        id: ci.id(),
                        name: ci.name(),
                        completed: ci.status() === 'completed'
                    }));
                }
            } catch (e) {}

            const creationDate = todo.creationDate();
            const modificationDate = todo.modificationDate();

            return JSON.stringify({
                id: todo.id(),
                name: todo.name(),
                notes: todo.notes() || null,
                status: todo.status(),
                dueDate: todo.dueDate() ? todo.dueDate().toISOString() : null,
                tags: todo.tags().map(t => ({ id: t.id(), name: t.name() })),
                project: proj,
                area: ar,
                checklistItems: checklist,
                creationDate: creationDate.toISOString(),
                modificationDate: (modificationDate ? modificationDate.toISOString() : creationDate.toISOString())
            });
        })()
        """
    }

    /// Fetch all projects.
    public static func fetchProjects() -> String {
        """
        (() => {
            const app = Application('Things3');
            const projects = app.projects();

            return JSON.stringify(projects.map(proj => {
                let ar = null;
                try {
                    const a = proj.area();
                    if (a && a.id()) {
                        ar = { id: a.id(), name: a.name() };
                    }
                } catch (e) {}

                return {
                    id: proj.id(),
                    name: proj.name(),
                    notes: proj.notes() || null,
                    status: proj.status(),
                    area: ar,
                    tags: proj.tags().map(t => ({ id: t.id(), name: t.name() })),
                    dueDate: proj.dueDate() ? proj.dueDate().toISOString() : null,
                    creationDate: proj.creationDate().toISOString()
                };
            }));
        })()
        """
    }

    /// Fetch all areas.
    public static func fetchAreas() -> String {
        """
        (() => {
            const app = Application('Things3');
            const areas = app.areas();

            return JSON.stringify(areas.map(area => ({
                id: area.id(),
                name: area.name(),
                tags: area.tags().map(t => ({ id: t.id(), name: t.name() }))
            })));
        })()
        """
    }

    /// Fetch all tags.
    public static func fetchTags() -> String {
        """
        (() => {
            const app = Application('Things3');
            const tags = app.tags();

            return JSON.stringify(tags.map(tag => ({
                id: tag.id(),
                name: tag.name()
            })));
        })()
        """
    }

    // MARK: - Mutations

    /// Complete a todo by ID.
    public static func completeTodo(id: String) -> String {
        """
        (() => {
            const app = Application('Things3');
            const todo = app.toDos.byId('\(id.jxaEscaped)');

            if (!todo.exists()) {
                return JSON.stringify({ success: false, error: 'Todo not found' });
            }

            todo.status = 'completed';
            return JSON.stringify({ success: true, id: '\(id.jxaEscaped)' });
        })()
        """
    }

    /// Cancel a todo by ID.
    public static func cancelTodo(id: String) -> String {
        """
        (() => {
            const app = Application('Things3');
            const todo = app.toDos.byId('\(id.jxaEscaped)');

            if (!todo.exists()) {
                return JSON.stringify({ success: false, error: 'Todo not found' });
            }

            todo.status = 'canceled';
            return JSON.stringify({ success: true, id: '\(id.jxaEscaped)' });
        })()
        """
    }

    /// Reopen a completed or canceled todo by ID.
    public static func reopenTodo(id: String) -> String {
        """
        (() => {
            const app = Application('Things3');
            const todo = app.toDos.byId('\(id.jxaEscaped)');

            if (!todo.exists()) {
                return JSON.stringify({ success: false, error: 'Todo not found' });
            }

            const currentStatus = todo.status();
            if (currentStatus === 'open') {
                return JSON.stringify({ success: false, error: 'Todo is already open' });
            }

            todo.status = 'open';

            const newStatus = todo.status();
            if (newStatus !== 'open') {
                return JSON.stringify({ success: false, error: 'Failed to reopen todo. Things 3 may not support reopening this item.' });
            }

            return JSON.stringify({ success: true, id: '\(id.jxaEscaped)' });
        })()
        """
    }

    /// Move a todo to the Trash via AppleScript (JXA has no working delete).
    /// `delete` fails with -1728 for completed or canceled todos; moving to the
    /// Trash list works for every status.
    public static func trashTodoAppleScript(id: String) -> String {
        """
        tell application "Things3"
            move to do id "\(id.appleScriptEscaped)" to list "Trash"
            return "ok"
        end tell
        """
    }

    /// Move a todo to a built-in list ("Inbox", "Anytime", "Someday").
    /// Also restores a todo from the Trash; moving to Inbox detaches it from its project.
    public static func moveTodoToListAppleScript(id: String, list: String) -> String {
        """
        tell application "Things3"
            move to do id "\(id.appleScriptEscaped)" to list "\(list.appleScriptEscaped)"
            return "ok"
        end tell
        """
    }

    /// Move a todo to a project (by ID or title).
    public static func moveTodo(id: String, toProject projectName: String) -> String {
        """
        (() => {
            const app = Application('Things3');
            const todo = app.toDos.byId('\(id.jxaEscaped)');

            if (!todo.exists()) {
                return JSON.stringify({ success: false, error: 'Todo not found' });
            }

            // Accept a project ID or title; IDs are unambiguous when titles repeat.
            let project = app.projects.byId('\(projectName.jxaEscaped)');
            if (!project.exists()) {
                project = app.projects.byName('\(projectName.jxaEscaped)');
            }
            if (!project.exists()) {
                return JSON.stringify({ success: false, error: 'Project not found: \(projectName.jxaEscaped)' });
            }

            todo.project = project;
            return JSON.stringify({ success: true, id: '\(id.jxaEscaped)' });
        })()
        """
    }

    /// Update a todo's properties.
    public static func updateTodo(
        id: String,
        name: String? = nil,
        notes: String? = nil,
        dueDate: Date? = nil,
        tags: [String]? = nil
    ) -> String {
        let dueDateISO = dueDate.map { ISO8601DateFormatter().string(from: $0) }

        // Tags are handled via AppleScript for reliability.
        _ = tags  // Tags are applied separately.

        return """
        (() => {
            const app = Application('Things3');
            const todo = app.toDos.byId('\(id.jxaEscaped)');

            if (!todo.exists()) {
                return JSON.stringify({ success: false, error: 'Todo not found' });
            }

            \(name.map { "todo.name = '\($0.jxaEscaped)';" } ?? "")
            \(notes.map { "todo.notes = '\($0.jxaEscaped)';" } ?? "")
            \(dueDateISO.map { "todo.dueDate = new Date('\($0)');" } ?? "")

            return JSON.stringify({ success: true, id: '\(id.jxaEscaped)' });
        })()
        """
    }

    /// Update a project's properties via JXA.
    public static func updateProject(
        id: String,
        name: String? = nil,
        notes: String? = nil,
        dueDate: Date? = nil
    ) -> String {
        let dueDateISO = dueDate.map { ISO8601DateFormatter().string(from: $0) }

        return """
        (() => {
            const app = Application('Things3');
            const project = app.projects.byId('\(id.jxaEscaped)');

            if (!project.exists()) {
                return JSON.stringify({ success: false, error: 'Project not found' });
            }

            \(name.map { "project.name = '\($0.jxaEscaped)';" } ?? "")
            \(notes.map { "project.notes = '\($0.jxaEscaped)';" } ?? "")
            \(dueDateISO.map { "project.dueDate = new Date('\($0)');" } ?? "")

            return JSON.stringify({ success: true, id: '\(id.jxaEscaped)' });
        })()
        """
    }

    /// Create a new todo via AppleScript (JXA `make` throws -2710 in Things 3).
    /// Returns the ID of the created todo.
    ///
    /// Checklist items, headings, evening and reminder times cannot be set through
    /// AppleScript; callers apply them afterwards with a URL scheme update.
    public static func createTodoAppleScript(
        name: String,
        notes: String? = nil,
        when: Date? = nil,
        deadline: Date? = nil,
        project: ThingsItemRef? = nil,
        area: ThingsItemRef? = nil
    ) -> String {
        var propsList = ["name:\"\(name.appleScriptEscaped)\""]
        if let notes = notes {
            propsList.append("notes:\"\(notes.appleScriptEscaped)\"")
        }

        var lines: [String] = []
        lines.append("tell application \"Things3\"")
        lines.append("    set newTodo to make new to do with properties {\(propsList.joined(separator: ", "))}")

        // Assignment errors propagate on purpose: a missing project must not
        // silently leave the todo in the Inbox.
        if let project = project {
            lines.append("    set project of newTodo to \(project.appleScriptSpecifier("project"))")
        }
        if let area = area {
            lines.append("    set area of newTodo to \(area.appleScriptSpecifier("area"))")
        }
        if let when = when {
            // `activation date` is read-only; `schedule` is the supported way to set it.
            lines.append(contentsOf: dateBuildingLines(date: when, variable: "whenDate"))
            lines.append("    schedule newTodo for whenDate")
        }
        if let deadline = deadline {
            lines.append(contentsOf: dateBuildingLines(date: deadline, variable: "deadlineDate"))
            lines.append("    set due date of newTodo to deadlineDate")
        }

        lines.append("    return id of newTodo")
        lines.append("end tell")

        return lines.joined(separator: "\n")
    }

    /// Generate AppleScript lines that build a local-midnight date in `variable`.
    ///
    /// The day is reset to 1 before the month changes: starting from Oct 31,
    /// setting month 11 first would yield Nov 31, which AppleScript rolls to Dec 1.
    private static func dateBuildingLines(date: Date, variable: String) -> [String] {
        let components = ThingsDateConverter.calendar.dateComponents([.year, .month, .day], from: date)
        return [
            "    set \(variable) to current date",
            "    set day of \(variable) to 1",
            "    set year of \(variable) to \(components.year ?? 0)",
            "    set month of \(variable) to \(components.month ?? 1)",
            "    set day of \(variable) to \(components.day ?? 1)",
            "    set time of \(variable) to 0",
        ]
    }

    /// Create a new project with the given properties.
    public static func createProject(
        name: String,
        notes: String? = nil,
        when: Date? = nil,
        deadline: Date? = nil,
        area: String? = nil
    ) -> String {
        let whenISO = when.map { ISO8601DateFormatter().string(from: $0) }
        let deadlineISO = deadline.map { ISO8601DateFormatter().string(from: $0) }

        var propsCode = "name: '\(name.jxaEscaped)'"
        if let notes = notes, !notes.isEmpty {
            propsCode += ", notes: '\(notes.jxaEscaped)'"
        }

        return """
        (() => {
            const app = Application('Things3');

            const props = { \(propsCode) };
            const project = app.make({ new: 'project', withProperties: props });

            // Set when date
            \(whenISO.map { "project.activationDate = new Date('\($0)');" } ?? "")

            // Set deadline
            \(deadlineISO.map { "project.dueDate = new Date('\($0)');" } ?? "")

            // Add to area
            \(area.map { """
            const area = app.areas.byName('\($0.jxaEscaped)');
            if (area.exists()) {
                project.area = area;
            }
            """ } ?? "")

            return JSON.stringify({
                success: true,
                id: project.id(),
                name: project.name()
            });
        })()
        """
    }

    // MARK: - Search

    /// Search todos by query text.
    public static func search(query: String) -> String {
        """
        (() => {
            const app = Application('Things3');
            const query = '\(query.jxaEscaped)'.toLowerCase();

            const allTodos = app.toDos();
            const matches = allTodos.filter(todo => {
                const name = (todo.name() || '').toLowerCase();
                const notes = (todo.notes() || '').toLowerCase();
                return name.includes(query) || notes.includes(query);
            });

            return JSON.stringify(matches.map(todo => {
                let proj = null;
                try {
                    const p = todo.project();
                    if (p && p.id()) {
                        proj = { id: p.id(), name: p.name() };
                    }
                } catch (e) {}

                const creationDate = todo.creationDate();
                const modificationDate = todo.modificationDate();

                return {
                    id: todo.id(),
                    name: todo.name(),
                    notes: todo.notes() || null,
                    status: todo.status(),
                    dueDate: todo.dueDate() ? todo.dueDate().toISOString() : null,
                    tags: todo.tags().map(t => ({ id: t.id(), name: t.name() })),
                    project: proj,
                    creationDate: creationDate.toISOString(),
                    modificationDate: (modificationDate ? modificationDate.toISOString() : creationDate.toISOString())
                };
            }));
        })()
        """
    }

    // MARK: - Tag Management (AppleScript)

    /// Create a new tag via AppleScript.
    /// Returns the ID of the created tag.
    public static func createTagAppleScript(name: String) -> String {
        """
        tell application "Things3"
            set newTag to make new tag with properties {name:"\(name.appleScriptEscaped)"}
            return id of newTag
        end tell
        """
    }

    /// Delete a tag by name via AppleScript.
    public static func deleteTagAppleScript(name: String) -> String {
        """
        tell application "Things3"
            if exists tag "\(name.appleScriptEscaped)" then
                delete tag "\(name.appleScriptEscaped)"
                return "deleted"
            else
                error "Tag not found: \(name.appleScriptEscaped)"
            end if
        end tell
        """
    }

    /// Rename a tag via AppleScript.
    public static func renameTagAppleScript(oldName: String, newName: String) -> String {
        """
        tell application "Things3"
            if exists tag "\(oldName.appleScriptEscaped)" then
                set name of tag "\(oldName.appleScriptEscaped)" to "\(newName.appleScriptEscaped)"
                return "renamed"
            else
                error "Tag not found: \(oldName.appleScriptEscaped)"
            end if
        end tell
        """
    }

    /// Split comma-separated arguments, trim, drop empties and duplicates (order kept).
    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Set tag names for a todo via AppleScript. An empty list clears all tags.
    public static func setTodoTagsAppleScript(id: String, tags: [String]) -> String {
        setTagsAppleScript(tags: tags, itemClass: "to do", itemId: id, variable: "theTodo", label: "Todo")
    }

    /// Set tag names for a project via AppleScript. An empty list clears all tags.
    public static func setProjectTagsAppleScript(id: String, tags: [String]) -> String {
        setTagsAppleScript(tags: tags, itemClass: "project", itemId: id, variable: "theProject", label: "Project")
    }

    /// `tag names` is one comma-separated string. It is built here rather than with
    /// `list as string`, which concatenates without separators ("a" + "b" -> "ab")
    /// and makes Things create a junk tag.
    private static func setTagsAppleScript(tags: [String], itemClass: String, itemId: String,
                                           variable: String, label: String) -> String {
        let names = normalizedTags(tags)
        let tagList = names.map { "\"\($0.appleScriptEscaped)\"" }.joined(separator: ", ")
        let tagNames = names.joined(separator: ", ").appleScriptEscaped

        return """
        tell application "Things3"
            set tagNames to {\(tagList)}
            repeat with tagName in tagNames
                if not (exists tag tagName) then
                    make new tag with properties {name: tagName}
                end if
            end repeat
            set \(variable) to \(itemClass) id "\(itemId.appleScriptEscaped)"
            if not (exists \(variable)) then
                error "\(label) not found: \(itemId.appleScriptEscaped)"
            end if
            set tag names of \(variable) to "\(tagNames)"
            return "ok"
        end tell
        """
    }

    /// Check if a tag exists via AppleScript.
    public static func tagExistsAppleScript(name: String) -> String {
        """
        tell application "Things3"
            exists tag "\(name.appleScriptEscaped)"
        end tell
        """
    }
}

// MARK: - String Extension for JXA Escaping

extension String {
    /// Escape a string for safe use in JXA single-quoted strings.
    var jxaEscaped: String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Escape a string for safe use in AppleScript double-quoted strings.
    var appleScriptEscaped: String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
