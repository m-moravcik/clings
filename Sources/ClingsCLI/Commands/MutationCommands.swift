// MutationCommands.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import ArgumentParser
import ClingsCore

// MARK: - Complete Command

struct CompleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "complete",
        abstract: "Mark a todo as completed",
        discussion: """
        Marks a todo as completed by its ID or title search. The todo will
        be moved to the Logbook in Things 3.

        You can complete by ID (exact) or by title search (fuzzy):
          clings complete ABC123           By exact ID
          clings complete --title "milk"   By title search

        To find a todo's ID, use the show command or --json output:
          clings today --json | jq '.[].id'

        EXAMPLES:
          clings complete ABC123             Complete by ID
          clings done ABC123                 Alias for 'complete'
          clings complete -t "buy groceries" Complete by title search
          clings complete --title "milk"     Same as above
          clings complete ABC123 --json      Output result as JSON

        SEE ALSO:
          cancel, bulk complete, show, search
        """,
        aliases: ["done"]
    )

    @Argument(help: "The ID of the todo to complete (optional if using --title)")
    var id: String?

    @Option(name: [.short, .long], help: "Complete todo by searching its title")
    var title: String?

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let client = try ThingsClientFactory.create()

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        // Determine which mode to use
        if let searchTitle = title {
            // Search for todo by title
            let results = try await client.search(query: searchTitle)
            let openTodos = results.filter { $0.status == .open }

            switch openTodos.count {
            case 0:
                throw ThingsError.notFound("No open todos matching '\(searchTitle)'")

            case 1:
                // Exactly one match - complete it
                let todo = openTodos[0]
                try await client.completeTodo(id: todo.id)
                UndoRecorder.record(.complete, todoId: todo.id, title: todo.name, snapshot: TodoSnapshot(todo: todo))
                print(formatter.format(message: "Completed: \(todo.name)"))

            default:
                // Multiple matches - show list with IDs
                print("Multiple todos match '\(searchTitle)':")
                for (index, todo) in openTodos.prefix(10).enumerated() {
                    print("  \(index + 1). \(todo.name)")
                }
                print("\nUse the exact ID to complete:")
                for todo in openTodos.prefix(5) {
                    print("  clings complete \(todo.id)")
                }
            }
        } else if let todoId = id {
            // Original ID-based completion
            let before = await UndoRecorder.snapshot(of: todoId, using: client)
            try await client.completeTodo(id: todoId)
            UndoRecorder.record(.complete, todoId: todoId, title: before?.name ?? todoId,
                                snapshot: before.map(TodoSnapshot.init(todo:)))
            print(formatter.format(message: "Completed todo: \(todoId)"))
        } else {
            throw ValidationError("Provide either a todo ID or --title flag")
        }
    }
}

// MARK: - Reopen Command

struct ReopenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reopen",
        abstract: "Reopen a completed or canceled todo",
        discussion: """
        Reopens a todo by its ID, setting its status back to open.
        Use this to restore a todo that was completed or canceled
        by mistake.

        EXAMPLES:
          clings reopen ABC123          Reopen by ID
          clings reopen ABC123 --json   Output result as JSON

        SEE ALSO:
          complete, cancel
        """
    )

    @Argument(help: "The ID of the todo to reopen")
    var id: String

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let client = try ThingsClientFactory.create()
        let before = await UndoRecorder.snapshot(of: id, using: client)
        try await client.reopenTodo(id: id)
        if let before {
            UndoRecorder.record(.reopen, todoId: id, title: before.name, snapshot: TodoSnapshot(todo: before))
        }

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        print(formatter.format(message: "Reopened todo: \(id)"))
    }
}

// MARK: - Cancel Command

struct CancelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cancel",
        abstract: "Cancel a todo",
        discussion: """
        Cancels a todo by its ID. Canceled todos are not deleted but
        marked as canceled and moved to the Logbook.

        Use cancel for tasks that are no longer relevant, as opposed
        to complete which is for finished tasks.

        EXAMPLES:
          clings cancel ABC123          Cancel a specific todo
          clings cancel ABC123 --json   Output result as JSON

        SEE ALSO:
          complete, delete, bulk cancel
        """
    )

    @Argument(help: "The ID of the todo to cancel")
    var id: String

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let client = try ThingsClientFactory.create()
        let before = await UndoRecorder.snapshot(of: id, using: client)
        try await client.cancelTodo(id: id)
        UndoRecorder.record(.cancel, todoId: id, title: before?.name ?? id,
                            snapshot: before.map(TodoSnapshot.init(todo:)))

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        print(formatter.format(message: "Canceled todo: \(id)"))
    }
}

// MARK: - Delete Command

struct DeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a todo (moves to trash)",
        discussion: """
        Moves a todo to the Trash. `clings undo` puts it back where it was.

        For permanent deletion, empty the Trash in the Things app.

        EXAMPLES:
          clings delete ABC123          Delete a specific todo
          clings rm ABC123              Alias for 'delete'
          clings delete ABC123 -f       Skip confirmation

        SEE ALSO:
          cancel, complete
        """,
        aliases: ["rm"]
    )

    @Argument(help: "The ID of the todo to delete")
    var id: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var force = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let client = try ThingsClientFactory.create()
        let before = await UndoRecorder.snapshot(of: id, using: client)
        try await client.deleteTodo(id: id)
        if let before {
            UndoRecorder.record(.delete, todoId: id, title: before.name, snapshot: TodoSnapshot(todo: before))
        }

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        print(formatter.format(message: "Deleted todo: \(id)"))
    }
}

// MARK: - Update Command

struct UpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a todo's properties",
        discussion: """
        Update one or more properties of a todo by ID.
        Only specified options will be updated.

        Examples:
          clings update ABC123 --name "New title"
          clings update ABC123 --notes "Updated notes"
          clings update ABC123 --append-notes "Follow-up: called back"
          clings update ABC123 --deadline 2024-12-25
          clings update ABC123 --clear-deadline
          clings update ABC123 --when tomorrow
          clings update ABC123 --when 2026-10-01@14:00      (with a reminder)
          clings update ABC123 --heading "Waiting on them"
          clings update ABC123 --project "📍 Week #12"
          clings update ABC123 --area "Work"
          clings update ABC123 --tags work urgent
          clings update ABC123 --add-tags waiting
          clings update ABC123 --checklist-items "Step 1" "Step 2"
          clings update ABC123 --append-checklist-items "Extra step"
          clings update ABC123 --prepend-checklist-items "First step"

        Name, notes, deadline, tags and project work without a token. Everything
        else goes through the Things URL scheme and needs an auth token
        (clings config set-auth-token). `clings undo` restores the previous state.
        """
    )

    @Argument(help: "The ID of the todo to update")
    var id: String

    @Option(name: .long, help: "New title/name for the todo")
    var name: String?

    @Option(name: .long, help: "New notes for the todo (replaces existing)")
    var notes: String?

    @Option(name: .customLong("append-notes"), help: "Append text to the notes. Requires auth token.")
    var appendNotes: String?

    @Option(name: .customLong("prepend-notes"), help: "Prepend text to the notes. Requires auth token.")
    var prependNotes: String?

    @Option(name: .long, help: "New deadline date (YYYY-MM-DD, tomorrow, next friday, ...)")
    var deadline: String?

    @Flag(name: .customLong("clear-deadline"), help: "Remove the deadline. Requires auth token.")
    var clearDeadline = false

    @Option(name: .long, help: "Schedule: today, evening, anytime, someday, a date, or date@HH:MM for a reminder. Requires auth token.")
    var when: String?

    @Option(name: .long, help: "Move to a heading within the task's project (title or ID). Requires auth token.")
    var heading: String?

    @Option(name: .long, help: "Move to a different project (title or ID)")
    var project: String?

    @Option(name: .long, help: "Move to an area (title or ID). Requires auth token.")
    var area: String?

    @Option(name: .long, parsing: .upToNextOption, help: "New tags (replaces existing)")
    var tags: [String] = []

    @Option(name: .customLong("add-tags"), parsing: .upToNextOption, help: "Add tags, keeping existing ones. Requires auth token.")
    var addTags: [String] = []

    @Option(name: .customLong("checklist-items"), parsing: .upToNextOption, help: "Replace all checklist items. Requires auth token.")
    var checklistItems: [String] = []

    @Option(name: .customLong("append-checklist-items"), parsing: .upToNextOption, help: "Append checklist items to existing list. Requires auth token.")
    var appendChecklistItems: [String] = []

    @Option(name: .customLong("prepend-checklist-items"), parsing: .upToNextOption, help: "Prepend checklist items to existing list. Requires auth token.")
    var prependChecklistItems: [String] = []

    @OptionGroup var output: OutputOptions

    func run() async throws {
        try validateOptions()

        // Parse dates up front so bad input fails before anything changes.
        let whenSpec = try when.map { value -> WhenSpec in
            guard let spec = WhenSpec.parse(value) else {
                throw ThingsError.invalidState(
                    "Invalid --when value: '\(value)'. Use today, evening, anytime, someday, a date (YYYY-MM-DD, tomorrow, next friday) or date@HH:MM."
                )
            }
            return spec
        }
        let deadlineDate = try deadline.map { value -> Date in
            guard let day = WhenSpec.parseDay(value),
                  let date = ThingsDateConverter.calendar.date(from: day) else {
                throw ThingsError.invalidState("Invalid date format: \(value). Use YYYY-MM-DD, tomorrow, next friday, ...")
            }
            return date
        }
        let resolvedHeading = try heading.map { value -> String in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ThingsError.invalidState("--heading value cannot be empty")
            }
            guard !trimmed.contains(where: { $0.isNewline }) else {
                throw ThingsError.invalidState("--heading value cannot contain newlines")
            }
            return trimmed
        }

        let client = try ThingsClientFactory.create()
        let before = await UndoRecorder.snapshot(of: id, using: client)

        // URL scheme part: everything AppleScript/JXA cannot do.
        var attributes = TodoUpdateAttributes()
        attributes.when = whenSpec
        attributes.appendNotes = appendNotes
        attributes.prependNotes = prependNotes
        attributes.addTags = addTags.isEmpty ? nil : addTags
        if clearDeadline {
            attributes.deadline = .clear
        }
        if !checklistItems.isEmpty {
            attributes.checklist = checklistItems.map { ChecklistEntry(title: $0) }
        } else if !appendChecklistItems.isEmpty {
            attributes.appendChecklist = appendChecklistItems
        } else if !prependChecklistItems.isEmpty {
            attributes.prependChecklist = prependChecklistItems
        }
        // Only open the database when an ID has to be resolved.
        let database = (area != nil || resolvedHeading != nil) ? try? CommandRuntime.makeDatabase() : nil
        if let area {
            if let areaId = try database?.resolveAreaId(area) {
                attributes.listId = areaId
            } else if database != nil {
                throw ThingsError.notFound("Area '\(area)'")
            } else {
                attributes.list = area
            }
        }
        if let resolvedHeading {
            let projectId = before?.project?.id
            if let projectId, let headingId = try database?.resolveHeadingId(resolvedHeading, projectId: projectId) {
                attributes.headingId = headingId
            } else {
                attributes.heading = resolvedHeading
            }
        }

        // Skip what already holds: Things ignores a no-op write, which would look like a rejection.
        if let before {
            attributes = attributes.removingSatisfied(by: TodoSnapshot(todo: before))
        }

        // Check the token before any write so a missing token cannot leave a partial update.
        let token = attributes.isEmpty ? nil : try AuthToken.require(for: "This update")

        // JXA part (no token needed): name, notes, deadline, tags, project.
        let hasJXAUpdates = name != nil || notes != nil || deadlineDate != nil || !tags.isEmpty
        if hasJXAUpdates {
            try await client.updateTodo(
                id: id,
                name: name,
                notes: notes,
                deadlineDate: deadlineDate,
                tags: tags.isEmpty ? nil : tags
            )
        }
        if let project {
            try await client.moveTodo(id: id, toProject: project)
        }

        var confirmation: ChangeConfirmation.Outcome?
        if let token {
            do {
                confirmation = try await URLSchemeWrite.perform(
                    try ThingsURLScheme.updateTodo(id: id, attributes: attributes, authToken: token), itemId: id
                )
            } catch {
                if hasJXAUpdates || project != nil {
                    throw ThingsError.operationFailed(
                        "Partial update: some fields were updated, but the URL scheme update failed: \(error.localizedDescription)"
                    )
                }
                throw error
            }
        }

        if let before {
            UndoRecorder.record(.update, todoId: id, title: before.name, snapshot: TodoSnapshot(todo: before))
        }

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        let projectNote = project.map { " (moved to project '\($0)')" } ?? ""
        let urlSchemeNote = confirmation == .unknown ? " (URL scheme update sent; could not confirm it was applied)" : ""
        print(formatter.format(message: "Updated todo: \(id)\(projectNote)\(urlSchemeNote)"))
    }

    private func validateOptions() throws {
        let hasChanges = name != nil || notes != nil || appendNotes != nil || prependNotes != nil
            || deadline != nil || clearDeadline || when != nil || heading != nil || project != nil
            || area != nil || !tags.isEmpty || !addTags.isEmpty || !checklistItems.isEmpty
            || !appendChecklistItems.isEmpty || !prependChecklistItems.isEmpty
        guard hasChanges else {
            throw ThingsError.invalidState(
                "No update options provided. Use --name, --notes, --append-notes, --prepend-notes, --deadline, --clear-deadline, --when, --heading, --project, --area, --tags, --add-tags or the checklist options."
            )
        }

        let checklistModes = [!checklistItems.isEmpty, !appendChecklistItems.isEmpty, !prependChecklistItems.isEmpty]
            .filter { $0 }.count
        if checklistModes > 1 {
            throw ThingsError.invalidState("Use only one of --checklist-items, --append-checklist-items, or --prepend-checklist-items at a time.")
        }
        if deadline != nil && clearDeadline {
            throw ThingsError.invalidState("Use either --deadline or --clear-deadline, not both.")
        }
        if notes != nil && (appendNotes != nil || prependNotes != nil) {
            throw ThingsError.invalidState("--notes replaces the notes; don't combine it with --append-notes or --prepend-notes.")
        }
        if !tags.isEmpty && !addTags.isEmpty {
            throw ThingsError.invalidState("--tags replaces all tags; don't combine it with --add-tags.")
        }
        if project != nil && area != nil {
            throw ThingsError.invalidState("A todo lives in either a project or an area; use --project or --area.")
        }
    }
}
