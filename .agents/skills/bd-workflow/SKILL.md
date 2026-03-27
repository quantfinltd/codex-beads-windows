---
name: bd-workflow
description: Use for fast, low-token issue tracking with `bd` in this repository. Trigger when asked to create/list/update/close beads issues, inspect ready work, or manage dependencies. Apply especially when dependency direction must be correct and when the user requests "create beads only" without claiming or implementation work.
---

# Bd Workflow

## Overview

Execute consistent `bd` commands with minimal overhead and correct dependency semantics.
Default to JSON output and short, task-focused issue descriptions.

## Core Rules

- Read project-level instructions in `AGENTS.md` and obey them.
- Always pass `--json` for machine-readable output.
- If user asks to create beads only, create/update only; do not claim, start coding, or close unrelated issues.
- If a claim attempt is rejected (already claimed, permission denied, or policy rejection), stop immediately and report the failure; do not start or continue implementation on that bead.
- Only proceed without a claim when the user explicitly instructs unclaimed work for that specific bead.
- Link newly discovered follow-up work with `discovered-from:<parent-id>`.
- Use epic grouping only for large initiatives (big tasks with multiple independent beads and multi-step delivery).
- Do not create epics for small or single-step work; use direct task beads instead.
- Treat epics as roll-up containers; implement and claim child tasks, not the epic itself, unless user explicitly asks.
- For epic completion, check eligibility first and close via `bd epic close-eligible --json`; if not eligible, leave epic open.
- Prefer concise issue titles and acceptance-oriented descriptions.

## Quick Commands

```bash
# See unblocked work
bd ready --json

# List all issues
bd list --json

# Create issue
bd create "Title" --description="Context and expected outcome" -t task -p 1 --json

# Create issue discovered from another
bd create "Title" --description="Context" -t task -p 1 --deps discovered-from:<id> --json

# Update status or priority
bd update <id> --claim --json
bd update <id> --priority 1 --json

# Close issue
bd close <id> --reason "Completed" --json

# Epic status and closure
bd epic status --json
bd epic close-eligible --json
```

## Dependency Direction (Important)

Use this mental model:
- `A` blocks `B` means `B` depends on `A`.

Reliable commands:

```bash
# Add "A blocks B" relationship
bd dep add B A --type blocks --json

# Equivalent shorthand
bd dep A --blocks B --json
```

Validate direction when uncertain:

```bash
bd dep list <id> --json
```

## Minimal Workflows

### Create Beads Only
- Run `bd ready --json` or `bd list --json` if context is needed.
- Create requested issues with `bd create ... --json`.
- Add required links/dependencies only.
- Stop after reporting created IDs and dependency wiring.

### Full Issue Lifecycle
- Start with `bd ready --json`.
- Claim only if explicitly asked: `bd update <id> --claim --json`.
- Treat claim rejection as a hard stop for that bead until user gives explicit direction.
- Create discovered follow-up with `--deps discovered-from:<parent-id>`.
- Close completed issue with reason.

### Large Initiative (Epic + Child Beads)
Use this only when work is large, for example:
- 4+ independent implementation beads
- changes span multiple systems/workflows
- expected to ship across multiple PRs or sessions

Workflow:
- Create epic: `bd create "Initiative title" -t epic -p 1 --json`
- Create child tasks under epic: `bd create "Task title" -t task -p 1 --parent <epic-id> --json`
- Add sequencing dependencies among children with `blocks` links.
- Do not claim epic for implementation work unless explicitly instructed by user.
- Use `bd epic status --json` to check completion roll-up and only close epics through `bd epic close-eligible --json`.

If a child already has `discovered-from:<epic-id>`, convert it before setting parent:
- `bd dep remove <child-id> <epic-id> --json`
- `bd update <child-id> --parent <epic-id> --json`

## Output Style

- Report issue IDs first.
- Mention dependency links explicitly (`X blocks Y`).
- Keep summaries short and action-oriented.
