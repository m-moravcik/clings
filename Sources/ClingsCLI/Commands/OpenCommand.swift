// OpenCommand.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import ArgumentParser
import ClingsCore
import Foundation

struct OpenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open a todo, project, area, tag or list in Things 3",
        discussion: """
        Brings Things 3 to the front and shows the target. Needs no auth token.

        TARGETS:
          A built-in list: inbox, today, anytime, upcoming, someday, logbook,
          tomorrow, deadlines, repeating, all-projects, logged-projects
          An ID of a todo, project or area
          Anything else is looked up by name (area, project, tag or list)

        EXAMPLES:
          clings open today                  Open Today
          clings open ABC123                 Reveal a todo or project by ID
          clings open "Work"                 Open the Work area or project
          clings open today --filter urgent  Today, filtered to #urgent

        SEE ALSO:
          show, today, inbox
        """
    )

    @Argument(help: "A built-in list, an ID, or the name of an area, project or tag")
    var target: String

    @Option(name: .long, parsing: .upToNextOption, help: "Only show items with these tags")
    var filter: [String] = []

    func run() async throws {
        let url: String
        let lowered = target.lowercased()
        if ThingsURLScheme.builtInListIds.contains(lowered) && filter.isEmpty {
            url = try ThingsURLScheme.show(id: lowered)
        } else if Self.looksLikeThingsId(target) && filter.isEmpty {
            url = try ThingsURLScheme.show(id: target)
        } else {
            url = try ThingsURLScheme.show(query: target, filterTags: filter)
        }
        try CommandRuntime.openURLScheme(url)
    }

    /// Things IDs are 21-22 base62 characters (older items may be UUIDs).
    static func looksLikeThingsId(_ value: String) -> Bool {
        let base62 = value.range(of: #"^[A-Za-z0-9]{21,22}$"#, options: .regularExpression) != nil
        let hasDigit = value.contains { $0.isNumber }
        return (base62 && hasDigit) || UUID(uuidString: value) != nil
    }
}
