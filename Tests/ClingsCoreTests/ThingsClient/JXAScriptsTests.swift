// JXAScriptsTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import ClingsCore

@Suite("JXAScripts")
struct JXAScriptsTests {
    @Suite("String Escaping")
    struct StringEscaping {
        @Test func jxaEscapedBackslash() {
            let input = "path\\to\\file"
            let escaped = input.jxaEscaped
            #expect(escaped == "path\\\\to\\\\file")
        }

        @Test func jxaEscapedSingleQuote() {
            let input = "it's a test"
            let escaped = input.jxaEscaped
            #expect(escaped == "it\\'s a test")
        }

        @Test func jxaEscapedNewline() {
            let input = "line1\nline2"
            let escaped = input.jxaEscaped
            #expect(escaped == "line1\\nline2")
        }

        @Test func jxaEscapedCarriageReturn() {
            let input = "line1\rline2"
            let escaped = input.jxaEscaped
            #expect(escaped == "line1\\rline2")
        }

        @Test func jxaEscapedTab() {
            let input = "col1\tcol2"
            let escaped = input.jxaEscaped
            #expect(escaped == "col1\\tcol2")
        }

        @Test func jxaEscapedCombined() {
            let input = "It's a test\nwith\\path"
            let escaped = input.jxaEscaped
            #expect(escaped == "It\\'s a test\\nwith\\\\path")
        }

        @Test func jxaEscapedEmpty() {
            let input = ""
            let escaped = input.jxaEscaped
            #expect(escaped == "")
        }

        @Test func jxaEscapedNoSpecialChars() {
            let input = "simple text"
            let escaped = input.jxaEscaped
            #expect(escaped == "simple text")
        }
    }

    @Suite("Fetch List Script")
    struct FetchListScript {
        @Test func containsListName() {
            let script = JXAScripts.fetchList("Today")
            #expect(script.contains("'Today'"))
            #expect(script.contains("Application('Things3')"))
            #expect(script.contains("JSON.stringify"))
        }

        @Test func escapesListName() {
            let script = JXAScripts.fetchList("It's a list")
            #expect(script.contains("It\\'s a list"))
        }

        @Test func hasCorrectStructure() {
            let script = JXAScripts.fetchList("Inbox")

            // Check for key JSON properties
            #expect(script.contains("id: todo.id()"))
            #expect(script.contains("name: todo.name()"))
            #expect(script.contains("status: todo.status()"))
            #expect(script.contains("dueDate:"))
            #expect(script.contains("tags:"))
            #expect(script.contains("project:"))
            #expect(script.contains("area:"))
            #expect(script.contains("checklistItems:"))
        }
    }

    @Suite("Fetch Todo Script")
    struct FetchTodoScript {
        @Test func containsId() {
            let script = JXAScripts.fetchTodo(id: "test-id-123")
            #expect(script.contains("'test-id-123'"))
            #expect(script.contains("app.toDos.byId"))
        }

        @Test func checksExistence() {
            let script = JXAScripts.fetchTodo(id: "test")
            #expect(script.contains("if (!todo.exists())"))
            #expect(script.contains("error"))
        }

        @Test func escapesId() {
            let script = JXAScripts.fetchTodo(id: "id'with'quotes")
            #expect(script.contains("id\\'with\\'quotes"))
        }
    }

    @Suite("Fetch Projects Script")
    struct FetchProjectsScript {
        @Test func hasCorrectStructure() {
            let script = JXAScripts.fetchProjects()
            #expect(script.contains("app.projects()"))
            #expect(script.contains("id: proj.id()"))
            #expect(script.contains("name: proj.name()"))
            #expect(script.contains("status: proj.status()"))
        }
    }

    @Suite("Fetch Areas Script")
    struct FetchAreasScript {
        @Test func hasCorrectStructure() {
            let script = JXAScripts.fetchAreas()
            #expect(script.contains("app.areas()"))
            #expect(script.contains("id: area.id()"))
            #expect(script.contains("name: area.name()"))
        }
    }

    @Suite("Fetch Tags Script")
    struct FetchTagsScript {
        @Test func hasCorrectStructure() {
            let script = JXAScripts.fetchTags()
            #expect(script.contains("app.tags()"))
            #expect(script.contains("id: tag.id()"))
            #expect(script.contains("name: tag.name()"))
        }
    }

    @Suite("Complete Todo Script")
    struct CompleteTodoScript {
        @Test func containsId() {
            let script = JXAScripts.completeTodo(id: "todo-123")
            #expect(script.contains("'todo-123'"))
            #expect(script.contains("todo.status = 'completed'"))
        }

        @Test func checksExistence() {
            let script = JXAScripts.completeTodo(id: "test")
            #expect(script.contains("if (!todo.exists())"))
            #expect(script.contains("success: false"))
        }

        @Test func returnsSuccess() {
            let script = JXAScripts.completeTodo(id: "test")
            #expect(script.contains("success: true"))
        }
    }

    @Suite("Cancel Todo Script")
    struct CancelTodoScript {
        @Test func setsStatus() {
            let script = JXAScripts.cancelTodo(id: "todo-456")
            #expect(script.contains("todo.status = 'canceled'"))
        }

        @Test func checksExistence() {
            let script = JXAScripts.cancelTodo(id: "test")
            #expect(script.contains("if (!todo.exists())"))
        }
    }

    @Suite("Reopen Todo Script")
    struct ReopenTodoScript {
        @Test func setsStatusOpen() {
            let script = JXAScripts.reopenTodo(id: "todo-reopen")
            #expect(script.contains("todo.status = 'open'"))
        }

        @Test func checksExistence() {
            let script = JXAScripts.reopenTodo(id: "test")
            #expect(script.contains("if (!todo.exists())"))
            #expect(script.contains("success: false"))
        }

        @Test func checksCurrentStatus() {
            let script = JXAScripts.reopenTodo(id: "test")
            #expect(script.contains("todo.status()"))
            #expect(script.contains("already open"))
        }

        @Test func verifiesStatusChange() {
            let script = JXAScripts.reopenTodo(id: "test")
            #expect(script.contains("newStatus !== 'open'"))
            #expect(script.contains("Failed to reopen"))
        }

        @Test func returnsSuccess() {
            let script = JXAScripts.reopenTodo(id: "test")
            #expect(script.contains("success: true"))
        }

        @Test func escapesId() {
            let script = JXAScripts.reopenTodo(id: "id'with'quotes")
            #expect(script.contains("id\\'with\\'quotes"))
        }
    }

    @Suite("Tag Scripts")
    struct TagScripts {
        @Test func joinsTagsIntoOneCommaSeparatedString() {
            // `{"a", "b"} as string` concatenates to "ab" and creates a junk tag.
            let script = JXAScripts.setTodoTagsAppleScript(id: "t1", tags: ["Alica", "Oliver P"])
            #expect(script.contains("set tag names of theTodo to \"Alica, Oliver P\""))
            #expect(!script.contains("as string"))
        }

        @Test func splitsCommaSeparatedArguments() {
            let script = JXAScripts.setTodoTagsAppleScript(id: "t1", tags: ["a,b", " c ", "a", ""])
            #expect(script.contains("set tag names of theTodo to \"a, b, c\""))
            #expect(script.contains("{\"a\", \"b\", \"c\"}"))
        }

        @Test func emptyListClearsTags() {
            let script = JXAScripts.setTodoTagsAppleScript(id: "t1", tags: [])
            #expect(script.contains("set tag names of theTodo to \"\""))
        }

        @Test func projectTagsUseTheSameFormat() {
            let script = JXAScripts.setProjectTagsAppleScript(id: "p1", tags: ["x", "y"])
            #expect(script.contains("set tag names of theProject to \"x, y\""))
        }
    }

    @Suite("Trash Todo Script")
    struct TrashTodoScript {
        @Test func movesToTrashInsteadOfCanceling() {
            // `delete` fails (-1728) for completed/canceled todos; a move to the Trash
            // list works for every status (verified against Things 3.24).
            let script = JXAScripts.trashTodoAppleScript(id: "todo-789")
            #expect(script.contains("move to do id \"todo-789\" to list \"Trash\""))
            #expect(!script.contains("delete"))
            #expect(!script.contains("canceled"))
        }

        @Test func escapesId() {
            let script = JXAScripts.trashTodoAppleScript(id: "a\"b")
            #expect(script.contains("to do id \"a\\\"b\""))
        }
    }

    @Suite("Move To List Script")
    struct MoveToListScript {
        @Test func movesToBuiltInList() {
            let script = JXAScripts.moveTodoToListAppleScript(id: "todo-1", list: "Someday")
            #expect(script.contains("move to do id \"todo-1\" to list \"Someday\""))
        }
    }

    @Suite("Move Todo Script")
    struct MoveTodoScript {
        @Test func containsIdsAndProject() {
            let script = JXAScripts.moveTodo(id: "todo-123", toProject: "My Project")
            #expect(script.contains("'todo-123'"))
            #expect(script.contains("'My Project'"))
            #expect(script.contains("app.projects.byName"))
        }

        @Test func acceptsProjectIdOrTitle() {
            let script = JXAScripts.moveTodo(id: "todo-1", toProject: "P1")
            #expect(script.contains("app.projects.byId('P1')"))
            #expect(script.contains("app.projects.byName('P1')"))
        }

        @Test func checksProjectExistence() {
            let script = JXAScripts.moveTodo(id: "test", toProject: "Project")
            #expect(script.contains("if (!project.exists())"))
            #expect(script.contains("Project not found"))
        }

        @Test func setsProject() {
            let script = JXAScripts.moveTodo(id: "test", toProject: "Project")
            #expect(script.contains("todo.project = project"))
        }
    }

    @Suite("Update Todo Script")
    struct UpdateTodoScript {
        @Test func withName() {
            let script = JXAScripts.updateTodo(id: "todo-123", name: "New Name")
            #expect(script.contains("todo.name = 'New Name'"))
        }

        @Test func withNotes() {
            let script = JXAScripts.updateTodo(id: "todo-123", notes: "Updated notes")
            #expect(script.contains("todo.notes = 'Updated notes'"))
        }

        @Test func withDueDate() {
            let date = Date()
            let script = JXAScripts.updateTodo(id: "todo-123", dueDate: date)
            #expect(script.contains("todo.dueDate = new Date("))
        }

        @Test func withTags() {
            // Note: Tags parameter is accepted but ignored in JXA script.
            // Tag updates are handled via AppleScript for reliability.
            // This test verifies the script is still valid and returns success.
            let script = JXAScripts.updateTodo(id: "todo-123", tags: ["work", "urgent"])
            #expect(script.contains("todo-123"))
            #expect(script.contains("success: true"))
            // Tags are NOT included in the JXA script - they're handled separately
        }

        @Test func withNoChanges() {
            let script = JXAScripts.updateTodo(id: "todo-123")
            #expect(script.contains("todo-123"))
            // Should still check existence and return success
            #expect(script.contains("if (!todo.exists())"))
            #expect(script.contains("success: true"))
        }

        @Test func escapesValues() {
            let script = JXAScripts.updateTodo(id: "test", name: "It's done", notes: "Line1\nLine2")
            #expect(script.contains("It\\'s done"))
            #expect(script.contains("Line1\\nLine2"))
        }

        // Note: --when uses Things URL scheme (activationDate is read-only in JXA).
        // URL scheme tests would require integration testing with Things 3.
    }

    @Suite("Create Todo Script (AppleScript)")
    struct CreateTodoScript {
        @Test func withName() {
            let script = JXAScripts.createTodoAppleScript(name: "New Task")
            #expect(script.contains("tell application \"Things3\""))
            #expect(script.contains("make new to do with properties"))
            #expect(script.contains("name:\"New Task\""))
        }

        @Test func withNotes() {
            let script = JXAScripts.createTodoAppleScript(name: "Task", notes: "Some notes")
            #expect(script.contains("notes:\"Some notes\""))
        }

        @Test func withProjectName() {
            let script = JXAScripts.createTodoAppleScript(name: "Task", project: .name("My Project"))
            #expect(script.contains("set project of newTodo to project \"My Project\""))
        }

        @Test func withProjectId() {
            let script = JXAScripts.createTodoAppleScript(name: "Task", project: .id("P1"))
            #expect(script.contains("set project of newTodo to project id \"P1\""))
        }

        @Test func withAreaId() {
            let script = JXAScripts.createTodoAppleScript(name: "Task", area: .id("A1"))
            #expect(script.contains("set area of newTodo to area id \"A1\""))
        }

        @Test func doesNotSwallowAssignmentErrors() {
            // A missing project must fail loudly, not silently leave the to-do in the Inbox.
            let script = JXAScripts.createTodoAppleScript(name: "Task", project: .name("Nope"), area: .name("Nope"))
            #expect(!script.contains("try"))
        }

        @Test func neverBuildsChecklistWithAppleScript() {
            // `make new to do` inside a to-do fails (-10000) and leaves a stray Inbox to-do.
            let script = JXAScripts.createTodoAppleScript(name: "Task")
            #expect(!script.contains("tell newTodo"))
        }

        @Test func returnsId() {
            let script = JXAScripts.createTodoAppleScript(name: "Task")
            #expect(script.contains("return id of newTodo"))
        }

        @Test func withDeadline() {
            let script = JXAScripts.createTodoAppleScript(name: "Task", deadline: Date())
            #expect(script.contains("set due date of newTodo to deadlineDate"))
        }

        @Test func withWhenSchedulesInsteadOfSettingReadOnlyActivationDate() {
            let script = JXAScripts.createTodoAppleScript(name: "Task", when: Date())
            #expect(script.contains("schedule newTodo for whenDate"))
            #expect(!script.contains("activation date"))
        }

        @Test func resetsDayBeforeMonthToAvoidOverflow() throws {
            // On Oct 31, setting month 11 first yields Nov 31 -> Dec 1.
            let script = JXAScripts.createTodoAppleScript(name: "Task", when: Date(), deadline: Date())
            for variable in ["whenDate", "deadlineDate"] {
                let reset = try #require(script.range(of: "set day of \(variable) to 1"))
                let month = try #require(script.range(of: "set month of \(variable) to"))
                #expect(reset.lowerBound < month.lowerBound)
            }
        }

        @Test func usesGregorianComponents() {
            let components = DateComponents(year: 2026, month: 11, day: 15)
            let date = ThingsDateConverter.calendar.date(from: components) ?? Date()
            let script = JXAScripts.createTodoAppleScript(name: "Task", when: date)
            #expect(script.contains("set year of whenDate to 2026"))
            #expect(script.contains("set month of whenDate to 11"))
            #expect(script.contains("set day of whenDate to 15"))
        }
    }

    @Suite("Search Script")
    struct SearchScript {
        @Test func containsQuery() {
            let script = JXAScripts.search(query: "test search")
            #expect(script.contains("'test search'"))
        }

        @Test func searchesBothNameAndNotes() {
            let script = JXAScripts.search(query: "test")
            #expect(script.contains("name.includes(query)"))
            #expect(script.contains("notes.includes(query)"))
        }

        @Test func isCaseInsensitive() {
            let script = JXAScripts.search(query: "test")
            #expect(script.contains("toLowerCase()"))
        }

        @Test func escapesQuery() {
            let script = JXAScripts.search(query: "it's a test")
            #expect(script.contains("it\\'s a test"))
        }
    }

    @Suite("Script Validity")
    struct ScriptValidity {
        // JXA scripts (IIFE format with Application('Things3'))
        static let jxaScripts = [
            JXAScripts.fetchList("Today"),
            JXAScripts.fetchTodo(id: "test"),
            JXAScripts.fetchProjects(),
            JXAScripts.fetchAreas(),
            JXAScripts.fetchTags(),
            JXAScripts.completeTodo(id: "test"),
            JXAScripts.cancelTodo(id: "test"),
            JXAScripts.reopenTodo(id: "test"),
            JXAScripts.moveTodo(id: "test", toProject: "Project"),
            JXAScripts.updateTodo(id: "test", name: "Name"),
            JXAScripts.search(query: "test"),
        ]

        @Test func allJXAScriptsAreIIFE() {
            for script in Self.jxaScripts {
                #expect(script.hasPrefix("(() => {"), "Script should start with IIFE")
                #expect(script.hasSuffix("})()"), "Script should end with IIFE invocation")
            }
        }

        @Test func allJXAScriptsUseThings3App() {
            for script in Self.jxaScripts {
                #expect(script.contains("Application('Things3')"))
            }
        }

        @Test func createTodoIsAppleScript() {
            let script = JXAScripts.createTodoAppleScript(name: "Task")
            #expect(script.contains("tell application \"Things3\""))
            #expect(script.contains("make new to do with properties"))
        }

        @Test func updateProjectIsJXA() {
            let script = JXAScripts.updateProject(id: "proj-1", name: "New Name")
            #expect(script.contains("Application('Things3')"))
            #expect(script.contains("app.projects.byId"))
        }
    }
}
