# Changelog

All notable changes to clings will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-06-07

### Added

- **`--heading` option for `project add`**: Create a project together with its headings in a single command, via the Things `json` URL scheme. Repeatable and order-preserving. Requires an auth token (set with `clings config set-auth-token`).
  - `clings project add "June 2026" --heading "Week 1" --heading "Week 2" --heading "Week 3"`
  - Headings cannot be added to an existing project afterwards — a Things API limitation — so define them at creation time.
- **Heading validation in `add`**: When using `add --heading`, clings now verifies the heading exists in the target project before creating the todo. Things silently drops an unknown `heading` parameter (placing the todo in the project root); clings surfaces an actionable error listing the available headings instead. `--heading` now also requires `--project`.

### Fixed

- **`fetchHeadings` name resolution**: Long single-word project names (≥20 characters, no spaces) were misclassified as UUIDs, so `clings project headings "<name>"` and heading validation returned no results. Project names are now resolved by title first, falling back to UUID only when no matching project exists.

## [0.3.3] - 2026-04-03

### Added

- **`--repeat` option for `add` command**: Create repeating todos via Things URL scheme. Supports simple keywords (`daily`, `weekly`, `biweekly`, `monthly`, `bimonthly`, `quarterly`, `biannual`, `yearly`), human-friendly shortcuts (`last-friday-of-month`, `first-monday-of-month`, etc.), and raw iCalendar RRULE strings (e.g. `FREQ=MONTHLY;BYDAY=-1FR`).
  - `clings add "Kudos" --project "PA - Admin" --repeat last-friday-of-month`
  - `clings add "Review" --repeat weekly`
  - `clings add "Task" --repeat "FREQ=MONTHLY;BYDAY=1MO"`

## [0.3.2] - 2026-03-21

### Added

- **Checklist items in `update` command**: Add, replace, or prepend checklist items on existing todos via Things URL scheme. Requires auth token.
  - `clings update <ID> --checklist-items "Step 1" "Step 2"` — replaces all checklist items
  - `clings update <ID> --append-checklist-items "Extra step"` — appends to existing list
  - `clings update <ID> --prepend-checklist-items "First step"` — prepends to existing list

## [0.3.1] - 2026-03-08

### Fixed

- **Today query correctness**: Fixed Today list returning all 1673 Anytime tasks instead of the correct 127. Query now properly filters by `start = 1 AND startDate <= today`.
- **Anytime query correctness**: Fixed Anytime list including Today tasks. Now correctly shows only tasks with `startDate IS NULL`.
- **JXA test suite**: Fixed 13 test failures where `createTodo` tests expected AppleScript format but implementation generates JXA.
- **Force unwraps in JXAScripts**: Replaced fragile `name!.jxaEscaped` patterns with safe optional mapping.

### Improved

- **N+1 query elimination**: List fetches now use batch loading for tags, checklist items, projects, and areas (4 queries total instead of 4×N). ~80% fewer database queries for large lists.
- **Filter command efficiency**: `clings filter` now uses a single `fetchAllOpen()` query instead of fetching from 5 separate lists sequentially.
- **Logbook pagination**: `clings logbook --limit N` controls how many completed todos are returned (default: 500).
- **Search pagination**: `clings search --limit N` controls result count (default: 100).

## [0.3.0] - 2026-03-02

### Added

- **Reopen command**: Reopen completed or canceled todos with `clings reopen <ID>`. Includes status validation and confirmation of state change.
- **Test database infrastructure**: Self-contained SQLite test databases via `TestDatabaseBuilder` enable testing all database queries without a live Things 3 installation. 36 new database tests cover list membership, date decoding, search, checklist items, and trashed item exclusion.
- **Schema drift detection**: `SchemaDriftTests` compare the live Things 3 database schema against a checked-in baseline (`schema-baseline.json`). Automatically skipped in CI where Things 3 is unavailable.
- **GitHub Actions CI**: Automated build and test on every push to main/dev and PRs to main. Runs `swift build`, `swift test`, and `swift build -c release` on macOS 15.
- **Things 3 release monitor**: Weekly GitHub Actions workflow checks culturedcode.com for new Things 3 versions and creates an issue with action items when an update is detected.
- **Todo model fields**: `startDate`, `isRecurring`, and project `area` inheritance are now exposed in the Todo model and available in filter queries.

### Fixed

- **Things 3 date decoding**: Packed dates (used for `startDate` and `deadlineDate`) now decode correctly using the Things 3 bit-packing format instead of treating raw integers as Unix timestamps.
- **Date comparison in queries**: Filter comparisons like `due < today` now work correctly against packed date values.
- **Single-todo JSON output**: `clings show <ID> --json` now uses the same `TodoJSON` format as list commands for consistent output.
- **Recurring filter**: `clings filter "recurring = true"` now correctly uses boolean comparison instead of string comparison.
- **JXA test suite**: Fixed 14 pre-existing test failures where `createTodo` tests expected JXA format but the implementation uses AppleScript.

### Changed

- **`dueDate` renamed to `deadlineDate`** in JSON output to match Things 3's internal terminology. This is a **breaking change** for scripts consuming `--json` output.
- **`ThingsDatabase` accepts explicit path**: `ThingsDatabase(databasePath:)` and `CLINGS_DB_PATH` environment variable allow pointing at any SQLite file, enabling testing and custom setups.
- **Documentation updates**: CLAUDE.md module structure, README.md filter fields, and command reference updated to match current codebase.

## [0.2.10] - 2025-12-29

### Fixed

- **Todo creation via AppleScript**: Avoids JXA "Can't make class" failures and schedules `when` dates using the Things `schedule` command.
- **Tag automation reliability**: Corrected tag existence checks so tag add/update/delete/rename and multi-tag updates work again.

## [0.2.9] - 2025-12-29

### Fixed

- **Multi-tag updates via AppleScript**: Set tag names using a comma-separated string to avoid AppleScript type errors when applying multiple tags.

## [0.2.8] - 2025-12-29

### Fixed

- **JXA crash on null modificationDate**: JXA list/search/fetch now safely handles missing modification dates (falls back to creationDate), fixing crashes in `clings filter` and list commands.

### Changed

- **No URL scheme usage**: Removed all Things URL scheme usage across add/update/open/project flows. Tag updates now use AppleScript, and creation uses JXA + AppleScript.
- **Open command disabled**: `clings open` now reports a clear error when invoked because URL schemes are disabled.
- **Bulk tag add**: Bulk tag operations now apply tags via update instead of printing a URL scheme warning.

## [0.2.7] - 2025-12-16

### Added

- **Project creation**: Create projects via `clings project add`:
  - `clings project add "Project Name"` - Create a new project
  - `clings project add "Sprint" --area "Work" --deadline 2025-01-31` - With options
  - Supports `--notes`, `--area`, `--when`, `--deadline`, and `--tags` flags
  - `clings project list` (or just `clings project`) - List all projects

- **Complete by title search**: Complete todos by searching their title:
  - `clings complete --title "buy milk"` - Search and complete by title
  - `clings complete -t "groceries"` - Short form
  - Shows disambiguation list when multiple todos match
  - Original ID-based completion still works: `clings complete ABC123`

## [0.2.6] - 2025-12-16

### Added

- **Tag CRUD commands**: Full tag management via `clings tags` subcommands:
  - `clings tags add "TagName"` - Create a new tag
  - `clings tags delete "TagName"` - Delete a tag (with confirmation unless `--force`)
  - `clings tags rename "OldName" "NewName"` - Rename a tag
  - `clings tags list` - List all tags (also the default when running just `clings tags`)

### Changed

- `clings tags` command now supports subcommands instead of only listing tags.
- Tag CRUD operations use AppleScript (not JXA) for reliable execution.

## [0.2.5] - 2025-12-16

### Fixed

- **`update --tags` silent failure**: Fixed critical bug where `clings update <id> --tags` would report success but never actually apply tags. Root cause was JXA's `todo.tags.push()` silently failing. Now uses Things URL scheme (`things:///update?id=X&tags=Y`) for reliable tag updates.

### Changed

- Tag operations in `updateTodo()` now use URL scheme instead of JXA for reliability.
- Added documentation comments explaining JXA tag limitations.

## [0.1.6] - 2025-12-08

### Fixed

- **`add --area` AppleScript error (-1700)**: Area assignment now correctly sets `todo.area` after `Things.make()` instead of attempting to set it in `withProperties`, which caused a JXA type conversion error.

- **`add --project` silent failure**: Added fallback to `Things.projects.whose()` when `Things.lists.byName()` fails to find a project, fixing cases where todos would silently land in Inbox instead of the specified project.

- **Emoji in title causes error**: Updated string escaping to use JSON encoding, which properly handles all Unicode characters including emoji (e.g., `⚠️`, `🖥️`).

- **Area ignored when project specified**: Removed the conditional that prevented area assignment when a project was also specified. Area and project can now be used together.

### Added

- **`--area` flag for `todo update`**: You can now move existing todos to a different area using `clings todo update <ID> --area "Area Name"`.

## [0.1.5] - 2025-12-05

### Fixed

- Fixed `add` command bugs with area, when/deadline, and project handling.

### Added

- Code quality audit: fixed 98% of clippy warnings, improved documentation.
- Homebrew installation support via `brew install dan-hart/tap/clings`.

## [0.1.4] and earlier

Initial development releases with core functionality:
- List views (today, inbox, upcoming, anytime, someday, logbook)
- Todo management (add, complete, cancel, update)
- Project management
- Search with filters
- Natural language parsing for quick add
- Shell completions (bash, zsh, fish)
- JSON output for scripting
- Terminal UI (tui)
- Statistics and review features
