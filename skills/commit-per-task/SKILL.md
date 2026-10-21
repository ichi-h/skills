---
name: commit-per-task
description: Make one Git commit each time a task is completed, following Conventional Commits. Use this automatically whenever the task-management skill is in use, unless the user says the commits are not needed.
---

# Commit per Task Skill

Use this together with the `task-management` skill. This skill only covers version control.

## Rules

- **One commit per completed task.** Never bundle tasks, and never leave a completed task uncommitted.
- **Commit before marking the task completed.**
- **One concern per commit.** Unrelated refactors or formatting belong in their own task.
- **Stage only the files the task touched.** Exclude generated files and local DB files.
- No `--no-verify`, no `--force` push.

## Message format

Follow Conventional Commits v1.0.0.

```text
<type>(<scope>): <description>

<body>
```

- `type`: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- `scope`: the affected domain (module, package, or directory — e.g. `client`, `server`, `skills`). Omit only for repo-wide changes.
- `description`: imperative, lowercase, no trailing period, header within 72 characters. Say what the change does.
- `body`: why and what, wrapped at 72 characters. Skip when self-evident.

Mark breaking changes with `!` after the type/scope and add a `BREAKING CHANGE:` footer describing the break and how to migrate.

```text
feat(db)!: rename not_yet to pending

BREAKING CHANGE: existing DBs must be migrated.
```
