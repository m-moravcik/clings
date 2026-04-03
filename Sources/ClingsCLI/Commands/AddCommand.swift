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
          clings add "Review docs for ProjectName"
          clings add "Task // notes go here"
          clings add "Task - checklist item 1 - checklist item 2"
        """
    )

    @Argument(help: "The todo title (supports natural language)")
    var title: String

    @Option(name: .long, help: "Add notes to the todo")
    var notes: String?

    @Option(name: .long, help: "Set the when date (today, tomorrow, etc.)")
    var when: String?

    @Option(name: .long, help: "Set the deadline")
    var deadline: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Add tags")
    var tags: [String] = []

    @Option(name: .long, help: "Add to a project")
    var project: String?

    @Option(name: .long, help: "Add to an area")
    var area: String?

    @Option(name: .long, help: "Add under a heading within the project (uses URL scheme)")
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
        if let when = when {
            parsed.whenDate = parseSimpleDate(when)
        }
        if let deadline = deadline {
            parsed.deadlineDate = parseSimpleDate(deadline)
        }

        // Handle parse-only mode
        if parseOnly {
            printParsedResult(parsed)
            return
        }

        if let heading = heading {
            // Heading requires URL scheme (no auth token needed)
            try addViaURLScheme(parsed: parsed, heading: heading)
        } else {
            let client = try ThingsClientFactory.create()
            _ = try await client.createTodo(
                name: parsed.title,
                notes: parsed.notes,
                when: parsed.whenDate,
                deadline: parsed.deadlineDate,
                tags: parsed.tags,
                project: parsed.project,
                area: parsed.area,
                checklistItems: parsed.checklistItems
            )
        }

        let outputFormatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        print(outputFormatter.format(message: "Created: \(parsed.title)"))
    }

    private func addViaURLScheme(parsed: ParsedTask, heading: String?) throws {
        var queryItems = [URLQueryItem(name: "title", value: parsed.title)]

        if let heading = heading {
            queryItems.append(URLQueryItem(name: "heading", value: heading))
        }
        if let notes = parsed.notes {
            queryItems.append(URLQueryItem(name: "notes", value: notes))
        }
        if let project = parsed.project {
            queryItems.append(URLQueryItem(name: "list", value: project))
        }
        if let area = parsed.area {
            queryItems.append(URLQueryItem(name: "list", value: area))
        }
        if let whenDate = parsed.whenDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            queryItems.append(URLQueryItem(name: "when", value: formatter.string(from: whenDate)))
        }
        if let deadlineDate = parsed.deadlineDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            queryItems.append(URLQueryItem(name: "deadline", value: formatter.string(from: deadlineDate)))
        }
        if !parsed.tags.isEmpty {
            queryItems.append(URLQueryItem(name: "tags", value: parsed.tags.joined(separator: ",")))
        }
        if !parsed.checklistItems.isEmpty {
            queryItems.append(URLQueryItem(name: "checklist-items", value: parsed.checklistItems.joined(separator: "\n")))
        }

        guard var components = URLComponents(string: "things:///add") else {
            throw ThingsError.operationFailed("Internal error: failed to parse Things URL base")
        }
        components.queryItems = queryItems
        guard let url = components.url?.absoluteString else {
            throw ThingsError.operationFailed("Failed to construct Things URL")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ThingsError.operationFailed("Failed to add via Things URL scheme (exit code \(process.terminationStatus))")
        }
    }

    private func parseSimpleDate(_ str: String) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let lower = str.lowercased()

        if lower == "today" {
            return calendar.startOfDay(for: now)
        }
        if lower == "tomorrow" {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        }
        return nil
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
