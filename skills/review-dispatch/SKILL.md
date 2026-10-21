---
name: review-dispatch
description: A skill that delegates perspective-based reviews to agents in parallel and collects the findings tables. The orchestrator itself does not review.
---

# Review Dispatch Skill

**Delegate perspective-based reviews to agents in parallel** and collect the findings tables.

**The deliverable of this skill is the findings tables (report-<perspective>.md). Do not integrate or accept/reject. Do not change a single line of code.**

## Principles

- **The orchestrator does not review.** All judgements are made by reviewers (child agents).
- The delegation mechanism does not matter (subagent, tmux, herdr — anything that can start in parallel).
  **The point is to launch multiple perspectives in parallel in a single call.** Running them in sequence stacks up time.
- No polling. Do not wait with `sleep`; wait for the completion notification (`--wait`).

## Steps

1. **Choose perspectives.** Only those needed. At most 3 (if more, split into 2 waves).

   | Perspective | Required when | thinking |
   |---|---|---|
   | Code | Always | medium |
   | Security | Touches authentication, authorization, external input, or secrets | high |
   | Tests | Tests are added or changed | medium |
   | Architecture | Touches aggregate boundaries, the domain layer, or public APIs | high |
   | Spec | Requirements or acceptance criteria exist | medium |

2. **Build the prompts.** One prompt per perspective. Fill in every `{{...}}` and save it to
   `/tmp/review-<label>/prompt-<perspective>.md`.

   Required elements of a prompt:
   - The target ({{TICKET}}) and the path to evidence.md ({{EVIDENCE}})
   - The perspective-specific checklist ({{CHECKLIST}})
   - The range of files that may be read (evidence.md and its immediate surroundings only; any exploration
     becomes a one-line item under "Unconfirmed items")
   - No re-verification of verified facts, no re-running of commands
   - **No file edits**
   - The output format (the findings table below)

   ```text
   | Severity | Location | Finding | Evidence | Suggested fix |
   |---|---|---|---|---|
   | MUST | app/foo.ts:42 | … | … | … |
   ```

   - Severity: MUST (the goal is unmet or there is a serious defect unless fixed) / NITS (behaviour is the same
     but it is better to fix) / IMO (a proposal that could lead to a better implementation)
   - Location is `path:line`. If the line cannot be identified, use `path` only.
   - For the same cause in multiple places, cite one representative line and mention the others
     (`app/a.ts:12` (also: `app/b.ts:30`)).
   - If there is nothing to report, write only `No findings`.
   - Output must be at most 60 lines. After the table, the only allowed content is `Unconfirmed items:`
     (at most 5 lines).

   Before dispatching, check that no unsubstituted `{{` remains.

   ```bash
   f=/tmp/review-<label>/prompt-<perspective>.md
   [ -f "$f" ] || { echo "Prompt not created: $f"; exit 1; }
   ! grep -n '{{' "$f" || { echo "Unsubstituted placeholders remain. Do not dispatch"; exit 1; }
   ```

3. **Launch in parallel.** Start as many reviewers as there are perspectives, in a single call.
   When they finish, save the results (the result files from the completion notifications) to
   `/tmp/review-<label>/report-<perspective>.md`.

4. **Confirm collection.** Done once the reports for all perspectives are in. Do not judge the content.

## Budget

- Tool calls per reviewer: at most 20
- Output per reviewer: at most 60 lines (80 lines only when MUST findings are numerous)
- Wall-clock for the whole review: 10 minutes (wait cap per reviewer: 15 minutes)

## Done conditions

- `report-<perspective>.md` for every perspective exists in `/tmp/review-<label>/`
- **There are no changes in the diff**
