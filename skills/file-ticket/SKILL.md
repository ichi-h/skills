---
name: file-ticket
description: A skill that groups accepted findings by concern and files them as task-management tickets. Follow the task-management skill for schema operations.
---

# File Ticket Skill

Group the accepted findings from findings.md **by concern** and file them as `task-management` tickets.

**The deliverable of this skill is tickets (INSERTs into tickets / tasks). Do not change a single line of code.**

## Principles

- The unit of filing is **one concern, not one finding** (`1 ticket = 1 issue = 1 PR`).
  Findings that come from the same cause, the same file, or the same design decision are grouped into one ticket.
  A guideline is 2–6 tasks per ticket. Independent fixes (a different bug in another module,
  a different perspective, a different risk) are split apart.
- A ticket's `description` consists of the three elements of an issue (`## What is the problem` /
  `## Why solve it` / `## Approach to the solution`). The headings are fixed.
  - What is the problem: observed phenomena, with `path:line`. Do not write opinions.
  - Why solve it: the cost of leaving it (data corruption, future change cost). Do not write subjectivity.
  - Approach to the solution: where and at which layer to fix it. If the approach is undecided, do not file
    (make it a "decide the approach" ticket instead).
- Order the tasks so that completing all of them resolves the issue, in executable order.
  Baseline: 1. reproduction test → 2. core fix → 3. call sites → 4. regression check.
  Add dependencies only when they truly exist, and cycle-check them once added (see `task-management`).
- **Avoid duplicates.** Before filing, check whether the same concern already exists in the DB.
  ```sql
  SELECT uid, title, state FROM tickets
  WHERE state IN ('not_yet', 'in_progress')
    AND (title LIKE '%keyword%' OR description LIKE '%keyword%')
  ORDER BY id DESC LIMIT 20;
  ```
  If it exists, do not file a new ticket; instead append one line to the end of the relevant section
  in that ticket's `description` — `- Appended (review-<label>): ...` — and add tasks.
  **Do not add headings** (the three elements stop being extractable). Do not append to `completed`
  tickets; file a new one.

## Findings that came from a review

- **File the defect, not the review.** A finding whose content is "this was hard to verify" is a gap
  in `evidence.md` (handled in `review-integrate`), not a ticket. File what is wrong with the code.
- **"Needs confirmation" is not MUST.** An item a reviewer could not confirm stays a
  "decide the approach" ticket that names what has to be checked, never a fix ticket that asserts
  the defect.
- **Group by cause across perspectives.** A spec finding and a code finding that both come from
  "the reload path has no single owner" are one ticket. The perspective is where it was noticed,
  not what it is.
- **Write the origin into the ticket** (`review-<label>` / the perspective), so a later reader can
  find the report the claim came from.

## Steps

1. Group the accepted findings from findings.md by concern and build a list of ticket units.
2. Check for duplicates against existing tickets (the SQL above).
3. Following the `task-management` schema, `INSERT` the tickets and tasks
   (`PRAGMA foreign_keys = ON;`, wrap multiple statements in `BEGIN; ... COMMIT;`,
   receive uid via `INSERT ... RETURNING uid`).
   Do not touch the state of the ticket under review. Filed tickets are left as `not_yet`.
4. Append a "Filing result" section to the end of findings.md (uid / title / task count / origin).
   This lets you trace later where a finding went.

5. **Write back what the review taught about the flow itself.** If the review ran over its budget
   or a reviewer needed material the fact pack lacked, note it next to the filing result —
   the next `review-prepare` run starts from that note.

## Report

When filing is done, return a single block.

```text
Filed: 3 (review <label> / 11 accepted findings grouped)
- tk01 Consolidate input validation in the handler layer   tasks 3 / perspectives: code, security
- tk02 Eliminate N+1 in list retrieval                     tasks 2 / perspectives: code
Appended: 1 (added 1 task to existing tk0x)
Rejected: 4 (see "Rejected" in findings.md)
Code changes: none
```

## Done conditions

- Every accepted finding is linked to either a "filed ticket" or an "append to an existing ticket"
- Filed tickets contain the three elements of an issue and their tasks
- The filing result is recorded in findings.md
- **There are no changes in the diff**
