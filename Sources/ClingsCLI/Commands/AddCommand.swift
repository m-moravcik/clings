// AddCommand.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import ArgumentParser
import ClingsCore
import Foundation

struct AddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a new todo with natural language support",
        discussion: """
        Supports natural language patterns:
          clings add "Buy milk tomorrow #errands"
          clings add "Call mom by friday !!"
          clings add "Review docs @ProjectName"
          clings add "Task // notes go here"
          clings add "Task - checklist item 1 - checklist item 2"

        --when accepts today, evening, anytime, someday, a date (2026-11-15,
        tomorrow, next friday) and an optional reminder time (2026-11-15@14:00).
        --project, --area and --heading accept a title or an ID.

        Evening, reminder times, headings and checklist items are applied with a
        Things URL scheme update and need an auth token (clings config set-auth-token).

        Prints the new todo's ID; `clings undo` removes it again.
        """
    )

    @Argument(help: "The todo title (supports natural language)")
    var title: String

    @Option(name: .long, help: "Add notes to the todo")
    var notes: String?

    @Option(name: .long, help: "When: today, evening, anytime, someday, a date, or date@HH:MM for a reminder")
    var when: String?

    @Option(name: .long, help: "Deadline date (YYYY-MM-DD, tomorrow, next friday, ...)")
    var deadline: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Add tags")
    var tags: [String] = []

    @Option(name: .long, help: "Add to a project (title or ID)")
    var project: String?

    @Option(name: .long, help: "Add to an area (title or ID)")
    var area: String?

    @Option(name: .long, help: "Add under a heading within the project (title or ID; requires auth token)")
    var heading: String?

    @Flag(name: .long, help: "Show parsed result without creating todo")
    var parseOnly = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let parser = TaskParser()
        var parsed = parser.parse(title)

        // Command line options override parsed values
        if let notes = notes {
            parsed.notes = notes
        }
        if !tags.isEmpty {
            parsed.tags.append(contentsOf: tags)
        }
        if let project = project {
            parsed.project = project
        }
        if let area = area {
            parsed.area = area
        }

        // Reject unparseable dates instead of silently dropping them.
        var whenSpec: WhenSpec? = parsed.whenDate.map { .day(Self.day(of: $0)) }
        if let when = when {
            guard let spec = WhenSpec.parse(when) else {
                throw ThingsError.invalidState(
                    "Invalid --when value: '\(when)'. Use today, evening, anytime, someday, a date (YYYY-MM-DD, tomorrow, next friday) or date@HH:MM."
                )
            }
            whenSpec = spec
            parsed.whenDate = spec.scheduledDay().flatMap { ThingsDateConverter.calendar.date(from: $0) }
        }
        if let deadline = deadline {
            guard let day = WhenSpec.parseDay(deadline) else {
                throw ThingsError.invalidState(
                    "Invalid --deadline value: '\(deadline)'. Use YYYY-MM-DD, tomorrow, next friday, ..."
                )
            }
            parsed.deadlineDate = ThingsDateConverter.calendar.date(from: day)
        }

        // Handle parse-only mode
        if parseOnly {
            printParsedResult(parsed)
            return
        }

        let client = try ThingsClientFactory.create()

        // Everything AppleScript cannot set is applied afterwards in one URL update.
        var followUp = TodoUpdateAttributes()
        if let whenSpec, whenSpec.requiresURLScheme {
            followUp.when = whenSpec
        }
        if !parsed.checklistItems.isEmpty {
            followUp.checklist = parsed.checklistItems.map { ChecklistEntry(title: $0) }
        }
        if let heading = heading {
            // Headings live inside a project; a heading without a project is meaningless.
            guard let headingProject = parsed.project else {
                throw ThingsError.invalidState(
                    "--heading requires a project. Use --project \"<name>\" together with --heading."
                )
            }
            let match = try await AddCommand.validateHeadingExists(heading, inProject: headingProject, using: client)
            if let match {
                followUp.headingId = match.id
            } else {
                followUp.heading = heading
            }
        }

        // Check the token before creating anything so a failure leaves nothing half-done.
        let token = followUp.isEmpty ? nil : try AuthToken.require(for: "Evening, reminder times, headings and checklists")

        let id = try await client.createTodo(
            name: parsed.title,
            notes: parsed.notes,
            when: parsed.whenDate,
            deadline: parsed.deadlineDate,
            tags: parsed.tags,
            project: parsed.project,
            area: parsed.area,
            checklistItems: []
        )
        UndoRecorder.record(.create, todoId: id, title: parsed.title, snapshot: nil)

        do {
            switch whenSpec {
            case .someday:
                try await client.moveTodoToList(id: id, list: "Someday")
            case .anytime:
                try await client.moveTodoToList(id: id, list: "Anytime")
            default:
                break
            }
            if let token {
                try await URLSchemeWrite.perform(
                    try ThingsURLScheme.updateTodo(id: id, attributes: followUp, authToken: token),
                    itemId: id
                )
            }
        } catch {
            throw ThingsError.operationFailed(
                "Created \(id) but could not finish setting it up: \(error.localizedDescription)"
            )
        }

        MutationOutput.print(message: "Created: \(parsed.title) (\(id))", id: id, output: output)
    }

    private static func day(of date: Date) -> DateComponents {
        ThingsDateConverter.calendar.dateComponents([.year, .month, .day], from: date)
    }

    /// Verify that `heading` exists in `project` before relying on the URL scheme.
    ///
    /// Things' `add` URL scheme silently ignores an unknown `heading`, so the only
    /// way to give the user useful feedback is to check the live database first.
    /// When the database is unavailable (JXA-only fallback) the check is skipped
    /// with a warning rather than blocking the operation.
    ///
    /// Static and client-injected so it can be unit tested without launching Things.
    @discardableResult
    static func validateHeadingExists(
        _ heading: String,
        inProject project: String,
        using client: any ThingsClientProtocol
    ) async throws -> Heading? {
        let headings: [Heading]
        do {
            headings = try await client.fetchHeadings(projectId: project)
        } catch ThingsError.invalidState {
            // SQLite not available (JXA-only client). Cannot validate; warn and proceed.
            FileHandle.standardError.write(Data(
                "Warning: cannot verify heading '\(heading)' (database unavailable); proceeding.\n".utf8
            ))
            return nil
        }

        guard let matched = headings.first(where: { $0.title == heading || $0.id == heading }) else {
            let available = headings.isEmpty
                ? "Project has no headings."
                : "Available headings: \(headings.map { "\"\($0.title)\"" }.joined(separator: ", "))."
            throw ThingsError.notFound(
                """
                Heading '\(heading)' not found in project '\(project)'.
                \(available)
                Things cannot create headings in an existing project. Create the heading in the \
                Things UI, or create a new project with headings via:
                  clings project add "<name>" --heading "\(heading)"
                """
            )
        }
        return matched
    }

    private func printParsedResult(_ parsed: ParsedTask) {
        let dateFormatter = ISO8601DateFormatter()

        if output.json {
            var jsonDict: [String: Any] = [
                "title": parsed.title,
            ]
            if let notes = parsed.notes {
                jsonDict["notes"] = notes
            }
            if !parsed.tags.isEmpty {
                jsonDict["tags"] = parsed.tags
            }
            if let project = parsed.project {
                jsonDict["project"] = project
            }
            if let area = parsed.area {
                jsonDict["area"] = area
            }
            if let whenDate = parsed.whenDate {
                jsonDict["when"] = dateFormatter.string(from: whenDate)
            }
            if let dueDate = parsed.deadlineDate {
                jsonDict["deadline"] = dateFormatter.string(from: dueDate)
            }
            if !parsed.checklistItems.isEmpty {
                jsonDict["checklistItems"] = parsed.checklistItems
            }

            if let data = try? JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            let useColors = !output.noColor
            let bold = useColors ? "\u{001B}[1m" : ""
            let cyan = useColors ? "\u{001B}[36m" : ""
            let dim = useColors ? "\u{001B}[2m" : ""
            let reset = useColors ? "\u{001B}[0m" : ""

            print("\(bold)Parsed Task\(reset)")
            print("\(dim)─────────────────────────────────────\(reset)")
            print("  Title:    \(parsed.title)")

            if let notes = parsed.notes {
                print("  Notes:    \(notes)")
            }
            if !parsed.tags.isEmpty {
                print("  Tags:     \(cyan)\(parsed.tags.map { "#\($0)" }.joined(separator: " "))\(reset)")
            }
            if let project = parsed.project {
                print("  Project:  \(project)")
            }
            if let area = parsed.area {
                print("  Area:     \(area)")
            }
            if let whenDate = parsed.whenDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                print("  When:     \(formatter.string(from: whenDate))")
            }
            if let dueDate = parsed.deadlineDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                print("  Deadline: \(formatter.string(from: dueDate))")
            }
            if !parsed.checklistItems.isEmpty {
                print("  Checklist:")
                for item in parsed.checklistItems {
                    print("    - \(item)")
                }
            }
            print("")
        }
    }
}
