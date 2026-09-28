// UndoCommand.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import ArgumentParser
import ClingsCore
import Foundation

struct UndoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "undo",
        abstract: "Undo the most recent change made with clings",
        discussion: """
        Reverses the most recent write recorded by clings. A bulk command is
        undone as a whole.

          add        moves the new todo to the Trash
          update     restores the previous title, notes, schedule, reminder,
                     deadline, tags, project/area/heading and checklist
          complete   reopens the todo
          cancel     reopens the todo
          reopen     completes or cancels it again
          delete     takes it out of the Trash, back to its list

        Restoring an update (or a scheduled todo from the Trash) goes through the
        Things URL scheme and needs an auth token. The last 50 changes are kept in
        ~/.config/clings/undo-history.json. Changes made in the Things app itself
        are not tracked.

        EXAMPLES:
          clings undo            Undo the latest change
          clings undo --show     Show what would be undone
          clings undo --list     Show the recent history
        """
    )

    @Flag(name: .long, help: "Show the latest change without undoing it")
    var show = false

    @Flag(name: .long, help: "List recent undo history")
    var list = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let store = try UndoRecorder.store()

        if list {
            render(try store.entries())
            return
        }

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        let group = try store.latestGroup()
        guard !group.isEmpty else {
            print(formatter.format(message: "Nothing to undo"))
            return
        }

        if show {
            render(group)
            return
        }

        let client = try ThingsClientFactory.create()

        // Restores compare against the current state so unchanged fields are not re-sent.
        var plans: [(UndoEntry, [UndoStep])] = []
        for entry in group {
            let current = entry.operation == .update
                ? (try? await client.fetchTodo(id: entry.todoId)).map(TodoSnapshot.init(todo:))
                : nil
            plans.append((entry, try UndoPlanner.steps(for: entry, current: current)))
        }
        let token = plans.contains { UndoPlanner.requiresAuthToken($0.1) }
            ? try AuthToken.require(for: "Undoing this change")
            : nil

        var undone: Set<UUID> = []
        do {
            for (entry, steps) in plans {
                for step in steps {
                    try await apply(step, client: client, token: token)
                }
                undone.insert(entry.id)
            }
        } catch {
            // Keep whatever did not complete so the user can retry.
            try store.remove(entryIds: undone)
            throw ThingsError.operationFailed(
                "Undo stopped after \(undone.count) of \(group.count) item(s): \(error.localizedDescription)"
            )
        }
        try store.remove(entryIds: undone)

        let summary = group.count == 1
            ? "Undid \(group[0].operation.rawValue): \(group[0].title)"
            : "Undid \(group[0].operation.rawValue) of \(group.count) todos"
        print(formatter.format(message: summary))
    }

    private func apply(_ step: UndoStep, client: any ThingsClientProtocol, token: String?) async throws {
        switch step {
        case .trash(let id):
            try await client.deleteTodo(id: id)
        case .reopen(let id):
            try await client.reopenTodo(id: id)
        case .complete(let id):
            try await client.completeTodo(id: id)
        case .cancel(let id):
            try await client.cancelTodo(id: id)
        case .moveToList(let id, let list):
            try await client.moveTodoToList(id: id, list: list)
        case .setTags(let id, let tags):
            try await client.updateTodo(id: id, name: nil, notes: nil, deadlineDate: nil, tags: tags)
        case .update(let id, let attributes):
            guard let token else {
                throw ThingsError.invalidState("Missing auth token")
            }
            try await URLSchemeWrite.perform(
                try ThingsURLScheme.updateTodo(id: id, attributes: attributes, authToken: token), itemId: id
            )
        }
    }

    private func render(_ entries: [UndoEntry]) {
        if output.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = (try? encoder.encode(entries)) ?? Data("[]".utf8)
            print(String(data: data, encoding: .utf8) ?? "[]")
            return
        }
        if entries.isEmpty {
            print("No undo history")
            return
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        for entry in entries {
            let batch = entry.batchId.map { " [bulk \($0.uuidString.prefix(8))]" } ?? ""
            print("\(formatter.string(from: entry.createdAt))  \(entry.operation.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0))  \(entry.title) (\(entry.todoId))\(batch)")
        }
    }
}
