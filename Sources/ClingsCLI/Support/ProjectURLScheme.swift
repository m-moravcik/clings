// ProjectURLScheme.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import ClingsCore
import Foundation

/// Builds and invokes the Things `json` URL scheme to create a project with headings.
///
/// Headings are the only project feature that cannot be set through the
/// AppleScript/JXA automation API (Things has no `heading` class) nor through
/// the simple `add-project` command (whose `to-dos` parameter is plain
/// newline-separated text, not structured items). The `json` command is the
/// only programmatic way to create headings — it nests them inside the
/// project's `items` array — and it requires an auth token.
enum ProjectURLScheme {
    // MARK: - JSON payload model (Things `json` command schema)

    private struct Operation: Encodable {
        let type = "project"
        let attributes: ProjectAttributes
    }

    private struct ProjectAttributes: Encodable {
        let title: String
        var notes: String?
        var area: String?
        var when: String?
        var deadline: String?
        var tags: [String]?
        var items: [Item]
    }

    private struct Item: Encodable {
        let type = "heading"
        let attributes: ItemAttributes
    }

    private struct ItemAttributes: Encodable {
        let title: String
    }

    /// Construct the `things:///json` URL string for creating a project with headings.
    ///
    /// Pure and side-effect free so it can be unit tested without launching Things.
    static func buildURL(
        title: String,
        notes: String?,
        area: String?,
        when: Date?,
        deadline: Date?,
        tags: [String],
        headings: [String],
        authToken: String
    ) throws -> String {
        let attributes = ProjectAttributes(
            title: title,
            notes: (notes?.isEmpty ?? true) ? nil : notes,
            area: (area?.isEmpty ?? true) ? nil : area,
            when: when.map { Self.dateString($0) },
            deadline: deadline.map { Self.dateString($0) },
            tags: tags.isEmpty ? nil : tags,
            items: headings.map { Item(attributes: .init(title: $0)) }
        )

        let encoder = JSONEncoder()
        // Stable key order keeps URLs deterministic for tests; Things ignores order.
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode([Operation(attributes: attributes)])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ThingsError.operationFailed("Failed to encode project JSON")
        }

        guard var components = URLComponents(string: "things:///json") else {
            throw ThingsError.operationFailed("Internal error: failed to parse Things URL base")
        }
        components.queryItems = [
            URLQueryItem(name: "data", value: json),
            URLQueryItem(name: "auth-token", value: authToken),
        ]
        guard let url = components.url?.absoluteString else {
            throw ThingsError.operationFailed("Failed to construct Things json URL")
        }
        return url
    }

    /// Build the URL and open it, creating the project (with headings) in Things.
    ///
    /// Requires a stored auth token (the `json` command rejects write operations
    /// without one). Throws an actionable error when the token is missing.
    static func addProject(
        title: String,
        notes: String?,
        area: String?,
        when: Date?,
        deadline: Date?,
        tags: [String],
        headings: [String]
    ) throws {
        let authToken: String
        do {
            authToken = try AuthTokenStore.loadToken()
        } catch {
            throw ThingsError.invalidState(
                """
                Creating a project with headings requires a Things auth token.
                Get it from Things → Settings → General → Enable Things URLs → Manage, then run:
                  clings config set-auth-token <token>
                """
            )
        }

        let url = try buildURL(
            title: title,
            notes: notes,
            area: area,
            when: when,
            deadline: deadline,
            tags: tags,
            headings: headings,
            authToken: authToken
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ThingsError.operationFailed(
                "Failed to create project via Things URL scheme (exit code \(process.terminationStatus))"
            )
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
