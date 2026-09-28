![clings](https://ghrb.waren.build/banner?header=![iterm2]+clings&subheader=Manage+Things+3+with+natural+language,+bulk+ops+%26+search&bg=1a1a2e&color=e0e0e0&support=true)

# clings - a feature-rich cli for Things 3 on macOS

> "clings" rhymes with "things"

> **Disclaimer:** This project is not affiliated with, endorsed by, or sponsored by [Cultured Code](https://culturedcode.com/). Things 3 is a registered trademark of Cultured Code GmbH & Co. KG. clings is an independent, open-source project that provides a command-line interface wrapper for the Things 3 application.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Built with Swift](https://img.shields.io/badge/built%20with-Swift-FA7343.svg)](https://swift.org/)
[![macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://www.apple.com/macos/)

**clings** brings the power of [Things 3](https://culturedcode.com/things/) to your terminal. Manage tasks, projects, and workflows with natural language, bulk operations, and powerful search - all without leaving the command line.

## Features

### 1. View Commands

Access all your Things 3 lists directly:

```bash
clings today             # or: clings t (default command)
clings inbox             # or: clings i
clings upcoming          # or: clings u
clings anytime
clings someday           # or: clings s
clings logbook           # or: clings l

# Organization
clings projects          # List all projects
clings areas             # List all areas
clings tags list         # List all tags
clings show <ID>         # Show details of a specific todo
```

### 2. Natural Language Task Entry

Add tasks using natural language parsing:

```bash
clings add "buy milk tomorrow #errands"
clings add "call mom friday @Family !high"
clings add "finish report by dec 15 #work"
clings add "review PR // needs careful testing - check auth - verify tests"

# Supported patterns:
# - Dates: today, tomorrow, next monday, in 3 days, dec 15
#   (a reminder time goes through --when, e.g. --when "friday@15:00")
# - Tags: #tag1 #tag2
# - Projects: for ProjectName or @ProjectName
# - Areas: in AreaName
# - Deadlines: by friday
# - Priority: !high, !!, !!!
# - Notes: // notes at the end
# - Checklist: - item1 - item2
```

You can also use explicit flags:

```bash
clings add "Task title" \
  --when tomorrow \
  --deadline "2024-12-31" \
  --tags work urgent \
  --project "Sprint 1" \
  --notes "Additional context"

# --when: today, evening, anytime, someday, a date, or date@HH:MM for a reminder
clings add "Standup notes" --when evening
clings add "Call the bank" --when "2026-10-01@14:00"
clings add "Read later" --when someday

# --project, --area and --heading take a title or an ID
clings add "Task" --project "Week #9" --heading "Personal"
clings add "Task" --area 9ehDXsRrBH7w4cSbLZY1pt
```

`add` prints the new todo's ID (`--json` returns `{"id": ..., "message": ...}`) and
fails loudly on an unparseable date or an unknown project instead of dropping the
value. Evening, reminder times, headings and checklist items are applied with a
URL scheme update right after creating the todo, which needs an auth token.

```bash

# Preview without creating
clings add "Test task tomorrow #work" --parse-only
```

### 3. Search and Filter

Search todos by text, or use the powerful filter command for advanced queries:

```bash
# Text search (case-insensitive, searches title and notes)
clings search "meeting"
clings find "project report"     # alias for search
clings f "status"                # short alias

# Advanced filtering (SQL-like query language)
clings filter "status = open"
clings filter "due < today AND status = open"
clings filter "tags CONTAINS 'urgent'"
clings filter "name LIKE '%report%'"
clings filter "project IS NOT NULL"
clings filter "when IS NOT NULL"        # todos with a scheduled date
clings filter "when < today"            # overdue scheduled todos
```

**Filter operators:** `=`, `!=`, `<`, `>`, `<=`, `>=`, `LIKE`, `CONTAINS`, `IS NULL`, `IS NOT NULL`, `IN`
**Logic:** `AND`, `OR`
**Fields:** `status`, `due` / `deadline`, `tags`, `project`, `area`, `name`, `notes`, `created`, `startdate`, `recurring`, `when` (scheduled date)

### 4. Todo Management

Manage individual todos:

```bash
# Show details
clings show <ID>

# Update properties (no auth token needed)
clings update <ID> --name "New title"
clings update <ID> --notes "Updated notes"
clings update <ID> --deadline 2024-12-25
clings update <ID> --tags work urgent
clings update <ID> --project "Week #9"          # title or ID

# Schedule and organize (requires auth token, see Configuration)
clings update <ID> --when tomorrow
clings update <ID> --when "2026-10-01@14:00"    # with a reminder
clings update <ID> --heading "Personal"
clings update <ID> --project "Week #9" --heading "Career"
clings update <ID> --area "Work"
clings update <ID> --append-notes "Called back, waiting"
clings update <ID> --add-tags waiting
clings update <ID> --clear-deadline

# Complete, cancel, delete, duplicate
clings complete <ID>             # or: clings done <ID>
clings complete --title "milk"   # complete by title search
clings reopen <ID>               # reopen a completed/canceled todo
clings cancel <ID>
clings delete <ID>               # moves to the Trash; or: clings rm <ID>
clings duplicate <ID>            # requires auth token

# Reveal in Things
clings open today
clings open <ID>
clings open "Work" --filter urgent
```

URL scheme updates are confirmed: clings watches the todo in the database and
reports an error when Things does not apply the change within a few seconds
(Things shows its own error dialog in that case).

### Undo

Every change made through clings can be reversed:

```bash
clings undo            # undo the latest change (a whole bulk command at once)
clings undo --show     # show what would be undone
clings undo --list     # recent history
```

| Change | Undo |
|--------|------|
| `add` | moves the new todo to the Trash |
| `update`, `bulk tag`, `bulk move` | restores title, notes, schedule, reminder, deadline, tags, project/area/heading and checklist (needs auth token) |
| `complete`, `cancel` | reopens |
| `reopen` | completes or cancels again |
| `delete` | takes it out of the Trash, back to its list |

The last 50 changes are kept in `~/.config/clings/undo-history.json` (0600).
Changes made in the Things app itself are not tracked.

### 5. Project Management

Create and manage projects:

```bash
# List all projects
clings project list              # or: clings projects

# Create a project
clings project add "Q1 Planning"
clings project add "Week #9" --area "Priority"
clings project add "Sprint" --area "Work" --deadline 2025-01-31

# Create a project with headings already in place
clings project add "Week #9" \
  --heading "Personal" \
  --heading "Career" \
  --heading "Family"

# List headings in a project (by name or UUID)
clings project headings "Week #9"
clings project headings <uuid>
clings project headings "Week #9" --json
```

> **Note:** Headings can only be created at project creation time via `--heading`. To add headings to an existing project, use the Things 3 app directly.

```bash
# Update a project (URL scheme options need an auth token)
clings project update <ID> --when someday
clings project update <ID> --area "Work" --append-notes "On hold" --add-tags waiting
clings project update <ID> --clear-deadline
```

### 6. Bulk Operations

Perform operations on multiple tasks using powerful filters.

> **Data Safety:** Bulk operations include built-in safety measures. Operations affecting more than 5 items require confirmation. Always use `--dry-run` first to preview changes.

```bash
# ALWAYS preview changes first with --dry-run
clings bulk complete --where "tags CONTAINS 'done'" --dry-run

# Complete matching tasks
clings bulk complete --where "tags CONTAINS 'done'"

# Cancel old project tasks
clings bulk cancel --where "project = 'Old Project'"

# Tag work tasks as urgent
clings bulk tag --where "project = 'Work'" urgent priority

# Move tasks to a project
clings bulk move --where "tags CONTAINS 'work'" --to "Work Project"
```

**Safety options:**
- `--dry-run` - Preview changes without applying them
- `--yes` - Skip confirmation prompts (use with caution)
- `--list` - Specify which list to operate on (default: today)

### 7. Statistics Dashboard

Track your productivity:

```bash
clings stats              # Show dashboard
clings stats trends       # Completion trends over time
clings stats heatmap      # Activity heatmap calendar
clings stats --days 7     # Limit to last 7 days
```

### 8. Weekly Review

Guide yourself through a GTD-style weekly review:

```bash
clings review             # Start a new review (default)
clings review start       # Same as above
clings review status      # Show last review session info
clings review clear       # Clear review session
```

### 9. Shell Completions

Generate shell completions:

```bash
clings completions bash > ~/.bash_completion.d/clings
clings completions zsh > ~/.zfunc/_clings
clings completions fish > ~/.config/fish/completions/clings.fish
```

### 10. Configuration

Set up the Things 3 auth token for features that use the Things URL scheme:

```bash
# Get your auth token from Things 3:
# Settings > General > Enable Things URLs > Copy auth token

# Save it to clings
clings config set-auth-token <your-token>
```

The auth token is stored at `~/.config/clings/auth-token` with restricted permissions (0600).

**Needs the auth token:**
- `add` with `--when evening`, a reminder time, `--heading` or checklist items
- `update` with `--when`, `--heading`, `--area`, `--append-notes`, `--prepend-notes`, `--add-tags`, `--clear-deadline` or checklist options
- `project add --heading`, `project update` with `--when`, `--area`, `--append-notes`, `--prepend-notes`, `--add-tags`, `--clear-deadline`
- `duplicate`
- `undo` of an update (and of deleting a scheduled todo)

**Works without it:**
- All read commands and `open`
- `add` with a date, deadline, tags, project or area
- `update` with `--name`, `--notes`, `--deadline`, `--tags`, `--project`
- `complete`, `cancel`, `reopen`, `delete`, `bulk`, and undoing them

## Requirements

- **macOS 10.15 (Catalina) or later**
- **Things 3 for Mac** - [Mac App Store](https://apps.apple.com/app/things-3/id904280696) or [Cultured Code](https://culturedcode.com/things/)
- **Automation Permission** - On first run, macOS will prompt you to grant automation permission

## Installation

### Homebrew (Recommended)

```bash
brew install m-moravcik/tap/clings
```

To upgrade to the latest version:

```bash
brew update && brew upgrade clings
```

### From Source

```bash
# Clone the repository
git clone https://github.com/m-moravcik/clings
cd clings

# Build release binary
swift build -c release

# Install
sudo cp .build/release/clings /usr/local/bin/
```

## Quick Start

```bash
# View today's tasks
clings today

# Add a quick task
clings add "buy groceries tomorrow #errands"

# Add a task under a heading in a project
clings add "Review PRs" --project "Work" --heading "Morning"

# View your inbox
clings inbox

# Search for tasks
clings search "project"

# Filter by status and date
clings filter "due < today AND status = open"

# List headings in a project
clings project headings "Week #9"

# Get productivity stats
clings stats

# Get help on any command
clings --help
clings add --help
clings project --help
```

## Command Reference

### Global Options

```
--json                   Output as JSON (for scripting)
--no-color               Suppress color output
-h, --help               Show help
--version                Show version
```

### Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `today` | `t` | Show today's todos (default) |
| `inbox` | `i` | Show inbox todos |
| `upcoming` | `u` | Show upcoming todos |
| `anytime` | - | Show anytime todos |
| `someday` | `s` | Show someday todos |
| `logbook` | `l` | Show completed todos |
| `trash` | - | Show trashed todos |
| `recent` | - | Show recently created todos (e.g. `recent 3d`, `recent 1w`) |
| `projects` | - | List all projects |
| `project list` | `project ls` | List all projects |
| `project add` | - | Create a new project (supports `--heading`) |
| `project update` | - | Update a project's properties |
| `project headings` | - | List headings in a project |
| `areas` | - | List all areas |
| `tags` | - | Manage tags |
| `show` | - | Show details of a todo by ID |
| `add` | - | Add a new todo; prints its ID |
| `update` | - | Update a todo's properties |
| `duplicate` | - | Duplicate a todo |
| `complete` | `done` | Mark a todo as completed |
| `reopen` | - | Reopen a completed/canceled todo |
| `cancel` | - | Cancel a todo |
| `delete` | `rm` | Delete a todo (moves to trash) |
| `undo` | - | Undo the latest change made with clings |
| `open` | - | Reveal a todo, project, area, tag or list in Things |
| `search` | `find`, `f` | Search todos by text |
| `filter` | - | Filter todos using SQL-like expressions |
| `bulk` | - | Bulk operations on multiple todos |
| `stats` | - | View productivity statistics |
| `review` | - | GTD weekly review workflow (start, status, clear) |
| `config` | - | Configure clings settings (auth token) |
| `doctor` | - | Check clings setup and local environment |
| `completions` | - | Generate shell completions |

## Output Formats

### Pretty (default)

Human-readable colored output:

```
Today (3 items)
──────────────────────────────────────────────
[ ] Review PR #123        Development   Dec 15   #work
[ ] Buy groceries         -             -        #personal
[x] Call dentist          Health        Dec 10   -
```

### JSON

Machine-readable JSON for scripting:

```bash
clings today --json | jq '.items[] | select(.tags | contains(["work"]))'
clings project headings "Week #9" --json | jq '.items[].title'
```

## Data Safety

- **Read operations:** Use direct SQLite access to the Things 3 database (read-only, fast)
- **Write operations:** Use AppleScript/JXA through the official Things 3 API (creating, scheduling via `schedule`, completing, trashing, moving between lists)
- **Everything AppleScript cannot set** (evening, reminders, headings, checklists, clearing deadlines): the Things 3 `json` URL scheme (requires auth token), confirmed against the database afterwards
- **List membership** mirrors Things itself: repeating templates only show in Upcoming, todos of Someday/completed/trashed projects are hidden, Someday lists loose todos only
- **No direct database writes:** clings never writes directly to the Things 3 database

### Best Practices

1. **Always use `--dry-run` first** when running bulk operations
2. **Start with small filters** to verify your filter expression matches what you expect
3. **Keep Things 3 backups** - Things 3 syncs to iCloud automatically

## Troubleshooting

### Automation permission error

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
```

Then enable Things 3 under your terminal application.

### Things 3 not running

Things 3 must be running for write operations (JXA). Read operations work even when Things 3 is closed.

### Auth token errors

```bash
# Re-set the auth token
clings config set-auth-token <your-token>

# Token is stored at:
cat ~/.config/clings/auth-token
```

## Development

```bash
swift build              # Build
swift run clings today   # Run in debug mode
swift test               # Run tests (473 tests)
```

See [CLAUDE.md](CLAUDE.md) for detailed development guidelines.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make changes following code quality standards
4. Add tests for new functionality
5. Ensure all checks pass: `swift build && swift test`
6. Submit a pull request

## License

GNU General Public License v3.0 (GPLv3) - see [LICENSE](LICENSE)

## Links

- **This fork:** https://github.com/m-moravcik/clings
- **Upstream:** https://github.com/drewburchfield/clings
- **Things 3:** https://culturedcode.com/things/
