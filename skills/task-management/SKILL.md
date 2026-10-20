---
name: task-management
description: A skill for managing tickets (issues), tasks, and dependencies with sqlite3. Always use it when you want to break a development work item with a clear issue into multiple steps and proceed in order ("break this into tasks", "make this a ticket", "resume", mentions of issues.db, etc.). DO NOT use it for issues so simple that no decomposition is needed.
---

# Task Management Skill

## Terminology

- **Issue**: A problem to be solved. One issue, one concern. It must always include "what the problem is", "why it should be solved", and "the approach to the solution" (the three elements of an issue).
- **Ticket**: A record for managing an issue. As a guideline, 1 ticket = 1 issue = 1 PR.
- **Task**: A step required to solve the issue. Split as small as possible, at a granularity where completing all of them resolves the issue.

## Rules

- The DB is at `$(pwd)/.<username>/issues.db`. Get the username with `whoami` (e.g., if the username is `alice`, use `.alice/issues.db`). If it doesn't exist, run `mkdir -p ".$(whoami)"` and create it with the schema below.
- `PRAGMA foreign_keys = ON;` is a per-connection setting. Put it at the start of the SQL every time you run `sqlite3`.
- Wrap multi-statement updates in `BEGIN; ... COMMIT;`.
- uid is auto-generated. Receive it with `INSERT ... RETURNING uid` (`RETURNING` requires SQLite 3.35+).
- Assumes a single executor working through things in order (no exclusive locking).

## Schema

```sql
CREATE TABLE tickets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uid TEXT UNIQUE NOT NULL DEFAULT (lower(hex(randomblob(2)))) CHECK(length(uid) = 4),
  title TEXT NOT NULL,
  description TEXT NOT NULL, -- Three elements of an issue. Headings: ## What is the problem / ## Why solve it / ## Approach to the solution
  state TEXT NOT NULL DEFAULT 'not_yet'
    CHECK(state IN ('not_yet', 'in_progress', 'completed', 'archived'))
);

-- canceled means "judged unnecessary to solve the issue and therefore not executed". For dependency purposes, it is equivalent to completed.
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uid TEXT UNIQUE NOT NULL DEFAULT (lower(hex(randomblob(2)))) CHECK(length(uid) = 4),
  ticket_id INTEGER NOT NULL REFERENCES tickets(id),
  title TEXT NOT NULL,
  description TEXT NOT NULL, -- Concrete content / checklist
  state TEXT NOT NULL DEFAULT 'not_yet'
    CHECK(state IN ('not_yet', 'completed', 'canceled'))
);

-- A task becomes executable only once all of its dependencies are completed/canceled. A task with no dependencies is executable from the start.
CREATE TABLE task_dependencies (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id INTEGER NOT NULL REFERENCES tasks(id),
  depends_on_task_id INTEGER NOT NULL REFERENCES tasks(id),
  CHECK(task_id != depends_on_task_id),
  UNIQUE(task_id, depends_on_task_id)
);
```

## Flow

### 1. Save the issue to tickets

If there are multiple concerns, split the ticket. If the three elements of the issue can't be made clear, explain why, ask the user to reconsider, and do not save it.

```sql
INSERT INTO tickets (title, description) VALUES ('Summary', '## What is the problem ...') RETURNING uid;
```

### 2. Put all steps into tasks / task_dependencies

When starting work, run `UPDATE tickets SET state='in_progress' WHERE uid='..'`.

```sql
INSERT INTO tasks (ticket_id, title, description)
VALUES ((SELECT id FROM tickets WHERE uid='ticket uid'), 'Summary', 'Details') RETURNING uid, title;

-- B comes after A is completed
INSERT INTO task_dependencies (task_id, depends_on_task_id)
VALUES ((SELECT id FROM tasks WHERE uid='B uid'), (SELECT id FROM tasks WHERE uid='A uid'));
```

After adding a dependency, **always run a cycle check**. If even one row is returned, there is a cycle: delete the added dependency and rethink the design.

```sql
WITH RECURSIVE walk(origin, current, depth) AS (
  SELECT task_id, depends_on_task_id, 1 FROM task_dependencies
  UNION ALL
  SELECT w.origin, td.depends_on_task_id, w.depth + 1
  FROM walk w JOIN task_dependencies td ON td.task_id = w.current
  WHERE w.depth < 1000
)
SELECT DISTINCT t.uid, t.title FROM walk w JOIN tasks t ON t.id = w.origin
WHERE w.origin = w.current;
```

### 3. Fetch all executable tasks and carry them out

```sql
SELECT t.* FROM tasks t
WHERE t.ticket_id = (SELECT id FROM tickets WHERE uid='ticket uid')
  AND t.state = 'not_yet'
  AND NOT EXISTS (
    SELECT 1 FROM task_dependencies td
    JOIN tasks t2 ON td.depends_on_task_id = t2.id
    WHERE td.task_id = t.id AND t2.state NOT IN ('completed', 'canceled')
  );
```

### 4. Update state

```sql
UPDATE tasks SET state='completed' WHERE uid IN ('fe3a', 'w2gi');

-- Only when it has become unnecessary for solving the issue. "Tedious" or "difficult" is not a valid reason. Record the reason.
UPDATE tasks SET state='canceled', description = description || char(10) || '[canceled] Reason: ...'
WHERE uid='xxxx';
```

### 5. Repeat 3–4 and determine completion

Determine completion by **zero not-yet-started tasks**, not by "step 3 returns nothing".

```sql
SELECT COUNT(*) FROM tasks
WHERE ticket_id = (SELECT id FROM tickets WHERE uid='ticket uid') AND state='not_yet';
```

- 0 rows: Confirm that the issue is resolved, then `UPDATE tickets SET state='completed' ...`. After the PR is merged, etc., it may be set to `archived`.
- Tasks remain but step 3 is also empty: This is a dependency anomaly (a cycle or an incorrect dependency). Investigate the cause and report it to the user.

## Resuming

When crossing sessions, first check the status of work in progress, then return to step 3.

```sql
SELECT tk.uid, tk.title, t.uid AS task_uid, t.title AS task_title
FROM tickets tk
LEFT JOIN tasks t ON t.ticket_id = tk.id AND t.state='not_yet'
WHERE tk.state='in_progress' ORDER BY tk.id, t.id;
```

## Inserting a task

Insert a new task immediately after a target task. **Do the re-pointing of successors (UPDATE) first.** If you do it the other way around, the new task ends up depending on itself and stalls.

```sql
-- 1. Add the new task (use the returned uid below)
INSERT INTO tasks (ticket_id, title, description)
SELECT ticket_id, 'New task', 'Details' FROM tasks WHERE uid='target uid' RETURNING uid;

BEGIN;
-- 2. Re-point successors that depended on the target so they depend on the new task
UPDATE task_dependencies
SET depends_on_task_id = (SELECT id FROM tasks WHERE uid='new uid')
WHERE depends_on_task_id = (SELECT id FROM tasks WHERE uid='target uid');
-- 3. Place the new task after the target
INSERT INTO task_dependencies (task_id, depends_on_task_id)
VALUES ((SELECT id FROM tasks WHERE uid='new uid'), (SELECT id FROM tasks WHERE uid='target uid'));
COMMIT;
```
