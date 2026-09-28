// UndoStoreTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import ClingsCore

@Suite("UndoStore")
struct UndoStoreTests {
    private func makeStore() -> UndoStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clings-undo-\(UUID().uuidString).json")
        return UndoStore(fileURL: url)
    }

    private func entry(_ todoId: String, batch: UUID? = nil, at offset: TimeInterval = 0) -> UndoEntry {
        UndoEntry(
            batchId: batch, operation: .complete, todoId: todoId, title: todoId,
            snapshot: nil, createdAt: Date(timeIntervalSince1970: 1_000_000 + offset)
        )
    }

    @Test func emptyWhenFileMissing() throws {
        #expect(try makeStore().entries().isEmpty)
        #expect(try makeStore().latestGroup().isEmpty)
    }

    @Test func listsNewestFirst() throws {
        let store = makeStore()
        try store.record([entry("a", at: 0)])
        try store.record([entry("b", at: 10)])

        #expect(try store.entries().map(\.todoId) == ["b", "a"])
    }

    @Test func trimsToMaxEntries() throws {
        let store = makeStore()
        for index in 0..<(UndoStore.maxEntries + 5) {
            try store.record([entry("t\(index)", at: TimeInterval(index))])
        }

        let entries = try store.entries()
        #expect(entries.count == UndoStore.maxEntries)
        #expect(entries.first?.todoId == "t\(UndoStore.maxEntries + 4)")
    }

    @Test func latestGroupReturnsWholeBatch() throws {
        let store = makeStore()
        let batch = UUID()
        try store.record([entry("single", at: 0)])
        try store.record([entry("x", batch: batch, at: 10), entry("y", batch: batch, at: 10)])

        #expect(Set(try store.latestGroup().map(\.todoId)) == ["x", "y"])
    }

    @Test func latestGroupWithoutBatchIsSingleEntry() throws {
        let store = makeStore()
        try store.record([entry("a", at: 0)])
        try store.record([entry("b", at: 10)])

        #expect(try store.latestGroup().map(\.todoId) == ["b"])
    }

    @Test func removeDeletesOnlyGivenEntries() throws {
        let store = makeStore()
        let keep = entry("keep", at: 0)
        let drop = entry("drop", at: 10)
        try store.record([keep])
        try store.record([drop])

        try store.remove(entryIds: [drop.id])

        #expect(try store.entries().map(\.todoId) == ["keep"])
    }

    @Test func historyFileIsPrivate() throws {
        let store = makeStore()
        try store.record([entry("a")])

        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue == 0o600)
    }

    @Test func snapshotCapturesRestorableState() {
        let startDay = ThingsDateConverter.calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)) ?? Date()
        let deadline = ThingsDateConverter.calendar.date(from: DateComponents(year: 2026, month: 12, day: 24)) ?? Date()
        let todo = Todo(
            id: "t1", name: "Call", notes: "n", status: .open, deadlineDate: deadline,
            tags: [Tag(name: "home")], project: Project(id: "p1", name: "P"),
            checklistItems: [ChecklistItem(id: "c1", name: "A", completed: true)],
            startDate: startDay, heading: "H", headingId: "h1", start: .someday,
            isEvening: true, reminderTime: DateComponents(hour: 9, minute: 30)
        )

        let snapshot = TodoSnapshot(todo: todo)

        #expect(snapshot.title == "Call")
        #expect(snapshot.notes == "n")
        #expect(snapshot.start == .someday)
        #expect(snapshot.startDay == DateComponents(year: 2026, month: 10, day: 1))
        #expect(snapshot.deadline == DateComponents(year: 2026, month: 12, day: 24))
        #expect(snapshot.isEvening)
        #expect(snapshot.reminderTime == DateComponents(hour: 9, minute: 30))
        #expect(snapshot.tags == ["home"])
        #expect(snapshot.projectId == "p1")
        #expect(snapshot.headingId == "h1")
        #expect(snapshot.checklist == [ChecklistEntry(title: "A", completed: true)])
    }
}
