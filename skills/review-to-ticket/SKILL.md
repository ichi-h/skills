---
name: review-to-ticket
description: A skill that reviews a ticket implementation from multiple perspectives in parallel, integrates the findings, and files them as tickets (issues) without fixing anything. Use it when asked to review, when you want to turn code findings into tasks, or when you want to hand findings off by filing them. It does not make changes. Do not use it for small checks that a single perspective covers.
---

# Review to Ticket Skill

Run perspective-based reviews in parallel, integrate the findings, and file them as `task-management` tickets.

**The deliverable of this skill is tickets. Do not change a single line of code.**

## Principles

- **The parent (orchestrator) must not review.** All judgements are delegated to child agents.
  The delegation mechanism does not matter (subagent / tmux / herdr / anything that can run in parallel).
  This skill only defines the flow that delegates to the 4 skills below.
- **Explore once, judge in parallel, file by concern.**
  Fact gathering happens exactly once at the start of this flow; reviewers only judge.
- **Always attach file:line to facts.**
  Without it, reviewers start "just checking", and fall into exploration mode.
- **Do not proceed over a limit.** Shrink the material or split into two waves instead.
  A review that overshoots the budget still produces a report, so the failure is silent —
  the limit is enforced by the orchestrator, not by the reviewer.

## Flow

Execute each step according to its own skill. The output directory
`/tmp/review-<label>/` is shared across all steps.

| #   | Responsibility                                                                           | Skill              | Deliverable                    |
| --- | ---------------------------------------------------------------------------------------- | ------------------ | ------------------------------ |
| 1   | Take in the review request. Pin down the target and build the fact pack                  | `review-prepare`   | `evidence.md`, `status.before` |
| 2   | Perform the review. Parallel delegation by perspective and collection of findings tables | `review-dispatch`  | `report-<perspective>.md`      |
| 3   | Integrate the review. Merge duplicate findings and decide accept/reject                  | `review-integrate` | `findings.md`                  |
| 4   | File tickets. Group by concern and `INSERT` into `task-management`                       | `file-ticket`      | tickets / tasks                |

## Budget

The whole review, end to end.

| Item                    | Limit                                               |
| ----------------------- | --------------------------------------------------- |
| `evidence.md` size      | 60 KB / 1,200 lines                                 |
| Diff under one review   | 800 lines (split beyond that, see `review-prepare`) |
| Perspectives per wave   | 3                                                   |
| Tool calls per reviewer | 15 (`review-dispatch` sets this in the prompt)      |
| Wall-clock              | 10 min per wave; wait cap 15 min per reviewer       |

If any limit is exceeded, **do not proceed.** Either shrink the material (step 1 again) or split the
review into two waves.

## Done conditions

- `/tmp/review-<label>/` contains `evidence.md`, `report-*.md` for every perspective, and `findings.md`
- Every accepted finding is linked to either a "filed ticket" or an "append to an existing ticket"
- Every line under a reviewer's `Unconfirmed items` is either resolved or recorded in `findings.md`
  (an unconfirmed item is a gap in the fact pack, not noise — see `review-integrate`)
- **There are no changes in the diff** (`git status` is the same as `status.before`)
