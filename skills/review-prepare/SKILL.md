---
name: review-prepare
description: Preparation for parallel review. A skill that pins down the diff under review and produces the fact pack (evidence.md) handed to reviewers. It makes no judgements about findings.
---

# Review Prepare Skill

Pin down what is under review and build a fact pack that lets reviewers judge without exploring.

**The deliverable of this skill is evidence.md. Do not judge findings. Do not change a single line of code.**

## Principles

- Reviewers read `evidence.md` (the judgements) and open `diff.patch` only for the lines a finding
  cites. **The diff is not repeated inside `evidence.md`.** It is on disk as `diff.patch`, and that
  is the only copy. Inlining it made the diff 93% of the pack in measured runs, and every reviewer
  re-read the whole patch instead of the facts.
- **Every fact appears exactly once.** Do not put a file both in full and in the diff.
- **A fact the reviewer cannot see is a tool call.** Do not write `see docs/requirements.md:117-133`;
  paste the sentences. Half-written acceptance criteria make every reviewer open that file.
- **A fact needs a reason to exist.** A paragraph whose only content is a pointer to a location is
  not a fact; it is an invitation to explore.

## The artifact directory

```
/tmp/review-<label>/
  evidence.md      # what reviewers read: §1 ticket, §2 inventory, §3 verified facts
  diff.patch       # the only copy of the diff (lockfiles and artefacts already removed)
  files/           # full text of changed files, for when a hunk is not enough
  check.log        # full log of the verification commands
  status.before    # `git status --porcelain` at the start, for the done check
  name-status.txt  # machine-readable file list
  shortstat.txt    # committed / uncommitted counts
```

The collectors (`diff.patch`, `files/`, `check.log`, `shortstat.txt`, `name-status.txt`,
`status.before`) are facts, not summaries. Their size does not count against the pack: they are read
on demand.

## Steps

### 1. Pin down the target

Receive from the user (or the orchestrator) the ticket ID under review, the branch, the comparison base
`base` (the merge target ref), and the acceptance criteria. If anything is unclear, ask.

```bash
mkdir -p /tmp/review-<label>
# Keep the task-management DB (.<username>/issues.db) out of the working tree diff
EXCLUDE="$(git rev-parse --git-path info/exclude)"
mkdir -p "$(dirname "$EXCLUDE")"
grep -qxF ".$(whoami)/" "$EXCLUDE" 2>/dev/null || echo ".$(whoami)/" >> "$EXCLUDE"
git status --porcelain > /tmp/review-<label>/status.before   # record used for the done check
git diff --shortstat "<base>...HEAD"                          # split the review if over 800 lines
```

- Judge completion by the difference from `status.before`. Dirty state before starting is acceptable.
- **If the target diff exceeds 800 changed lines, do not review it in one pass.** Split it and return.
  Split by concern, not by file count — a wave groups the files that one perspective has to hold in
  its head at once (`app/lib/*` in one wave, `server/*` + `test/*` in another, for instance).
  Set `OUT` per wave (`/tmp/review-<label>-1`, `-2`) and carry the same ticket in each.
- Untracked (`??`) files do not appear in the diff. If they belong in scope, run `git add -N <path>`.
  `collect-evidence.sh` reports the count of untracked files it skipped; an empty diff from untracked
  work is not an empty review.

### 2. Generate evidence.md

`collect-evidence.sh` builds the skeleton and the collectors. Call the script by a path relative to
**this skill's directory** (the install location differs per environment).

```bash
SKILL_DIR=<this skill's directory>
"$SKILL_DIR/scripts/collect-evidence.sh" <base-ref> /tmp/review-<label> \
  --ticket <uid> \                     # optional: fill §1 from the task-management DB
  -- "bun run typecheck" "bun test"    # verification commands; decide them per project
```

What it does:

- **Writes the diff to `diff.patch` only.** `evidence.md` carries a file table, the shortstat and the
  changed-line count instead.
- **Drops lockfiles and build artefacts** (lockfiles, `dist/`, `build/`, `coverage/`, `node_modules/`,
  `*.min.*`, `*.map`, `*.snap`, generated code) from both the patch and `files/`, and lists each one
  in §2 with its status and +/− counts so nobody wonders where it went.
- **Fills §1 from the ticket** when `--ticket <uid>` is given and `.<username>/issues.db` exists.
  Without it, §1 keeps its TODOs.
- **Enforces the budget itself**: 15 KB / 400 lines for the pack, 800 changed lines for the patch.
  Over budget, it writes the artifacts and exits **3** — the review must then be split or the material
  trimmed. Do not lower the budget to fit the file.

When a hunk alone is not enough to judge a modified file, add the relevant region with
`scripts/evidence-ranges.py` — never the whole file:

```bash
git -c core.quotePath=false diff --no-color "<base>...HEAD" -- docs/operations.md \
  | "$SKILL_DIR/scripts/evidence-ranges.py" --file docs/operations.md --pad 15
```

Note this is an extra: the patch and `files/` already hold the text, so add a region only when
carrying the pointer costs the reviewer more than the region costs the pack.

### 3. Fill in the TODOs

Fill in `## 3` (verified facts) of the generated evidence.md — and `## 1` only when it was not filled
from the ticket. `## 2` is generated; do not touch it. There is no `## 4`; notes for the review belong
in the dispatch prompt (`review-dispatch/templates/prompt.md`), which every reviewer already receives.

Fill in **only what reviewers tend to re-verify**:

- Behaviour actually confirmed by running it (the relevant lines of the run log)
- Framework or dependency behaviour where judgements diverge (down to `node_modules/pkg/file:line`)
- **The relevant lines of the spec, quoted.** Not the location — the text. `docs/requirements.md:117-133`
  alone is an instruction to go and read it; four pasted sentences are a fact.
- Explicit notes on out-of-scope items and known gaps

**Always attach file:line to facts.** Without it, reviewers start "just checking", and fall into exploration mode.

### 4. Check the budget before dispatching

```bash
echo "exit: $?"   # from step 2 — anything other than 0 means do not dispatch
grep -c 'TODO' /tmp/review-<label>/evidence.md   # must be 0 apart from genuinely out-of-scope items
wc -c -l /tmp/review-<label>/evidence.md         # expected within 15 KB / 400 lines
```

The script already fails on size; the grep catches the other half — an unfilled pack is smaller than
budget and looks perfect. Both checks exist because each catches what the other misses.

- Over the budget: split into another wave or move material out. **Do not lower the budget to fit
  the file** — the reviewers pay for every line.
- Before dispatching, ask of every paragraph: "can a reviewer reach the finding from this file
  alone?" A paragraph that only points at a location is not a fact; it is a reason to explore.

## Done conditions

- `/tmp/review-<label>/evidence.md` exists, its TODOs are filled in, and `collect-evidence.sh` exited 0
- `/tmp/review-<label>/diff.patch` exists (the reviewers will read it)
- `/tmp/review-<label>/status.before` has been recorded
- **There are no changes in the diff**
