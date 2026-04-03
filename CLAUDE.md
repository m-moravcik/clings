# CLAUDE.md - clings Project Guidelines

> A Things 3 CLI for macOS

## Project Overview

**clings** is a fast, feature-rich command-line interface for [Things 3](https://culturedcode.com/things/) on macOS, written in Swift.

- **License:** GNU General Public License v3.0 (GPLv3)
- **Platform:** macOS only (requires Things 3 installed)
- **Technology:** Swift + SQLite (reads) + JavaScript for Automation (JXA) via `osascript` (writes)
- **Version:** 0.3.3

## Build & Run

```bash
# Build
swift build

# Run
swift run clings today
swift run clings --help

# Test
swift test

# Build release
swift build -c release
```

## Architecture

### Hybrid Read/Write Approach

clings uses a **hybrid architecture** for optimal performance and safety:

- **Reads:** Direct SQLite access to the Things 3 database (~30ms response time)
- **Writes:** JXA/AppleScript through the official Things 3 automation API

This approach provides:
- Near-instant reads without launching Things 3
- Safe writes through the official API
- Compatibility with Things 3 updates

### Module Structure

```
Sources/
├── ClingsCLI/
│   └── Commands/              # Command implementations (AddCommand, ListCommands, etc.)
├── ClingsCore/
│   ├── Config/                # Auth token storage
│   ├── Filter/                # Filter DSL parser and expression evaluator
│   ├── Models/                # Todo, Project, Area, Tag, ChecklistItem, Status
│   ├── NLP/                   # Natural language task parsing
│   ├── Output/                # OutputFormatter (pretty + JSON)
│   ├── ThingsClient/          # ThingsDatabase (SQLite), JXAScripts, HybridThingsClient
│   └── Utils/                 # ThingsDateConverter, SchemaIntrospector
Tests/
├── ClingsCoreTests/
│   ├── Database/              # ThingsDatabaseTests, SchemaDriftTests, TestDatabaseBuilder
│   └── ThingsClient/          # JXAScriptsTests
├── SchemaBaseline/            # schema-baseline.json (schema drift detection)
```

### Design Principles

1. **Separation of Concerns:** CLI layer thin, business logic in ClingsCore
2. **Testability:** All business logic in library target
3. **Swift Best Practices:** Use Swift's type safety, optionals, and error handling
4. **Performance:** SQLite for reads, batch operations where possible

## Code Quality Standards

### Error Handling

```swift
// Use typed errors
enum ClingsError: LocalizedError {
    case thingsNotRunning
    case permissionDenied
    case notFound(String)
    case databaseError(String)

    var errorDescription: String? {
        switch self {
        case .thingsNotRunning:
            return "Things 3 is not running"
        case .permissionDenied:
            return "Automation permission required.\n\nGrant access in System Settings > Privacy & Security > Automation"
        case .notFound(let item):
            return "Item not found: \(item)"
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}
```

**Rules:**
- Use Swift's `Error` protocol for custom error types
- Use `throws` and `try` for error propagation
- NEVER use force unwrapping (`!`) in production code
- All error messages must be user-friendly with actionable guidance
- Handle macOS automation permission errors gracefully

### Swift Concurrency

Use async/await for I/O operations:

```swift
func fetchTodos() async throws -> [Todo] {
    try await withCheckedThrowingContinuation { continuation in
        // Database or JXA operation
    }
}
```

### Formatting

Use SwiftFormat with project defaults. Import organization:

```swift
// 1. Foundation/Standard library
import Foundation

// 2. External packages
import ArgumentParser
import GRDB

// 3. Internal modules
import ClingsCore
```

## Testing Requirements

### Database Path Resolution

`ThingsDatabase` resolves its path in order:
1. Explicit `databasePath` parameter (throws if file not found)
2. `CLINGS_DB_PATH` environment variable (throws if file not found)
3. Auto-discovery from Things 3 group container (falls back to JXA-only client)

### Test Categories

**Unit Tests** - Test models, parsing, formatting:
```swift
import Testing
@testable import ClingsCore

@Suite("TaskParser")
struct TaskParserTests {
    @Test func parseDateToday() {
        let result = TaskParser.parseDate("today")
        #expect(result != nil)
    }
}
```

**Database Integration Tests** - Test real SQLite queries using `TestDatabaseBuilder`:
```swift
let builder = try TestDatabaseBuilder()
DatabaseTestFixtures.populate(builder)
let db = try ThingsDatabase(databasePath: builder.path)
let todos = try db.fetchList(.today)
```

`TestDatabaseBuilder` creates a temp SQLite file with the exact Things 3 schema (all 41 TMTask columns, plus TMArea, TMTag, TMTaskTag, TMAreaTag, TMChecklistItem). No live Things 3 installation needed.

**Schema Drift Tests** - Compare live Things 3 DB against `Tests/SchemaBaseline/schema-baseline.json`. Auto-skip in CI via `XCTSkip` when Things 3 is not installed. Run locally with:
```bash
swift test --filter SchemaDrift
```

If Things 3 updates its schema, run `scripts/update-schema-baseline.sh` after verifying compatibility.

### Coverage Requirements

- **Minimum:** 80% overall code coverage
- **Critical Paths:** 95%+ coverage for:
  - Error handling
  - Database access
  - CLI argument parsing

## Dependencies (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "6.24.0"),
    .package(url: "https://github.com/malcommac/SwiftDate", from: "7.0.0"),
]
```

| Package | Purpose |
|---------|---------|
| swift-argument-parser | CLI argument parsing |
| GRDB.swift | SQLite database access |
| SwiftDate | Date/time parsing and formatting |

## CLI Design Guidelines

### Command Structure

```
clings [OPTIONS] <COMMAND>

Options:
  --json                 Output as JSON (for scripting)
  --no-color             Suppress color output
  -h, --help             Show help
  --version              Show version

Commands:
  today, t (default)     Show today's todos
  inbox, i               Show inbox todos
  upcoming, u            Show upcoming todos
  anytime                Show anytime todos
  someday, s             Show someday todos
  logbook, l             Show completed todos
  projects               List all projects
  areas                  List all areas
  tags                   List all tags
  show                   Show details of a todo by ID
  add                    Quick add with natural language
  complete, done         Mark a todo as completed
  reopen                 Reopen a completed/canceled todo
  cancel                 Cancel a todo
  delete, rm             Delete a todo
  update                 Update a todo's properties
  search, find, f        Search todos by text
  bulk                   Bulk operations on multiple todos
  filter                 Filter todos using a query
  open                   Open a todo or list in Things 3
  stats                  View productivity statistics
  review                 Interactive weekly review workflow
  completions            Generate shell completions
```

### Design Principles

1. **Intuitive:** Commands match Things 3 terminology
2. **Scriptable:** JSON output for piping and automation
3. **Informative:** Exit codes indicate success (0), user error (1), system error (2)
4. **Complete:** Shell completions for bash, zsh, fish
5. **Fast:** SQLite reads complete in ~30ms

## CI/CD Requirements

### GitHub Actions Workflow

Every PR must pass:
1. `swift build` - Build succeeds
2. `swift test` - All tests pass
3. `swift build -c release` - Release build succeeds

### Release Process

Releases are automated via GitHub Actions (`.github/workflows/release.yml`). The workflow triggers on tag push matching `v*` and handles building, testing, GitHub Release creation, and Homebrew tap updates.

**To release a new version:**

1. Update `version` in `Sources/ClingsCLI/Clings.swift`
2. Add a `## [X.Y.Z]` section to `CHANGELOG.md`
3. Commit and merge to main
4. Run `scripts/release.sh X.Y.Z`

The script validates your working tree, version match, and changelog entry, then creates an annotated tag and pushes it. GitHub Actions handles the rest:
- Validates tag matches source version
- Builds release binary (macOS ARM64)
- Runs tests
- Creates GitHub Release with changelog excerpt and binary
- Updates `drewburchfield/homebrew-tap` Formula/clings.rb with new URL and SHA256

**Required secret:** `HOMEBREW_TAP_PAT` - fine-grained PAT scoped to `drewburchfield/homebrew-tap` with `Contents: Read and Write` permission. Set at `github.com/drewburchfield/clings/settings/secrets/actions`.

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make changes following these guidelines
4. Add tests for new functionality
5. Ensure all checks pass: `swift build && swift test`
6. Submit a pull request

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Claude Directives

- Never add Claude as a co-author on commits
- **Releases are automated.** When releasing a new version, update the version in `Clings.swift` and `CHANGELOG.md`, commit, then run `scripts/release.sh <version>`. Do not manually update the Homebrew tap; the release workflow handles it.
