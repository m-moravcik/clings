// ThingsDatabase.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GRDB

/// Direct SQLite access to the Things 3 database for fast reads.
/// Note: This is an undocumented API and may break with Things updates.
public final class ThingsDatabase: Sendable {
    private let dbPath: String

    /// The resolved path to the SQLite database file.
    public var path: String { dbPath }

    /// Initialize with an optional explicit database path.
    ///
    /// Resolution order:
    /// 1. Explicit `databasePath` parameter (if provided)
    /// 2. `CLINGS_DB_PATH` environment variable (if set)
    /// 3. Auto-discovery from Things 3 group container
    public init(databasePath: String? = nil) throws {
        if let explicit = databasePath {
            guard FileManager.default.fileExists(atPath: explicit) else {
                throw ThingsError.operationFailed(
                    "Database file not found at path: \(explicit)"
                )
            }
            self.dbPath = explicit
            return
        }

        if let envPath = ProcessInfo.processInfo.environment["CLINGS_DB_PATH"] {
            guard FileManager.default.fileExists(atPath: envPath) else {
                throw ThingsError.operationFailed(
                    "Database file not found at CLINGS_DB_PATH: \(envPath)"
                )
            }
            self.dbPath = envPath
            return
        }

        // Find the Things database - it may be in a ThingsData-XXXX subdirectory
        let groupContainerBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac")

        // Try to find the database in any ThingsData-* subdirectory
        var dbPathFound: String?

        if let contents = try? FileManager.default.contentsOfDirectory(atPath: groupContainerBase.path) {
            for item in contents where item.hasPrefix("ThingsData-") {
                let candidatePath = groupContainerBase
                    .appendingPathComponent(item)
                    .appendingPathComponent("Things Database.thingsdatabase/main.sqlite")
                if FileManager.default.fileExists(atPath: candidatePath.path) {
                    dbPathFound = candidatePath.path
                    break
                }
            }
        }

        // Fallback: try the old location (Things Database.thingsdatabase directly in container)
        if dbPathFound == nil {
            let fallbackPath = groupContainerBase
                .appendingPathComponent("Things Database.thingsdatabase/main.sqlite")
            if FileManager.default.fileExists(atPath: fallbackPath.path) {
                dbPathFound = fallbackPath.path
            }
        }

        guard let path = dbPathFound else {
            throw ThingsError.operationFailed("Things 3 database not found. Is Things 3 installed?")
        }

        self.dbPath = path
    }

    /// Open a read-only connection to the database.
    private func openDatabase() throws -> DatabaseQueue {
        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(path: dbPath, configuration: config)
    }

    // MARK: - Shared SQL

    /// Todo columns for rows selected with `todoFrom`. `project` is the effective
    /// parent project: todos filed under a heading leave `TMTask.project` empty
    /// and inherit the heading's project.
    private static let todoColumns = """
        t.uuid, t.title, t.notes, t.status, t.stopDate, t.deadline, t.creationDate,
        t.userModificationDate, COALESCE(t.project, h.project) AS project, t.area,
        t.startDate, t.rt1_repeatingTemplate, t.rt1_recurrenceRule IS NOT NULL AS isTemplate,
        t.heading, t.start, t.startBucket, t.reminderTime
        """

    /// Joins each todo (`t`) to its heading (`h`) and effective project (`p`).
    private static let todoFrom = """
        FROM TMTask t
        LEFT JOIN TMTask h ON h.uuid = t.heading
        LEFT JOIN TMTask p ON p.uuid = COALESCE(t.project, h.project)
        """

    /// Parents Things still shows: descendants of trashed or closed projects
    /// (filed directly or under a heading) are hidden from every list but Trash.
    private static let visibleParents = """
        (p.uuid IS NULL OR (p.trashed = 0 AND p.status = 0))
        AND (h.uuid IS NULL OR h.trashed = 0)
        """

    /// An open, visible todo. Repeating templates are included; list queries
    /// that must hide them add `notTemplate`.
    private static let openTodo = "t.type = 0 AND t.trashed = 0 AND t.status = 0 AND \(visibleParents)"

    private static let notTemplate = "t.rt1_recurrenceRule IS NULL"

    // MARK: - List Queries

    /// Fetch todos from a specific list view.
    ///
    /// Membership mirrors the lists Things itself returns over AppleScript,
    /// except that Anytime leaves out todos already shown in Today.
    /// - Parameter limit: Maximum number of results (applies to logbook, default 500).
    public func fetchList(_ list: ListView, limit: Int? = nil) throws -> [Todo] {
        let db = try openDatabase()
        let columns = Self.todoColumns
        let from = Self.todoFrom
        let openTodo = Self.openTodo
        let notTemplate = Self.notTemplate

        return try db.read { db in
            let sql: String
            let arguments: StatementArguments

            switch list {
            case .inbox:
                sql = """
                    SELECT \(columns) \(from)
                    WHERE \(openTodo) AND \(notTemplate)
                          AND t.start = 0 AND t.startDate IS NULL AND p.uuid IS NULL
                    ORDER BY t."index"
                    """
                arguments = []

            case .today:
                let todayPacked = ThingsDateConverter.encodeDate(Date())
                // start = 2 rows whose date has arrived are still Today: Things only
                // flips them to start = 1 at its next day rollover.
                sql = """
                    SELECT \(columns) \(from)
                    WHERE \(openTodo) AND \(notTemplate)
                          AND (
                              (t.start IN (1, 2) AND t.startDate IS NOT NULL AND t.startDate <= ?)
                              OR (t.startDate IS NULL AND t.deadline IS NOT NULL AND t.deadline <= ?
                                  AND t.deadlineSuppressionDate IS NULL)
                          )
                    ORDER BY t.todayIndex, t."index"
                    """
                arguments = [todayPacked, todayPacked]

            case .upcoming:
                let todayPacked = ThingsDateConverter.encodeDate(Date())
                // Things lists every repeating template here, plus Anytime todos
                // that only carry a future deadline.
                sql = """
                    SELECT \(columns) \(from)
                    WHERE \(openTodo)
                          AND (
                              t.rt1_recurrenceRule IS NOT NULL
                              OR t.startDate > ?
                              OR (t.startDate IS NULL AND t.start = 1 AND t.deadline > ?)
                          )
                    ORDER BY COALESCE(t.startDate, t.rt1_nextInstanceStartDate, t.deadline) IS NULL,
                             COALESCE(t.startDate, t.rt1_nextInstanceStartDate, t.deadline),
                             t."index"
                    """
                arguments = [todayPacked, todayPacked]

            case .anytime:
                // Todos of a Someday (or future-scheduled) project stay hidden until
                // the project itself becomes active.
                sql = """
                    SELECT \(columns) \(from)
                    WHERE \(openTodo) AND \(notTemplate)
                          AND t.start = 1 AND t.startDate IS NULL
                          AND (p.uuid IS NULL OR p.start = 1)
                    ORDER BY t."index"
                    """
                arguments = []

            case .someday:
                // Things' Someday list holds loose todos only; Someday todos inside a
                // project are shown with that project.
                sql = """
                    SELECT \(columns) \(from)
                    WHERE \(openTodo) AND \(notTemplate)
                          AND t.start = 2 AND t.startDate IS NULL AND p.uuid IS NULL
                    ORDER BY t."index"
                    """
                arguments = []

            case .logbook:
                let logbookLimit = limit ?? 500
                sql = """
                    SELECT \(columns) \(from)
                    WHERE t.status = 3 AND t.trashed = 0 AND t.type = 0
                    ORDER BY t.stopDate DESC
                    LIMIT ?
                    """
                arguments = [logbookLimit]

            case .trash:
                sql = """
                    SELECT \(columns) \(from)
                    WHERE t.trashed = 1 AND t.type = 0
                    ORDER BY t."index"
                    """
                arguments = []
            }

            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return try self.todosFromRows(rows, db: db)
        }
    }

    /// Fetch all open (non-completed, non-trashed) todos in a single query.
    /// More efficient than fetching from each list separately. Includes
    /// repeating templates so `recurring = true` filters can find them.
    public func fetchAllOpen() throws -> [Todo] {
        let db = try openDatabase()

        return try db.read { db in
            let sql = """
                SELECT \(Self.todoColumns) \(Self.todoFrom)
                WHERE \(Self.openTodo)
                ORDER BY t.todayIndex, t."index"
                """

            let rows = try Row.fetchAll(db, sql: sql)
            return try self.todosFromRows(rows, db: db)
        }
    }

    /// Fetch all projects.
    public func fetchProjects() throws -> [Project] {
        let db = try openDatabase()

        return try db.read { db in
            let sql = """
                SELECT uuid, title, notes, status, stopDate, deadline, creationDate, area
                FROM TMTask
                WHERE type = 1 AND trashed = 0 AND status = 0 AND rt1_recurrenceRule IS NULL
                ORDER BY "index"
                """

            let rows = try Row.fetchAll(db, sql: sql)
            return try rows.map { row in
                let uuid: String = row["uuid"]
                let title: String = row["title"]
                let notes: String? = row["notes"]
                let statusInt: Int = row["status"]
                let areaUuid: String? = row["area"]

                let area: Area? = try areaUuid.flatMap { try self.fetchArea(uuid: $0, db: db) }
                let tags = try self.fetchTagsForTask(uuid: uuid, db: db)

                let deadline: Date? = (row["deadline"] as Int?).flatMap {
                    ThingsDateConverter.decodeToDate($0)
                }
                let creationDate = (row["creationDate"] as Double?).flatMap {
                    Date(timeIntervalSince1970: $0)
                } ?? Date()

                return Project(
                    id: uuid,
                    name: title,
                    notes: notes,
                    status: statusFromInt(statusInt),
                    area: area,
                    tags: tags,
                    deadlineDate: deadline,
                    creationDate: creationDate
                )
            }
        }
    }

    /// Fetch all areas.
    public func fetchAreas() throws -> [Area] {
        let db = try openDatabase()

        return try db.read { db in
            let sql = "SELECT uuid, title FROM TMArea ORDER BY \"index\""
            let rows = try Row.fetchAll(db, sql: sql)

            return try rows.map { row in
                let uuid: String = row["uuid"]
                let title: String = row["title"]
                let tags = try self.fetchTagsForArea(uuid: uuid, db: db)

                return Area(id: uuid, name: title, tags: tags)
            }
        }
    }

    /// Fetch all tags.
    public func fetchTags() throws -> [Tag] {
        let db = try openDatabase()

        return try db.read { db in
            let sql = "SELECT uuid, title FROM TMTag ORDER BY title"
            let rows = try Row.fetchAll(db, sql: sql)

            return rows.map { row in
                Tag(id: row["uuid"], name: row["title"])
            }
        }
    }

    /// Fetch all headings for a project (by UUID or name).
    public func fetchHeadings(projectId: String) throws -> [Heading] {
        let db = try openDatabase()

        return try db.read { db in
            // Resolve name → UUID. Don't guess by length/spaces: Things UUIDs are
            // 22 chars with no spaces, which collides with long single-word project
            // names. Instead try a title match first; fall back to treating the input
            // as a UUID only when no project with that title exists.
            let projectRow = try Row.fetchOne(db,
                sql: "SELECT uuid FROM TMTask WHERE title = ? AND type = 1 AND trashed = 0 LIMIT 1",
                arguments: [projectId])
            let resolvedId: String = projectRow?["uuid"] ?? projectId

            let rows = try Row.fetchAll(db,
                sql: """
                    SELECT uuid, title FROM TMTask
                    WHERE project = ? AND type = 2 AND trashed = 0
                    ORDER BY "index"
                    """,
                arguments: [resolvedId])

            return rows.map { row in
                Heading(id: row["uuid"], title: row["title"], projectId: resolvedId)
            }
        }
    }

    /// Last modification time of a to-do, project or heading, or nil if it doesn't exist.
    public func modificationDate(of id: String) throws -> Date? {
        try openDatabase().read { db in
            try Double.fetchOne(db, sql: "SELECT userModificationDate FROM TMTask WHERE uuid = ?", arguments: [id])
                .map { Date(timeIntervalSince1970: $0) }
        }
    }

    /// Whether the item sits in the Trash. Things ignores URL scheme updates to trashed items.
    public func isTrashed(_ id: String) throws -> Bool {
        try openDatabase().read { db in
            try Int.fetchOne(db, sql: "SELECT trashed FROM TMTask WHERE uuid = ?", arguments: [id]) == 1
        }
    }

    // MARK: - Name to ID Resolution

    /// Resolve a project title or ID to an ID. Trashed projects and repeating
    /// templates never match (a todo filed there would be invisible); when several
    /// projects share a title, an open one wins over completed ones.
    public func resolveProjectId(_ nameOrId: String) throws -> String? {
        try openDatabase().read { db in
            try String.fetchOne(db, sql: """
                SELECT uuid FROM TMTask
                WHERE type = 1 AND trashed = 0 AND rt1_recurrenceRule IS NULL
                      AND (uuid = ? OR title = ?)
                ORDER BY uuid = ? DESC, status != 0, "index"
                LIMIT 1
                """, arguments: [nameOrId, nameOrId, nameOrId])
        }
    }

    /// Resolve an area title or ID to an ID.
    public func resolveAreaId(_ nameOrId: String) throws -> String? {
        try openDatabase().read { db in
            try String.fetchOne(db, sql: """
                SELECT uuid FROM TMArea WHERE uuid = ? OR title = ?
                ORDER BY uuid = ? DESC, "index"
                LIMIT 1
                """, arguments: [nameOrId, nameOrId, nameOrId])
        }
    }

    /// Resolve a heading title or ID within a project to the heading's ID.
    public func resolveHeadingId(_ titleOrId: String, projectId: String) throws -> String? {
        try openDatabase().read { db in
            try String.fetchOne(db, sql: """
                SELECT uuid FROM TMTask
                WHERE type = 2 AND trashed = 0 AND project = ? AND (uuid = ? OR title = ?)
                ORDER BY uuid = ? DESC, "index"
                LIMIT 1
                """, arguments: [projectId, titleOrId, titleOrId, titleOrId])
        }
    }

    /// Fetch a single todo by ID.
    public func fetchTodo(id: String) throws -> Todo {
        let db = try openDatabase()

        return try db.read { db in
            let sql = """
                SELECT \(Self.todoColumns) \(Self.todoFrom)
                WHERE t.uuid = ? AND t.type = 0
                """

            guard let row = try Row.fetchOne(db, sql: sql, arguments: [id]) else {
                throw ThingsError.notFound(id)
            }

            return try self.todoFromRow(row, db: db)
        }
    }

    /// Fetch recently created todos (non-completed, non-trashed) since a given date.
    public func fetchRecent(since: Date) throws -> [Todo] {
        let db = try openDatabase()
        // creationDate is a Unix timestamp, like every non-packed date column.
        let sinceTimestamp = since.timeIntervalSince1970

        return try db.read { db in
            let sql = """
                SELECT \(Self.todoColumns) \(Self.todoFrom)
                WHERE t.trashed = 0 AND t.type = 0 AND t.status != 3 AND t.creationDate > ?
                      AND \(Self.visibleParents)
                ORDER BY t.creationDate DESC
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [sinceTimestamp])
            return try self.todosFromRows(rows, db: db)
        }
    }

    /// Search todos by text.
    /// - Parameter limit: Maximum number of results (default 100).
    public func search(query: String, limit: Int = 100) throws -> [Todo] {
        let db = try openDatabase()

        return try db.read { db in
            let sql = """
                SELECT \(Self.todoColumns) \(Self.todoFrom)
                WHERE t.type = 0 AND t.trashed = 0
                      AND (p.uuid IS NULL OR p.trashed = 0) AND (h.uuid IS NULL OR h.trashed = 0)
                      AND (t.title LIKE ? OR t.notes LIKE ?)
                ORDER BY t.todayIndex, t."index"
                LIMIT ?
                """

            let pattern = "%\(query)%"
            let rows = try Row.fetchAll(db, sql: sql, arguments: [pattern, pattern, limit])
            return try self.todosFromRows(rows, db: db)
        }
    }

    // MARK: - Counts

    /// Count completed todos since a given date without loading full Todo objects.
    public func countCompleted(since date: Date) throws -> Int {
        let db = try openDatabase()
        return try db.read { db in
            let timestamp = date.timeIntervalSince1970
            let sql = "SELECT COUNT(*) FROM TMTask WHERE status = 3 AND trashed = 0 AND type = 0 AND userModificationDate >= ?"
            return try Int.fetchOne(db, sql: sql, arguments: [timestamp]) ?? 0
        }
    }

    /// Count canceled todos since a given date without loading full Todo objects.
    public func countCanceled(since date: Date) throws -> Int {
        let db = try openDatabase()
        return try db.read { db in
            let timestamp = date.timeIntervalSince1970
            let sql = "SELECT COUNT(*) FROM TMTask WHERE status = 2 AND trashed = 0 AND type = 0 AND userModificationDate >= ?"
            return try Int.fetchOne(db, sql: sql, arguments: [timestamp]) ?? 0
        }
    }

    /// Return daily completion counts (day -> count) since a given date.
    public func dailyCompletionCounts(since date: Date) throws -> [Date: Int] {
        let db = try openDatabase()
        let timestamp = date.timeIntervalSince1970
        let rows = try db.read { db in
            try Row.fetchAll(db,
                sql: "SELECT userModificationDate FROM TMTask WHERE status = 3 AND trashed = 0 AND type = 0 AND userModificationDate >= ?",
                arguments: [timestamp])
        }
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for row in rows {
            let ts: Double = row["userModificationDate"]
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: ts))
            counts[day, default: 0] += 1
        }
        return counts
    }

    // MARK: - Helper Methods

    /// Convert a single row to a Todo, fetching related data individually.
    /// Use `todosFromRows` for batch operations to avoid N+1 queries.
    private func todoFromRow(_ row: Row, db: Database) throws -> Todo {
        let uuid: String = row["uuid"]
        let title: String = row["title"]
        let notes: String? = row["notes"]
        let statusInt: Int = row["status"]
        let projectUuid: String? = row["project"]
        let areaUuid: String? = row["area"]

        let project: Project? = try projectUuid.flatMap { try self.fetchProjectBasic(uuid: $0, db: db) }
        let area: Area? = try areaUuid.flatMap { try self.fetchArea(uuid: $0, db: db) }
        let tags = try fetchTagsForTask(uuid: uuid, db: db)
        let checklistItems = try fetchChecklistItems(uuid: uuid, db: db)
        let headingUuid: String? = row["heading"]
        let headingTitle: String? = try headingUuid.flatMap { uuid in
            try Row.fetchOne(db, sql: "SELECT title FROM TMTask WHERE uuid = ? AND type = 2", arguments: [uuid])
                .map { $0["title"] as String }
        }

        return buildTodo(row: row, uuid: uuid, title: title, notes: notes, statusInt: statusInt,
                         project: project, area: area, tags: tags, checklistItems: checklistItems,
                         heading: headingTitle)
    }

    /// Batch convert rows to Todos, loading all related data in bulk.
    /// Uses 4 queries total instead of 4×N individual queries.
    private func todosFromRows(_ rows: [Row], db: Database) throws -> [Todo] {
        guard !rows.isEmpty else { return [] }

        // Collect all UUIDs and related IDs
        var taskUuids: [String] = []
        var projectUuids: Set<String> = []
        var areaUuids: Set<String> = []
        var headingUuids: Set<String> = []

        for row in rows {
            let uuid: String = row["uuid"]
            taskUuids.append(uuid)
            if let projectUuid: String = row["project"] { projectUuids.insert(projectUuid) }
            if let areaUuid: String = row["area"] { areaUuids.insert(areaUuid) }
            if let headingUuid: String = row["heading"] { headingUuids.insert(headingUuid) }
        }

        // Batch fetch all related data
        let tagsByTask = try batchFetchTagsForTasks(uuids: taskUuids, db: db)
        let checklistByTask = try batchFetchChecklistItems(uuids: taskUuids, db: db)
        let areasById = try batchFetchAreas(uuids: areaUuids, db: db)
        let headingTitlesById = try batchFetchHeadingTitles(uuids: headingUuids, db: db)

        // Batch fetch projects (which also need area resolution)
        let projectsById = try batchFetchProjects(uuids: projectUuids, areasById: areasById, db: db)

        // Assemble todos
        return rows.map { row in
            let uuid: String = row["uuid"]
            let title: String = row["title"]
            let notes: String? = row["notes"]
            let statusInt: Int = row["status"]
            let projectUuid: String? = row["project"]
            let areaUuid: String? = row["area"]
            let headingUuid: String? = row["heading"]

            let project = projectUuid.flatMap { projectsById[$0] }
            let area = areaUuid.flatMap { areasById[$0] }
            let tags = tagsByTask[uuid] ?? []
            let checklistItems = checklistByTask[uuid] ?? []
            let headingTitle = headingUuid.flatMap { headingTitlesById[$0] }

            return buildTodo(row: row, uuid: uuid, title: title, notes: notes, statusInt: statusInt,
                             project: project, area: area, tags: tags, checklistItems: checklistItems,
                             heading: headingTitle)
        }
    }

    private func buildTodo(row: Row, uuid: String, title: String, notes: String?,
                           statusInt: Int, project: Project?, area: Area?,
                           tags: [Tag], checklistItems: [ChecklistItem],
                           heading: String? = nil) -> Todo {
        let deadline: Date? = (row["deadline"] as Int?).flatMap {
            ThingsDateConverter.decodeToDate($0)
        }
        let startDate: Date? = (row["startDate"] as Int?).flatMap {
            ThingsDateConverter.decodeToDate($0)
        }
        let repeatingTemplate: String? = row["rt1_repeatingTemplate"]
        let isRepeatingTemplate: Bool = row["isTemplate"] ?? false
        let start: TodoStart? = (row["start"] as Int?).flatMap { value in
            switch value {
            case 0: return .inbox
            case 1: return .anytime
            case 2: return .someday
            default: return nil
            }
        }
        let isEvening = (row["startBucket"] as Int?) == 1
        let reminderTime = (row["reminderTime"] as Int?).flatMap { ThingsDateConverter.decodeTime($0) }
        let completionDate = (row["stopDate"] as Double?).map { Date(timeIntervalSince1970: $0) }
        let creationDate: Date = (row["creationDate"] as Double?).flatMap {
            Date(timeIntervalSince1970: $0)
        } ?? Date()
        let modificationDate: Date = (row["userModificationDate"] as Double?).flatMap {
            Date(timeIntervalSince1970: $0)
        } ?? creationDate

        return Todo(
            id: uuid,
            name: title,
            notes: notes,
            status: statusFromInt(statusInt),
            deadlineDate: deadline,
            tags: tags,
            project: project,
            area: area,
            checklistItems: checklistItems,
            startDate: startDate,
            repeatingTemplate: repeatingTemplate,
            isRepeatingTemplate: isRepeatingTemplate,
            creationDate: creationDate,
            modificationDate: modificationDate,
            scheduledDate: startDate,
            heading: heading,
            headingId: row["heading"],
            start: start,
            isEvening: isEvening,
            reminderTime: reminderTime,
            completionDate: completionDate
        )
    }

    // MARK: - Batch Fetch Helpers

    private func batchFetchTagsForTasks(uuids: [String], db: Database) throws -> [String: [Tag]] {
        guard !uuids.isEmpty else { return [:] }
        let placeholders = uuids.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT tt.tasks, tag.uuid, tag.title
            FROM TMTaskTag AS tt
            JOIN TMTag AS tag ON tt.tags = tag.uuid
            WHERE tt.tasks IN (\(placeholders))
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(uuids))
        var result: [String: [Tag]] = [:]
        for row in rows {
            let taskUuid: String = row["tasks"]
            let tag = Tag(id: row["uuid"], name: row["title"])
            result[taskUuid, default: []].append(tag)
        }
        return result
    }

    private func batchFetchChecklistItems(uuids: [String], db: Database) throws -> [String: [ChecklistItem]] {
        guard !uuids.isEmpty else { return [:] }
        let placeholders = uuids.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT uuid, title, status, task
            FROM TMChecklistItem
            WHERE task IN (\(placeholders))
            ORDER BY "index"
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(uuids))
        var result: [String: [ChecklistItem]] = [:]
        for row in rows {
            let taskUuid: String = row["task"]
            let item = ChecklistItem(
                id: row["uuid"],
                name: row["title"],
                completed: (row["status"] as Int) == 3
            )
            result[taskUuid, default: []].append(item)
        }
        return result
    }

    private func batchFetchHeadingTitles(uuids: Set<String>, db: Database) throws -> [String: String] {
        guard !uuids.isEmpty else { return [:] }
        let uuidArray = Array(uuids)
        let placeholders = uuidArray.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT uuid, title FROM TMTask WHERE uuid IN (\(placeholders)) AND type = 2"
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(uuidArray))
        var result: [String: String] = [:]
        for row in rows {
            result[row["uuid"]] = row["title"]
        }
        return result
    }

    private func batchFetchAreas(uuids: Set<String>, db: Database) throws -> [String: Area] {
        guard !uuids.isEmpty else { return [:] }
        let uuidArray = Array(uuids)
        let placeholders = uuidArray.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT uuid, title FROM TMArea WHERE uuid IN (\(placeholders))"
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(uuidArray))
        var result: [String: Area] = [:]
        for row in rows {
            let uuid: String = row["uuid"]
            result[uuid] = Area(id: uuid, name: row["title"], tags: [])
        }
        return result
    }

    private func batchFetchProjects(uuids: Set<String>, areasById: [String: Area],
                                     db: Database) throws -> [String: Project] {
        guard !uuids.isEmpty else { return [:] }
        let uuidArray = Array(uuids)
        let placeholders = uuidArray.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT uuid, title, status, area FROM TMTask WHERE uuid IN (\(placeholders)) AND type = 1"
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(uuidArray))
        var result: [String: Project] = [:]
        for row in rows {
            let uuid: String = row["uuid"]
            let areaUuid: String? = row["area"]
            let area = areaUuid.flatMap { areasById[$0] }
            result[uuid] = Project(
                id: uuid,
                name: row["title"],
                notes: nil,
                status: statusFromInt(row["status"]),
                area: area,
                tags: [],
                deadlineDate: nil,
                creationDate: nil
            )
        }
        return result
    }

    // MARK: - Single-item Fetch Helpers (used by fetchTodo)

    private func fetchProjectBasic(uuid: String, db: Database) throws -> Project? {
        let sql = "SELECT title, status, area FROM TMTask WHERE uuid = ? AND type = 1"
        guard let row = try Row.fetchOne(db, sql: sql, arguments: [uuid]) else {
            return nil
        }

        let areaUuid: String? = row["area"]
        let area: Area? = try areaUuid.flatMap { try self.fetchArea(uuid: $0, db: db) }

        return Project(
            id: uuid,
            name: row["title"],
            notes: nil,
            status: statusFromInt(row["status"]),
            area: area,
            tags: [],
            deadlineDate: nil,
            creationDate: nil
        )
    }

    private func fetchArea(uuid: String, db: Database) throws -> Area? {
        let sql = "SELECT title FROM TMArea WHERE uuid = ?"
        guard let row = try Row.fetchOne(db, sql: sql, arguments: [uuid]) else {
            return nil
        }

        return Area(id: uuid, name: row["title"], tags: [])
    }

    private func fetchTagsForTask(uuid: String, db: Database) throws -> [Tag] {
        let sql = """
            SELECT tag.uuid, tag.title
            FROM TMTaskTag AS tt
            JOIN TMTag AS tag ON tt.tags = tag.uuid
            WHERE tt.tasks = ?
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: [uuid])
        return rows.map { Tag(id: $0["uuid"], name: $0["title"]) }
    }

    private func fetchTagsForArea(uuid: String, db: Database) throws -> [Tag] {
        let sql = """
            SELECT tag.uuid, tag.title
            FROM TMAreaTag AS at
            JOIN TMTag AS tag ON at.tags = tag.uuid
            WHERE at.areas = ?
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: [uuid])
        return rows.map { Tag(id: $0["uuid"], name: $0["title"]) }
    }

    private func fetchChecklistItems(uuid: String, db: Database) throws -> [ChecklistItem] {
        let sql = """
            SELECT uuid, title, status
            FROM TMChecklistItem
            WHERE task = ?
            ORDER BY "index"
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: [uuid])
        return rows.map { row in
            ChecklistItem(
                id: row["uuid"],
                name: row["title"],
                completed: (row["status"] as Int) == 3
            )
        }
    }

    private func statusFromInt(_ value: Int) -> Status {
        switch value {
        case 0: return .open
        case 2: return .canceled
        case 3: return .completed
        default: return .open
        }
    }

}
