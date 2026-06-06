// ProjectURLSchemeTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import ClingsCLI

@Suite("ProjectURLScheme")
struct ProjectURLSchemeTests {
    /// Decode the query of a built URL into a [name: value] map.
    private func queryItems(of urlString: String) throws -> [String: String] {
        let components = try #require(URLComponents(string: urlString))
        var map: [String: String] = [:]
        for item in components.queryItems ?? [] {
            map[item.name] = item.value
        }
        return map
    }

    /// Decode the `data` query parameter back into the JSON object array.
    private func dataPayload(of urlString: String) throws -> [[String: Any]] {
        let items = try queryItems(of: urlString)
        let json = try #require(items["data"])
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        return try #require(decoded)
    }

    @Test func usesJSONCommandBase() throws {
        let url = try ProjectURLScheme.buildURL(
            title: "P", notes: nil, area: nil, when: nil, deadline: nil,
            tags: [], headings: ["H1"], authToken: "tok"
        )
        #expect(url.hasPrefix("things:///json?"))
    }

    @Test func includesAuthToken() throws {
        let url = try ProjectURLScheme.buildURL(
            title: "P", notes: nil, area: nil, when: nil, deadline: nil,
            tags: [], headings: ["H1"], authToken: "secret-token"
        )
        let items = try queryItems(of: url)
        #expect(items["auth-token"] == "secret-token")
    }

    @Test func payloadIsProjectWithTitle() throws {
        let payload = try dataPayload(of: ProjectURLScheme.buildURL(
            title: "June 2026", notes: nil, area: nil, when: nil, deadline: nil,
            tags: [], headings: ["Week 1"], authToken: "tok"
        ))
        #expect(payload.count == 1)
        #expect(payload[0]["type"] as? String == "project")
        let attrs = try #require(payload[0]["attributes"] as? [String: Any])
        #expect(attrs["title"] as? String == "June 2026")
    }

    @Test func headingsBecomeNestedItemsInOrder() throws {
        let payload = try dataPayload(of: ProjectURLScheme.buildURL(
            title: "P", notes: nil, area: nil, when: nil, deadline: nil,
            tags: [], headings: ["Week 1", "Week 2", "Week 3"], authToken: "tok"
        ))
        let attrs = try #require(payload[0]["attributes"] as? [String: Any])
        let items = try #require(attrs["items"] as? [[String: Any]])
        #expect(items.count == 3)
        #expect(items[0]["type"] as? String == "heading")
        #expect((items[0]["attributes"] as? [String: Any])?["title"] as? String == "Week 1")
        // Order must be preserved.
        #expect((items[1]["attributes"] as? [String: Any])?["title"] as? String == "Week 2")
        #expect((items[2]["attributes"] as? [String: Any])?["title"] as? String == "Week 3")
    }

    @Test func includesOptionalFields() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 1
        let date = try #require(Calendar.current.date(from: components))

        let payload = try dataPayload(of: ProjectURLScheme.buildURL(
            title: "P", notes: "my notes", area: "Work",
            when: date, deadline: date, tags: ["a", "b"], headings: ["H"], authToken: "tok"
        ))
        let attrs = try #require(payload[0]["attributes"] as? [String: Any])
        #expect(attrs["notes"] as? String == "my notes")
        #expect(attrs["area"] as? String == "Work")
        #expect(attrs["when"] as? String == "2026-06-01")
        #expect(attrs["deadline"] as? String == "2026-06-01")
        #expect(attrs["tags"] as? [String] == ["a", "b"])
    }

    @Test func omitsEmptyOptionalFields() throws {
        let payload = try dataPayload(of: ProjectURLScheme.buildURL(
            title: "P", notes: "", area: "", when: nil, deadline: nil,
            tags: [], headings: ["H"], authToken: "tok"
        ))
        let attrs = try #require(payload[0]["attributes"] as? [String: Any])
        #expect(attrs["notes"] == nil)
        #expect(attrs["area"] == nil)
        #expect(attrs["tags"] == nil)
        #expect(attrs["when"] == nil)
        #expect(attrs["deadline"] == nil)
    }
}
