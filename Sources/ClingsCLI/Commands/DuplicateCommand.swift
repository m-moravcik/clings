// DuplicateCommand.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import ArgumentParser
import ClingsCore

struct DuplicateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "duplicate",
        abstract: "Duplicate a todo",
        discussion: """
        Creates a copy of a todo next to the original, with the same notes,
        tags, checklist and schedule. Repeating todos cannot be duplicated.

        Uses the Things URL scheme and needs an auth token
        (clings config set-auth-token). Things applies it within a few seconds.

        EXAMPLES:
          clings duplicate ABC123
        """
    )

    @Argument(help: "The ID of the todo to duplicate")
    var id: String

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let token = try AuthToken.require(for: "Duplicating a todo")
        try CommandRuntime.openURLScheme(try ThingsURLScheme.duplicateTodo(id: id, authToken: token))

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)
        print(formatter.format(message: "Duplicated todo: \(id)"))
    }
}
