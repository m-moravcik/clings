// ProjectCommands.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import ArgumentParser
import ClingsCore
import Foundation

// MARK: - Project Command (Parent)

struct ProjectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "project",
        abstract: "Manage projects",
        discussion: """
        List and create projects in Things 3.

        Projects are containers for related todos working toward a specific goal.

        EXAMPLES:
          clings project                    List all projects (same as 'clings projects')
          clings project list               Same as above
          clings project add "Q1 Planning"  Create a new project
          clings project add "Sprint" --area "Work" --deadline 2025-01-31

        SEE ALSO:
          projects, add --project, areas
        """,
        subcommands: [
            ProjectListCommand.self,
            ProjectAddCommand.self,
            ProjectUpdateCommand.self,
            ProjectHeadingsCommand.self,
        ],
        defaultSubcommand: ProjectListCommand.self
    )
}

// MARK: - Project List Command

struct ProjectListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all projects",
        aliases: ["ls"]
    )

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let client = try ThingsClientFactory.create()
        let projects = try await client.fetchProjects()

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        print(formatter.format(projects: projects))
    }
}

// MARK: - Project Add Command

struct ProjectAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Create a new project",
        discussion: """
        Creates a new project in Things 3.

        Use --heading (repeatable) to create the project with headings in one shot.
        Headings cannot be added to an existing project afterwards (Things API
        limitation), so define them here when the project is created.

        EXAMPLES:
          clings project add "Q1 Planning"
          clings project add "Feature X" --notes "Implementation of feature X"
          clings project add "Sprint 12" --area "Work" --when today
          clings project add "Vacation" --deadline 2025-06-01 --tags "personal,planning"
          clings project add "June 2026" --heading "Week 1" --heading "Week 2"
        """
    )

    @Argument(help: "Title of the project")
    var title: String

    @Option(name: .long, help: "Project notes/description")
    var notes: String?

    @Option(name: .long, help: "Area to assign project to")
    var area: String?

    @Option(name: .long, help: "When to start (today, tomorrow, YYYY-MM-DD)")
    var when: String?

    @Option(name: .long, help: "Deadline date (YYYY-MM-DD)")
    var deadline: String?

    @Option(name: .long, help: "Tags (comma-separated)")
    var tags: String?

    @Option(name: .long, parsing: .singleValue, help: "Heading to create in the project (repeatable, order preserved)")
    var heading: [String] = []

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw ThingsError.invalidState("Project title cannot be empty")
        }

        let parsedWhen = try when.map { try parseWhenDate($0) }
        let parsedDeadline = try deadline.map { try parseWhenDate($0) }
        let tagList = tags?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? []

        let cleanedHeadings = heading
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if cleanedHeadings.isEmpty {
            // No headings: keep the safe JXA path (official automation API).
            let client = try ThingsClientFactory.create()
            _ = try await client.createProject(
                name: trimmedTitle,
                notes: notes,
                when: parsedWhen,
                deadline: parsedDeadline,
                tags: tagList,
                area: area
            )
        } else {
            // Headings require the URL scheme: Things' AppleScript/JXA API has no
            // heading class, so add-project's to-dos JSON is the only programmatic way.
            try ProjectURLScheme.addProject(
                title: trimmedTitle,
                notes: notes,
                area: area,
                when: parsedWhen,
                deadline: parsedDeadline,
                tags: tagList,
                headings: cleanedHeadings
            )
        }

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        print(formatter.format(message: "Created project: \(trimmedTitle)"))
    }

    private func parseWhenDate(_ str: String) throws -> Date {
        let lower = str.lowercased()
        let calendar = Calendar.current
        let now = Date()

        if lower == "today" {
            return calendar.startOfDay(for: now)
        }
        if lower == "tomorrow" {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
                return tomorrow
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        if let date = formatter.date(from: str) {
            return date
        }
        throw ThingsError.invalidState("Invalid date format: \(str). Use YYYY-MM-DD, 'today', or 'tomorrow'.")
    }
}

// MARK: - Project Update Command

struct ProjectUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a project's properties",
        discussion: """
        Update one or more properties of a project by ID.
        Only specified options will be updated.

        Name, notes, deadline and tags work without a token. Scheduling, moving
        to another area, appending notes, adding tags and clearing the deadline go
        through the Things URL scheme and need an auth token.

        EXAMPLES:
          clings project update <uuid> --name "New Title"
          clings project update <uuid> --notes "Updated notes"
          clings project update <uuid> --append-notes "Status: on hold"
          clings project update <uuid> --deadline 2025-06-01
          clings project update <uuid> --clear-deadline
          clings project update <uuid> --when someday
          clings project update <uuid> --area "Work"
          clings project update <uuid> --tags work planning
          clings project update <uuid> --add-tags waiting
        """
    )

    @Argument(help: "The ID of the project to update")
    var id: String

    @Option(name: .long, help: "New name for the project")
    var name: String?

    @Option(name: .long, help: "New notes for the project (replaces existing)")
    var notes: String?

    @Option(name: .customLong("append-notes"), help: "Append text to the notes. Requires auth token.")
    var appendNotes: String?

    @Option(name: .customLong("prepend-notes"), help: "Prepend text to the notes. Requires auth token.")
    var prependNotes: String?

    @Option(name: .long, help: "New deadline date (YYYY-MM-DD, tomorrow, next friday, ...)")
    var deadline: String?

    @Flag(name: .customLong("clear-deadline"), help: "Remove the deadline. Requires auth token.")
    var clearDeadline = false

    @Option(name: .long, help: "Schedule: today, evening, anytime, someday or a date. Requires auth token.")
    var when: String?

    @Option(name: .long, help: "Move to an area (title or ID). Requires auth token.")
    var area: String?

    @Option(name: .long, parsing: .upToNextOption, help: "New tags (replaces existing)")
    var tags: [String] = []

    @Option(name: .customLong("add-tags"), parsing: .upToNextOption, help: "Add tags, keeping existing ones. Requires auth token.")
    var addTags: [String] = []

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let hasChanges = name != nil || notes != nil || appendNotes != nil || prependNotes != nil
            || deadline != nil || clearDeadline || when != nil || area != nil || !tags.isEmpty || !addTags.isEmpty
        guard hasChanges else {
            throw ThingsError.invalidState(
                "No update options provided. Use --name, --notes, --append-notes, --prepend-notes, --deadline, --clear-deadline, --when, --area, --tags or --add-tags."
            )
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

        let deadlineDate = try deadline.map { value -> Date in
            guard let day = WhenSpec.parseDay(value),
                  let date = ThingsDateConverter.calendar.date(from: day) else {
                throw ThingsError.invalidState("Invalid date format: \(value). Use YYYY-MM-DD, tomorrow, next friday, ...")
            }
            return date
        }

        var attributes = ProjectUpdateAttributes()
        attributes.appendNotes = appendNotes
        attributes.prependNotes = prependNotes
        attributes.addTags = addTags.isEmpty ? nil : addTags
        if clearDeadline {
            attributes.deadline = .clear
        }
        if let when {
            guard let spec = WhenSpec.parse(when), !spec.isReminder else {
                throw ThingsError.invalidState(
                    "Invalid --when value: '\(when)'. Use today, evening, anytime, someday or a date."
                )
            }
            attributes.when = spec
        }
        if let area {
            guard let areaId = try CommandRuntime.makeDatabase().resolveAreaId(area) else {
                throw ThingsError.notFound("Area '\(area)'")
            }
            attributes.areaId = areaId
        }
        let token = attributes.isEmpty ? nil : try AuthToken.require(for: "This project update")

        let client = try ThingsClientFactory.create()
        if name != nil || notes != nil || deadlineDate != nil || !tags.isEmpty {
            try await client.updateProject(
                id: id,
                name: name,
                notes: notes,
                deadlineDate: deadlineDate,
                tags: tags.isEmpty ? nil : tags
            )
        }
        if let token {
            try await URLSchemeWrite.perform(
                try ThingsURLScheme.updateProject(id: id, attributes: attributes, authToken: token), itemId: id
            )
        }

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        print(formatter.format(message: "Updated project: \(id)"))
    }
}

// MARK: - Project Headings Command

struct ProjectHeadingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "headings",
        abstract: "List headings in a project",
        discussion: """
        Lists all headings defined in a project. Accepts project name or UUID.
        Useful for scripting --heading values in 'add' and 'update' commands.

        EXAMPLES:
          clings project headings "Week #9"
          clings project headings <uuid>
          clings project headings "Week #9" --json
        """
    )

    @Argument(help: "Project name or UUID")
    var project: String

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let client = try ThingsClientFactory.create()
        let headings = try await client.fetchHeadings(projectId: project)

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        print(formatter.format(headings: headings))
    }
}
