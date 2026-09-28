// TestDatabaseBuilder.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GRDB
@testable import ClingsCore

/// Creates temporary SQLite databases with the exact Things 3 schema for testing.
///
/// Usage:
/// ```swift
/// let builder = try TestDatabaseBuilder()
/// builder.addArea(uuid: "area-1", title: "Work")
/// builder.addTask(uuid: "task-1", title: "Buy milk", start: 0)
/// let db = try ThingsDatabase(databasePath: builder.path)
/// ```
final class TestDatabaseBuilder {
    let path: String
    private let dbQueue: DatabaseQueue

    init() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "clings-test-\(UUID().uuidString).sqlite"
        self.path = tempDir.appendingPathComponent(filename).path
        self.dbQueue = try DatabaseQueue(path: path)
        try createSchema()
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Schema Creation

    private func createSchema() throws {
        try dbQueue.write { db in
            // TMTask - exact schema from Things 3
            try db.execute(sql: """
                CREATE TABLE TMTask (
                    "uuid"                              TEXT PRIMARY KEY,
                    "leavesTombstone"                   INTEGER,
                    "creationDate"                      REAL,
                    "userModificationDate"              REAL,
                    "type"                              INTEGER,
                    "status"                            INTEGER,
                    "stopDate"                          REAL,
                    "trashed"                           INTEGER,
                    "title"                             TEXT,
                    "notes"                             TEXT,
                    "notesSync"                         INTEGER,
                    "cachedTags"                        BLOB,
                    "start"                             INTEGER,
                    "startDate"                         INTEGER,
                    "startBucket"                       INTEGER,
                    "reminderTime"                      INTEGER,
                    "lastReminderInteractionDate"       REAL,
                    "deadline"                          INTEGER,
                    "deadlineSuppressionDate"           INTEGER,
                    "t2_deadlineOffset"                 INTEGER,
                    "index"                             INTEGER,
                    "todayIndex"                        INTEGER,
                    "todayIndexReferenceDate"           INTEGER,
                    "area"                              TEXT,
                    "project"                           TEXT,
                    "heading"                           TEXT,
                    "contact"                           TEXT,
                    "untrashedLeafActionsCount"         INTEGER,
                    "openUntrashedLeafActionsCount"     INTEGER,
                    "checklistItemsCount"               INTEGER,
                    "openChecklistItemsCount"           INTEGER,
                    "rt1_repeatingTemplate"             TEXT,
                    "rt1_recurrenceRule"                BLOB,
                    "rt1_instanceCreationStartDate"     INTEGER,
                    "rt1_instanceCreationPaused"        INTEGER,
                    "rt1_instanceCreationCount"         INTEGER,
                    "rt1_afterCompletionReferenceDate"  INTEGER,
                    "rt1_nextInstanceStartDate"         INTEGER,
                    "experimental"                      BLOB,
                    "repeater"                          BLOB,
                    "repeaterMigrationDate"             REAL
                )
                """)

            try db.execute(sql: """
                CREATE INDEX index_TMTask_stopDate ON TMTask(stopDate)
                """)
            try db.execute(sql: """
                CREATE INDEX index_TMTask_project ON TMTask(project)
                """)
            try db.execute(sql: """
                CREATE INDEX index_TMTask_area ON TMTask(area)
                """)

            // TMArea
            try db.execute(sql: """
                CREATE TABLE TMArea (
                    "uuid"        TEXT PRIMARY KEY,
                    "title"       TEXT,
                    "visible"     INTEGER,
                    "index"       INTEGER,
                    "cachedTags"  BLOB,
                    "experimental" BLOB
                )
                """)

            // TMTag
            try db.execute(sql: """
                CREATE TABLE TMTag (
                    "uuid"        TEXT PRIMARY KEY,
                    "title"       TEXT,
                    "shortcut"    TEXT,
                    "usedDate"    REAL,
                    "parent"      TEXT,
                    "index"       INTEGER,
                    "experimental" BLOB
                )
                """)

            // TMTaskTag
            try db.execute(sql: """
                CREATE TABLE TMTaskTag (
                    "tasks" TEXT NOT NULL,
                    "tags"  TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE INDEX index_TMTaskTag_tasks ON TMTaskTag(tasks)
                """)

            // TMAreaTag
            try db.execute(sql: """
                CREATE TABLE TMAreaTag (
                    "areas" TEXT NOT NULL,
                    "tags"  TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE INDEX index_TMAreaTag_areas ON TMAreaTag(areas)
                """)

            // TMChecklistItem
            try db.execute(sql: """
                CREATE TABLE TMChecklistItem (
                    "uuid"                 TEXT PRIMARY KEY,
                    "userModificationDate" REAL,
                    "creationDate"         REAL,
                    "title"                TEXT,
                    "status"               INTEGER,
                    "stopDate"             REAL,
                    "index"                INTEGER,
                    "task"                 TEXT,
                    "leavesTombstone"      INTEGER,
                    "experimental"         BLOB
                )
                """)
            try db.execute(sql: """
                CREATE INDEX index_TMChecklistItem_task ON TMChecklistItem(task)
                """)
        }
    }

    // MARK: - Data Insertion

    /// Add a task (todo, project, or heading depending on type).
    ///
    /// - Parameters:
    ///   - type: 0 = todo, 1 = project, 2 = heading
    ///   - status: 0 = open, 2 = canceled, 3 = completed
    ///   - start: 0 = inbox, 1 = today/anytime, 2 = someday
    ///   - startDate: Packed date integer (use `ThingsDateConverter.encode`)
    ///   - deadline: Packed date integer
    ///   - heading: UUID of the heading (type=2 row) the todo is filed under
    ///   - isRepeatingTemplate: Marks the row as a repeating template (non-null `rt1_recurrenceRule`)
    ///   - startBucket: 1 = This Evening
    ///   - reminderTime: Packed time, `hour << 26 | minute << 20`
    @discardableResult
    func addTask(
        uuid: String = UUID().uuidString,
        title: String = "Test Task",
        notes: String? = nil,
        type: Int = 0,
        status: Int = 0,
        trashed: Int = 0,
        start: Int = 0,
        startDate: Int? = nil,
        deadline: Int? = nil,
        project: String? = nil,
        area: String? = nil,
        index: Int = 0,
        todayIndex: Int = 0,
        creationDate: Double? = nil,
        userModificationDate: Double? = nil,
        stopDate: Double? = nil,
        repeatingTemplate: String? = nil,
        heading: String? = nil,
        isRepeatingTemplate: Bool = false,
        startBucket: Int = 0,
        reminderTime: Int? = nil
    ) -> String {
        let now = Date().timeIntervalSince1970
        try! dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO TMTask (
                        uuid, title, notes, type, status, trashed, start,
                        startDate, deadline, project, area, "index", todayIndex,
                        creationDate, userModificationDate, stopDate,
                        rt1_repeatingTemplate, heading, rt1_recurrenceRule,
                        startBucket, reminderTime
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    uuid, title, notes, type, status, trashed, start,
                    startDate, deadline, project, area, index, todayIndex,
                    creationDate ?? now, userModificationDate ?? now, stopDate,
                    repeatingTemplate, heading,
                    isRepeatingTemplate ? Data([0x01]) : nil,
                    startBucket, reminderTime
                ]
            )
        }
        return uuid
    }

    @discardableResult
    func addArea(
        uuid: String = UUID().uuidString,
        title: String = "Test Area",
        index: Int = 0
    ) -> String {
        try! dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO TMArea (uuid, title, visible, \"index\") VALUES (?, ?, 1, ?)",
                arguments: [uuid, title, index]
            )
        }
        return uuid
    }

    @discardableResult
    func addTag(
        uuid: String = UUID().uuidString,
        title: String = "Test Tag",
        index: Int = 0
    ) -> String {
        try! dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO TMTag (uuid, title, \"index\") VALUES (?, ?, ?)",
                arguments: [uuid, title, index]
            )
        }
        return uuid
    }

    func addTaskTag(taskUuid: String, tagUuid: String) {
        try! dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO TMTaskTag (tasks, tags) VALUES (?, ?)",
                arguments: [taskUuid, tagUuid]
            )
        }
    }

    func addAreaTag(areaUuid: String, tagUuid: String) {
        try! dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO TMAreaTag (areas, tags) VALUES (?, ?)",
                arguments: [areaUuid, tagUuid]
            )
        }
    }

    @discardableResult
    func addChecklistItem(
        uuid: String = UUID().uuidString,
        title: String = "Checklist item",
        status: Int = 0,
        index: Int = 0,
        task: String
    ) -> String {
        let now = Date().timeIntervalSince1970
        try! dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO TMChecklistItem (uuid, title, status, "index", task, creationDate)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [uuid, title, status, index, task, now]
            )
        }
        return uuid
    }
}
