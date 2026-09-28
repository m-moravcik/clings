// ThingsURLSchemeTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import ClingsCore

@Suite("ThingsURLScheme")
struct ThingsURLSchemeTests {
    static func query(_ url: String) throws -> [String: String] {
        let components = try #require(URLComponents(string: url))
        var map: [String: String] = [:]
        for item in components.queryItems ?? [] {
            map[item.name] = item.value
        }
        return map
    }

    /// Decode the `data` parameter of a `things:///json` URL.
    static func operations(_ url: String) throws -> [[String: Any]] {
        let json = try #require(try query(url)["data"])
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(object as? [[String: Any]])
    }

    static func attributes(_ url: String) throws -> [String: Any] {
        let operation = try #require(try operations(url).first)
        return try #require(operation["attributes"] as? [String: Any])
    }

    @Suite("To-do update")
    struct TodoUpdate {
        @Test func buildsJSONUpdateOperation() throws {
            var attributes = TodoUpdateAttributes()
            attributes.title = "New"
            let url = try ThingsURLScheme.updateTodo(id: "abc", attributes: attributes, authToken: "tok")

            #expect(url.hasPrefix("things:///json?"))
            #expect(try ThingsURLSchemeTests.query(url)["auth-token"] == "tok")
            let operation = try #require(try ThingsURLSchemeTests.operations(url).first)
            #expect(operation["type"] as? String == "to-do")
            #expect(operation["operation"] as? String == "update")
            #expect(operation["id"] as? String == "abc")
        }

        @Test func sendsOnlyProvidedAttributes() throws {
            var attributes = TodoUpdateAttributes()
            attributes.appendNotes = "more"
            attributes.addTags = ["a", "b"]
            let attrs = try ThingsURLSchemeTests.attributes(
                try ThingsURLScheme.updateTodo(id: "abc", attributes: attributes, authToken: "tok")
            )

            #expect(attrs["append-notes"] as? String == "more")
            // Verified against Things 3.24: the json command only accepts an array here;
            // the comma-separated string from the docs is rejected with an error dialog.
            #expect(attrs["add-tags"] as? [String] == ["a", "b"])
            #expect(attrs.count == 2)
        }

        @Test func encodesWhenWithTime() throws {
            var attributes = TodoUpdateAttributes()
            attributes.when = .dayAndTime(DateComponents(year: 2026, month: 10, day: 1, hour: 14, minute: 0))
            let attrs = try ThingsURLSchemeTests.attributes(
                try ThingsURLScheme.updateTodo(id: "abc", attributes: attributes, authToken: "tok")
            )

            #expect(attrs["when"] as? String == "2026-10-01@14:00")
        }

        @Test func clearsDeadlineWithEmptyString() throws {
            var attributes = TodoUpdateAttributes()
            attributes.deadline = .clear
            let attrs = try ThingsURLSchemeTests.attributes(
                try ThingsURLScheme.updateTodo(id: "abc", attributes: attributes, authToken: "tok")
            )

            #expect(attrs["deadline"] as? String == "")
        }

        @Test func setsDeadlineDay() throws {
            var attributes = TodoUpdateAttributes()
            attributes.deadline = .set(DateComponents(year: 2026, month: 12, day: 24))
            let attrs = try ThingsURLSchemeTests.attributes(
                try ThingsURLScheme.updateTodo(id: "abc", attributes: attributes, authToken: "tok")
            )

            #expect(attrs["deadline"] as? String == "2026-12-24")
        }

        @Test func sendsListAndHeadingIdsTogether() throws {
            var attributes = TodoUpdateAttributes()
            attributes.listId = "proj"
            attributes.headingId = "head"
            let attrs = try ThingsURLSchemeTests.attributes(
                try ThingsURLScheme.updateTodo(id: "abc", attributes: attributes, authToken: "tok")
            )

            #expect(attrs["list-id"] as? String == "proj")
            #expect(attrs["heading-id"] as? String == "head")
        }

        @Test func encodesChecklistWithCompletionState() throws {
            var attributes = TodoUpdateAttributes()
            attributes.checklist = [
                ChecklistEntry(title: "A", completed: false),
                ChecklistEntry(title: "B", completed: true),
            ]
            let attrs = try ThingsURLSchemeTests.attributes(
                try ThingsURLScheme.updateTodo(id: "abc", attributes: attributes, authToken: "tok")
            )

            let items = try #require(attrs["checklist-items"] as? [[String: Any]])
            #expect(items.count == 2)
            #expect(items[0]["type"] as? String == "checklist-item")
            let second = try #require(items[1]["attributes"] as? [String: Any])
            #expect(second["title"] as? String == "B")
            #expect(second["completed"] as? Bool == true)
        }

        @Test func emptyChecklistClearsIt() throws {
            var attributes = TodoUpdateAttributes()
            attributes.checklist = []
            let attrs = try ThingsURLSchemeTests.attributes(
                try ThingsURLScheme.updateTodo(id: "abc", attributes: attributes, authToken: "tok")
            )

            #expect((attrs["checklist-items"] as? [Any])?.isEmpty == true)
        }

        @Test func appendAndPrependChecklistAreChecklistItemObjects() throws {
            // Verified against Things 3.24: newline strings and plain string arrays are ignored.
            var attributes = TodoUpdateAttributes()
            attributes.appendChecklist = ["x", "y"]
            attributes.prependChecklist = ["first"]
            let attrs = try ThingsURLSchemeTests.attributes(
                try ThingsURLScheme.updateTodo(id: "abc", attributes: attributes, authToken: "tok")
            )

            let appended = try #require(attrs["append-checklist-items"] as? [[String: Any]])
            #expect(appended.count == 2)
            #expect(appended[0]["type"] as? String == "checklist-item")
            #expect((appended[1]["attributes"] as? [String: Any])?["title"] as? String == "y")
            let prepended = try #require(attrs["prepend-checklist-items"] as? [[String: Any]])
            #expect((prepended[0]["attributes"] as? [String: Any])?["title"] as? String == "first")
        }

        @Test func keepsSpecialCharactersIntact() throws {
            var attributes = TodoUpdateAttributes()
            attributes.title = "C++ a+b & c=d #3"
            let attrs = try ThingsURLSchemeTests.attributes(
                try ThingsURLScheme.updateTodo(id: "abc", attributes: attributes, authToken: "tok")
            )

            #expect(attrs["title"] as? String == "C++ a+b & c=d #3")
        }

        @Test func isEmptyWhenNothingSet() {
            #expect(TodoUpdateAttributes().isEmpty)
            var attributes = TodoUpdateAttributes()
            attributes.notes = ""
            #expect(!attributes.isEmpty)
        }
    }

    @Suite("Project update")
    struct ProjectUpdate {
        @Test func buildsProjectUpdateOperation() throws {
            var attributes = ProjectUpdateAttributes()
            attributes.when = .someday
            attributes.areaId = "area"
            attributes.addTags = ["x"]
            attributes.prependNotes = "top"
            let url = try ThingsURLScheme.updateProject(id: "p1", attributes: attributes, authToken: "tok")

            let operation = try #require(try ThingsURLSchemeTests.operations(url).first)
            #expect(operation["type"] as? String == "project")
            #expect(operation["operation"] as? String == "update")
            #expect(operation["id"] as? String == "p1")
            let attrs = try #require(operation["attributes"] as? [String: Any])
            #expect(attrs["when"] as? String == "someday")
            #expect(attrs["area-id"] as? String == "area")
            #expect(attrs["add-tags"] as? [String] == ["x"])
            #expect(attrs["prepend-notes"] as? String == "top")
        }
    }

    @Suite("Show")
    struct Show {
        @Test func showById() throws {
            let url = try ThingsURLScheme.show(id: "abc")
            #expect(url.hasPrefix("things:///show?"))
            #expect(try ThingsURLSchemeTests.query(url)["id"] == "abc")
        }

        @Test func showByQueryWithTagFilter() throws {
            let url = try ThingsURLScheme.show(query: "Work", filterTags: ["urgent", "home"])
            let query = try ThingsURLSchemeTests.query(url)
            #expect(query["query"] == "Work")
            #expect(query["filter"] == "urgent,home")
        }

        @Test(arguments: ["inbox", "today", "anytime", "upcoming", "someday", "logbook",
                          "tomorrow", "deadlines", "repeating", "all-projects", "logged-projects"])
        func builtInListIds(list: String) {
            #expect(ThingsURLScheme.builtInListIds.contains(list))
        }
    }

    @Suite("Duplicate")
    struct Duplicate {
        @Test func usesUpdateCommandWithDuplicateFlag() throws {
            let url = try ThingsURLScheme.duplicateTodo(id: "abc", authToken: "tok")
            #expect(url.hasPrefix("things:///update?"))
            let query = try ThingsURLSchemeTests.query(url)
            #expect(query["id"] == "abc")
            #expect(query["duplicate"] == "true")
            #expect(query["auth-token"] == "tok")
        }
    }
}
