---
name: review-to-ticket
description: A skill that reviews a ticket implementation from multiple perspectives in parallel, integrates the findings, and files them as tickets (issues) without fixing anything. Use it when asked to review, when you want to turn code findings into tasks, or when you want to hand findings off by filing them. It does not make changes. Do not use it for small checks that a single perspective covers.
---

# Review to Ticket Skill

Run perspective-based reviews in parallel, integrate the findings, and file them as `task-management` tickets.

**The deliverable of this skill is tickets. Do not change a single line of code.**

## Principles

- **The parent (orchestrator) must not review.** All judgements are delegated to child agents.
- **Explore once, judge in parallel, file by concern.** Fact gathering happens exactly once, at the
  start; reviewers only judge.
- **Paste the material, don't point at it.** Everything a reviewer needs goes into its prompt
  (facts with `path:line`, the quoted spec lines, the diff path). A paragraph that only names a
  location is an invitation to explore.
- **One turn per reviewer.** The prompt names the report file; collection is one read of that file.
  A second prompt to "write the table to a file" re-sends the whole context.
- **A budget belongs in the prompt.** A limit that is only written in the skill moves nothing.
- **Record silent failures.** Budget overruns and ignored limits go into `findings.md` as one line.

## Artifact directory

`/tmp/review-<label>/` is shared across all steps:

```
diff.patch             # the only copy of the diff (lockfiles and artefacts removed)
files/                 # full text of changed files, for when a hunk is not enough
evidence.md            # §1 ticket, §2 file inventory, §3 verified facts (≤ 15 KB / 400 lines)
prompt-<p>.md          # one prompt per perspective
report-<p>.md          # each reviewer's findings table
findings.md            # integrated decisions
status.before          # `git status --porcelain` at the start, for the done check
```

## Step 1 — Pin the target and build the evidence

Receive the ticket uid, the comparison base `base`, and the acceptance criteria. If unclear, ask.
Decide the split **before** building anything:

```bash
mkdir -p /tmp/review-<label>
git diff --shortstat "<base>...HEAD"   # > 800 changed lines ⇒ split by concern into waves
git status --porcelain > /tmp/review-<label>/status.before
git diff --no-color "<base>...HEAD" -- ':(exclude)*.lock' ':(exclude)dist/*' ':(exclude)build/*' \
  ':(exclude)coverage/*' ':(exclude)node_modules/*' ':(exclude)*.min.*' ':(exclude)*.map' \
  > /tmp/review-<label>/diff.patch
git diff --name-only "<base>...HEAD"   # copy the changed files' full text into files/ (skip generated code)
```

- Untracked (`??`) files do not appear in the diff; `git add -N <path>` those that belong in scope.
- Write `evidence.md` (≤ 15 KB / 400 lines, the diff stays in `diff.patch`):
  - **§1 ticket**: uid, title, acceptance criteria — **paste the requirement text, not a pointer.**
  - **§2 inventory**: file table with +/− counts and a shortstat line.
  - **§3 verified facts**: only what reviewers tend to re-verify — behaviour confirmed by running it
    (with the log lines), framework behaviour where judgements diverge (down to
    `node_modules/pkg/file:line`), the quoted spec lines, and the fact that decides a question two
    perspectives will both ask. Every fact carries `path:line`.
- When a hunk alone is not enough, paste the relevant region (±15 lines) into §3 — never the whole file.

## Step 2 — Build the prompts

Pick perspectives (max 3 per wave; more ⇒ split into waves):

| Perspective  | Required when                                                     | thinking |
| ------------ | ----------------------------------------------------------------- | -------- |
| Code         | Always                                                            | medium   |
| Security     | Touches authentication, authorization, external input, or secrets | high     |
| Tests        | Tests are added or changed                                        | medium   |
| Architecture | Touches aggregate boundaries, the domain layer, or public APIs    | high     |
| Spec         | Requirements or acceptance criteria exist                         | medium   |

Write one prompt per perspective to `/tmp/review-<label>/prompt-<p>.md`. It must contain all of:

1. **Role**: reviewer; judge, do not fix; nothing outside the artifact directory may be changed.
2. **Target**: the ticket uid, the paths of `evidence.md`, `diff.patch`, `files/`, and its report
   path `/tmp/review-<label>/report-<p>.md`.
3. **Budget block** (copy verbatim):
   ```text
   ## 予算 / Budget
   - ツール呼び出しは 15 回まで。超えそうなら打ち切って、残りを「未確認事項」に 1 行で書け。
   - 全体 60 行以内。表の後に書けるのは「未確認事項:」だけ（最大 3 行）。
   - 目安 8 分。判断は evidence.md の中で完結させる。

   ## 禁止 / Prohibited
   - evidence.md の「3. Verified facts」を再検証しない。§3 が報告しているコマンドは再実行しない。
   - インタプリタ・プローブを走らせない（node -e / python -c / tsx / sqlite3 / テストランナー）。
   - ファイルの作成・編集・削除は report-<p>.md 1 つだけ。それ以外のファイルは作らない。
   - evidence.md と diff.patch を超えてリポジトリを探索しない。§3 に無いことは「未確認事項」に書く。
   ```
4. **Perspective questions**: at most 4, phrased as questions to judge, not steps to execute.
5. **Output format**:
   ```text
   | Severity | Location | Finding | Evidence | Suggested fix |
   |---|---|---|---|---|
   | MUST | app/foo.ts:42 | … | … | … |
   ```
   Severity from the reviewer's own perspective (MUST / NITS / IMO; final severity is settled at
   integration). Evidence must cite the evidence.md section or `path:line` — no finding without it.
   No findings ⇒ `No findings` only.

Before dispatching, verify each prompt yourself: every `{{...}}` replaced, budget block present,
report path named. (There is no gate script anymore — the prompt is short enough to inspect.)

## Step 3 — Launch in parallel, wait once, collect

Start all reviewers of a wave in **one** tool call (subagent workflow, tmux, herdr — anything that
runs in parallel), wait once for all of them, then read `report-<p>.md` once per perspective.
Do not `sleep`-poll, do not prompt a reviewer twice. If a reviewer was dispatched without its report
path, recover the table from its output once yourself.

## Step 4 — Integrate into findings.md

1. **Merge duplicates.** Same finding in several reports = one entry.
2. **Verify the evidence for MUST.** Read the cited line yourself, exactly once; drop false positives.
   Do not extend this into a second review.
3. **Decide accept/reject.** MUST/NITS: to be filed. IMO: accept only if the effect is large.
   Keep rejected entries with their reasons.
4. **Harvest `Unconfirmed items`.** Every line a reviewer put there is a gap in the fact pack, not
   noise. Classify: covered in the pack / out of scope / a real pack gap (add it to §3 before the
   next wave) / a repository-wide gap (add it to the standing profile, see below) / a real finding
   that needs confirmation (carry it into findings.md with what would confirm it).
   When perspectives split severities over the same cause, settle the severity once and record the
   cause once — and check whether the fact that decided it belongs in §3 so the next wave
   does not repeat the arbitration.
5. **Write `/tmp/review-<label>/findings.md`.** Do not restate the reports; record decisions and
   pointers:
   ```markdown
   # {{TICKET}} review integration

   ## Accepted (to be filed)
   - [ ] MUST: `app/foo.ts:42` … (source: code, from `report-code.md`)
     - Destination: {{new / append to existing ticket uid}}

   ## Rejected (with reasons)
   - IMO: … — rejected because the quality difference is small (from `report-design.md`)

   ## Unconfirmed items
   - {{the line as the reviewer wrote it}} — {{classification}}

   ## Notes on the flow
   - {{budget overruns, pack gaps worth carrying to the next run}}
   ```

**Standing profiles.** A gap that every ticket in the repository would hit (framework behaviour,
library quirks) goes into `facts/<repository-name>.md` next to this skill — written once, reused by
every review. The skill supplies the mechanism only; profile content is per-repository data.

## Step 5 — File the tickets

Hand `findings.md` to the `file-ticket` skill. It groups accepted findings by concern, checks for
duplicates, `INSERT`s the tickets, and appends the filing result to findings.md. Do not file the
review itself ("this was hard to verify" is a pack gap, not a ticket), and never file a
"needs confirmation" item as a fix ticket — it stays a "decide the approach" ticket.

## Budget

| Item                    | Limit                        |
| ----------------------- | ---------------------------- |
| `evidence.md` size      | 15 KB / 400 lines            |
| Diff under one review   | 800 changed lines (split beyond) |
| Perspectives per wave   | 3                            |
| Tool calls per reviewer | 15 (stated in the prompt)    |
| Wall-clock              | ~10 min per wave             |

If a limit is exceeded, shrink the material or split into waves — do not lower the budget.

## Done conditions

- `diff.patch`, `evidence.md`, `report-<p>.md` for every perspective, and `findings.md` exist in
  `/tmp/review-<label>/`
- Every accepted finding is linked to a filed ticket or an append to an existing one
- Every `Unconfirmed items` line is classified (and real pack gaps written back into §3 or the
  standing profile)
- `git status` matches `status.before` — **there are no changes in the diff**
