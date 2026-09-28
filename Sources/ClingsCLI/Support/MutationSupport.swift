// MutationSupport.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import ClingsCore
import Foundation

/// Loads the Things auth token with an actionable error when it is missing.
enum AuthToken {
    static func require(for purpose: String) throws -> String {
        do {
            return try CommandRuntime.loadAuthToken()
        } catch {
            throw ThingsError.invalidState(
                """
                \(purpose) requires a Things auth token.
                Get it from Things → Settings → General → Enable Things URLs → Manage, then run:
                  clings config set-auth-token <token>
                """
            )
        }
    }
}

/// A URL scheme write that is confirmed against the database.
enum URLSchemeWrite {
    /// Open `url` and wait until Things has applied it to `itemId`.
    /// Throws when Things demonstrably ignored the write (usually shown as an error dialog in Things).
    @discardableResult
    static func perform(_ url: String, itemId: String) async throws -> ChangeConfirmation.Outcome {
        let waitForChange = CommandRuntime.watchForChange(itemId)
        try CommandRuntime.openURLScheme(url)
        let outcome = await waitForChange()
        if outcome == .notApplied {
            throw ThingsError.operationFailed(
                "Things did not apply the change to \(itemId) within 8 seconds. It may be showing an error message; check the Things window."
            )
        }
        return outcome
    }
}

/// Records undo history. Failing to record never fails the mutation itself.
enum UndoRecorder {
    /// Test hook: redirect history away from ~/.config/clings.
    nonisolated(unsafe) static var storeOverride: UndoStore?

    static func store() throws -> UndoStore {
        try storeOverride ?? UndoStore.standard()
    }

    static func record(_ entries: [UndoEntry]) {
        do {
            try store().record(entries)
        } catch {
            warn("could not record undo history: \(error.localizedDescription)")
        }
    }

    static func record(_ operation: UndoOperation, todoId: String, title: String, snapshot: TodoSnapshot?) {
        record([UndoEntry(batchId: nil, operation: operation, todoId: todoId, title: title, snapshot: snapshot)])
    }

    /// Snapshot a to-do before mutating it. Returns nil (with a warning) when it cannot be read,
    /// so the mutation still goes ahead.
    static func snapshot(of id: String, using client: any ThingsClientProtocol) async -> Todo? {
        do {
            return try await client.fetchTodo(id: id)
        } catch {
            warn("could not snapshot \(id) for undo: \(error.localizedDescription)")
            return nil
        }
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("Warning: \(message)\n".utf8))
    }
}

/// Output for mutations that produce or touch a single item.
enum MutationOutput {
    private struct Response: Encodable {
        let message: String
        let id: String
    }

    static func print(message: String, id: String, output: OutputOptions) {
        guard output.json else {
            Swift.print(message)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(Response(message: message, id: id))) ?? Data("{}".utf8)
        Swift.print(String(data: data, encoding: .utf8) ?? "{}")
    }
}
