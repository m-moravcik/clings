// CommandRuntime.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import ClingsCore
import Foundation

enum CommandRuntime {
    @TaskLocal static var makeClient: @Sendable () -> any ThingsClientProtocol = {
        (try? ThingsClientFactory.create()) ?? ThingsClient()
    }

    @TaskLocal static var makeDatabase: @Sendable () throws -> ThingsDatabase = {
        try ThingsDatabase()
    }

    @TaskLocal static var inputReader: @Sendable () -> String? = {
        Swift.readLine()
    }

    @TaskLocal static var loadAuthToken: @Sendable () throws -> String = {
        try AuthTokenStore.loadToken()
    }

    /// Start watching an item before a URL scheme write. The returned closure waits
    /// until Things applies the write (see `ChangeConfirmation`). Throws when the database
    /// shows the item does not exist or is in the Trash: Things would never apply the write.
    @TaskLocal static var watchForChange: @Sendable (String) throws -> @Sendable () async -> ChangeConfirmation.Outcome = { id in
        guard let database = try? CommandRuntime.makeDatabase() else {
            return { .unknown }
        }
        let lookup: Date?
        let trashed: Bool
        do {
            lookup = try database.modificationDate(of: id)
            trashed = try database.isTrashed(id)
        } catch {
            return { .unknown }
        }
        guard let before = lookup else {
            throw ThingsError.notFound(id)
        }
        if trashed {
            throw ThingsError.invalidState("\(id) is in the Trash; Things ignores changes to it. Restore it first (clings undo or the Things app).")
        }
        return {
            await ChangeConfirmation.waitForChange(before: before) {
                guard let date = try database.modificationDate(of: id) else {
                    throw ThingsError.notFound(id)
                }
                return date
            }
        }
    }

    @TaskLocal static var openURLScheme: @Sendable (String) throws -> Void = { urlString in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // -g keeps Things in the background; URL scheme writes don't need focus.
        process.arguments = ["-g", urlString]
        do {
            try process.run()
        } catch {
            throw ThingsError.operationFailed("Failed to launch Things URL scheme handler: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ThingsError.operationFailed("Failed to update via Things URL scheme (exit code \(process.terminationStatus))")
        }
    }
}
