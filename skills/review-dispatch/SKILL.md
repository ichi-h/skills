---
name: review-dispatch
description: A skill that delegates perspective-based reviews to agents in parallel and collects the findings tables. The orchestrator itself does not review.
---

# Review Dispatch Skill

**Delegate perspective-based reviews to agents in parallel** and collect the findings tables.

**The deliverable of this skill is the findings tables (report-<perspective>.md). Do not integrate or accept/reject. Do not change a single line of code.**

## Principles

- **The orchestrator does not review.** All judgements are made by reviewers (child agents).
- **Launch every perspective of a wave in parallel, in a single call.** Running them in sequence
  stacks up wall-clock. The delegation mechanism does not matter (subagent / tmux / herdr —
  anything that can start in parallel).
- **Wait in one call for all reviewers.** No `sleep` polling; wait for the completion notification
  (`--wait`). Waiting per reviewer blocks on the slowest while the finished ones sit uncollected.
  "One call" means one tool invocation that returns when all are settled — not "one wait command
  with several arguments". See step 3 for the per-harness form.
- **The reviewer writes its own report file.** The collection step is a read of
  `report-<perspective>.md`, not a second prompt. Do not instruct a reviewer to "now write the table
  to a file": the prompt already names the file, and a second round trip per reviewer costs more
  than the whole wave.
- **The budget goes into the prompt.** A number that is only written here moves nothing; the
  reviewer stops at a limit only if the text it receives says one.
- **A perspective is a judgement, not a work order.** A checklist of enumerated verification jobs
  turns the reviewer into an executor. Write what to look at, not how many things to check.

## Steps

1. **Choose perspectives.** Only those needed. At most 3 (if more, split into 2 waves).

   | Perspective  | Required when                                                     | thinking |
   | ------------ | ----------------------------------------------------------------- | -------- |
   | Code         | Always                                                            | medium   |
   | Security     | Touches authentication, authorization, external input, or secrets | high     |
   | Tests        | Tests are added or changed                                        | medium   |
   | Architecture | Touches aggregate boundaries, the domain layer, or public APIs    | high     |
   | Spec         | Requirements or acceptance criteria exist                         | medium   |

   Do not raise `thinking` "to be safe". The table's level is the level.

2. **Build the prompts.** One prompt per perspective. Start from `templates/prompt.md`, fill in
   every `{{...}}`, and save it to `/tmp/review-<label>/prompt-<perspective>.md`.
   `templates/prompt.md` already carries the budget block, the prohibitions, and the output format,
   so do not retype them — substitute the placeholders and supply the perspective checklist:

   | Placeholder     | Value                                                        |
   | --------------- | ------------------------------------------------------------ |
   | `{{PERSPECTIVE}}` | Code / Security / Tests / Architecture / Spec              |
   | `{{TICKET}}`      | the ticket uid                                             |
   | `{{EVIDENCE}}`    | `/tmp/review-<label>/evidence.md`                          |
   | `{{DIFF}}`        | `/tmp/review-<label>/diff.patch`                           |
   | `{{FILES}}`       | `/tmp/review-<label>/files`                                |
   | `{{REPORT}}`      | `/tmp/review-<label>/report-<perspective>.md`              |
   | `{{CHECKLIST}}`   | at most 4 judgement questions for the perspective          |

   The budget block is not optional; if you write the prompt from scratch anyway, it must contain this:

   ```text
   ## 予算 / Budget
   - ツール呼び出しは 15 回まで。超えそうなら打ち切って、残りを「未確認事項」に 1 行で書け。
   - 全体 60 行以内。表の後に書けるのは「未確認事項:」だけ（最大 3 行）。
   - 目安 8 分。判断は evidence.md の中で完結させる。

   ## 禁止 / Prohibited
   - evidence.md の「3. Verified facts」を再検証しない。§3.1 が報告しているコマンドは再実行しない。
   - インタプリタ・プローブを走らせない（node -e / python -c / tsx / sqlite3 / テストランナー）。
   - ファイルの作成・編集・削除は成果物ディレクトリの report-<perspective>.md 1 つだけ。
     それ以外のファイルは作らない（作業ツリー内の一時ファイルも含む）。
   - evidence.md とリポジトリの再探索をしない。§3 に無いことは「未確認事項」に書く。
   ```

   The prohibition used to ban file creation outright while the orchestrator asked for a file
   afterwards. The reviewer cannot both obey and deliver, and the collection step turned into a
   second prompt. Name the report file in the prompt (`{{REPORT}}` =
   `/tmp/review-<label>/report-<perspective>.md`) and carve it out of the prohibition;
   `check-prompt.sh` fails a prompt that lacks either.

   The `{{DIFF}}` and `{{FILES}}` substitutions matter even though the pack carries no diff: without
   them the reviewer guesses where a finding's line came from. The checklist is **at most 4 items**,
   phrased as questions to judge, not as steps to execute — no enumerated line numbers, no lists of
   default values, no "confirm that X really blocks Y"; those are exploration seeds.

   Severity is graded **from the reviewer's own perspective**. Three perspectives reporting the same
   cause as NITS / NITS / IMO is a perspective-design signal, not three findings: leave the final
   severity to the integration step instead of asking each reviewer to pre-arbitrate. The template
   carries the line; keep it.

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
     (at most 3 lines).

   Before dispatching, gate the prompts. The script fails on an unsubstituted placeholder, a missing
   budget, a missing escape hatch, an absent probe ban, a missing evidence path, a missing
   `report-<perspective>.md` path, a prohibition that does not carve out the artifact directory, an
   unscoped severity line, and on an adjacent `DO_NOT_DISPATCH` from `collect-evidence.sh`:

   ```bash
   SKILL_DIR=<this skill's directory>
   "$SKILL_DIR/scripts/check-prompt.sh" /tmp/review-<label>/prompt-*.md   # exit 1 = do not dispatch
   ```

   It reports every failing check at once. Fix what it reports rather than dispatching around it.
   The gate is what makes the 800-line / 15 KB budget real: the collector's exit 3 is a value a shell
   pipeline drops without noticing, while a prompt that the gate refuses cannot be launched at all.

   The gate's own rules are covered by `scripts/self-test.sh` (each rule gets a fixture that must
   pass and one that must fail). Run it after editing `check-prompt.sh`; a rule that silently stops
   firing is worse than no rule, because it looks like a check.

3. **Launch in parallel and wait once.** Start as many reviewers as there are perspectives in one
   tool call, and collect `report-<perspective>.md` when all of them settle.

   **herdr**: `agent wait` takes exactly one `<TARGET>` (`herdr agent wait rev-code rev-spec` is a
   usage error, `unexpected argument`). Bundle them in one shell invocation instead — the background
   `&` plus a single `wait` is the one call:

   ```bash
   # One tool call. Each `agent prompt --wait` returns when that reviewer settles; the shell `wait`
   # joins them. Name every reviewer: an unnamed pane (wS:pG) cannot be waited on at all.
   for p in code spec tests; do
     herdr agent prompt "rev-$p" "$(cat /tmp/review-<label>/prompt-$p.md)" --wait --timeout 900000 &
   done
   wait
   ```

   Confirm the names first; a pane that was never named cannot be collected:

   ```bash
   herdr agent list   # every reviewer must show a `name`
   ```

   **subagent**: one workflow call with one child per perspective, or one wait for the batch.

   **Do not `sleep` and poll.** Do not read a reviewer's pane while it is still `working`, and do
   not wake a finished reviewer a second time to ask for its table — it already wrote
   `report-<perspective>.md`.

4. **Collect.** Read `report-<perspective>.md` once per perspective. If a reviewer was dispatched
   without the report path (an older prompt), recover it with one `agent read <name> --source
   recent-unwrapped`, strip the pane decoration, and write the file yourself — once, not per
   reviewer as a second prompt. Done when every report is on disk. Do not judge the content.

## Budget

- Tool calls per reviewer: at most 15 — and this number goes into the prompt, not just here
- Output per reviewer: at most 60 lines
- Wall-clock for the whole review: 10 minutes (wait cap per reviewer: 15 minutes)
- Total tool calls for a 3-perspective wave: 45. A wave that produced more than that produced
  exploration, not review. Diagnose in this order, and do not raise the budget:

1. **Was the budget in the prompt?** If not, that is the cause; fix the prompt.
2. **Did the fact pack stay under 15 KB?** If not, step 1 of `review-prepare` failed, not the
   reviewer (the collector exits 3 on overrun, so an oversized pack means the exit code was ignored).
3. **Did the checklist enumerate items?** More than 4 judgement questions means it became a
   work order.
4. **Did each reviewer get more than one turn?** A second prompt to write the report, or an extra
   turn to answer a question the prompt failed to answer, re-sends the whole prompt and context.
   A measured wave paid two such round trips per reviewer; that cost more than the wave's own
   tool calls and produced nothing. Fix the prompt, not the reviewer.
5. **Did it need material the pack lacked?** That is a fact pack gap — record it, feed it back into
   `evidence.md` for the next run.
6. Only then consider the model or `thinking`, and only within the table above.

A reviewer that hit the 15-call cap and answered from the pack is a success, not a truncation.

## Done conditions

- `report-<perspective>.md` for every perspective exists in `/tmp/review-<label>/`
- Every reviewer was addressed by name for the whole wave (no unnamed-pane collection)
- Each report was written by its reviewer; no reviewer was prompted a second time to produce a file
- `scripts/check-prompt.sh` exited 0 on the dispatched prompts
- **There are no changes in the diff**
