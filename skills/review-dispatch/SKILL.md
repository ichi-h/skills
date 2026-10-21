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
   The template already carries the budget block, the prohibitions, and the output format, so the
   parts below are what you have to supply — the budget block is not optional:

   ```text
   ## 予算 / Budget
   - ツール呼び出しは 15 回まで。超えそうなら打ち切って、残りを「未確認事項」に 1 行で書け。
   - 全体 60 行以内。表の後に書けるのは「未確認事項:」だけ（最大 3 行）。
   - 目安 8 分。判断は evidence.md の中で完結させる。

   ## 禁止 / Prohibited
   - evidence.md の「3. Verified facts」を再検証しない。§3.1 が報告しているコマンドは再実行しない。
   - インタプリタ・プローブを走らせない（node -e / python -c / tsx / sqlite3 / テストランナー）。
   - ファイルを作成・編集・削除しない（作業ツリー内の一時ファイルも含む）。
   - evidence.md とリポジトリの再探索をしない。§3 に無いことは「未確認事項」に書く。
   ```

   Then the perspective itself:

   - The target ({{TICKET}}) and the path to evidence.md ({{EVIDENCE}})
   - The perspective-specific checklist — **at most 4 items**, phrased as questions to judge, not
     as steps to execute. No enumerated line numbers, no lists of default values, no
     "confirm that X really blocks Y" — those are exploration seeds.
   - The range of files that may be read (evidence.md only; evidence does not cover it, so anything
     else goes under `Unconfirmed items`)
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
     (at most 3 lines).

   Before dispatching, gate the prompts. The script fails on an unsubstituted placeholder, a missing
   budget, a missing escape hatch, an absent probe ban, and a missing evidence path; it warns when
   the checklist has turned into an enumerated work order:

   ```bash
   SKILL_DIR=<this skill's directory>
   "$SKILL_DIR/scripts/check-prompt.sh" /tmp/review-<label>/prompt-*.md   # exit 1 = do not dispatch
   ```

   Fix what it reports rather than dispatching around it.

3. **Launch in parallel.** Start as many reviewers as there are perspectives, **in a single call**.
   When they finish, save the results (the result files from the completion notifications) to
   `/tmp/review-<label>/report-<perspective>.md`.

   Wait for all of them in one call, not one by one:

   ```bash
   # herdr: the wait takes several targets; a per-reviewer wait blocks on the slower one
   # while the others sit finished and uncollected
   herdr agent wait rev-code rev-spec rev-tests --timeout 900000
   ```

   Same with subagents: one `subagent` workflow call with one child per perspective, or a single
   wait for the batch. **Do not `sleep` and poll**, and do not read a reviewer's pane while it is
   still `working`.

4. **Confirm collection.** Done once the reports for all perspectives are in. Do not judge the content.

## Budget

- Tool calls per reviewer: at most 15 — and this number goes into the prompt, not just here
- Output per reviewer: at most 60 lines
- Wall-clock for the whole review: 10 minutes (wait cap per reviewer: 15 minutes)
- Total tool calls for a 3-perspective wave: 45. A wave that produced more than that produced
  exploration, not review. Diagnose in this order, and do not raise the budget:

1. **Was the budget in the prompt?** If not, that is the cause; fix the prompt.
2. **Is the fact pack over 60 KB?** Then step 1 of `review-prepare` failed, not the reviewer.
3. **Did the checklist enumerate items?** More than 4 judgement questions means it became a
   work order.
4. **Did it need material the pack lacked?** That is a fact pack gap — record it, feed it back into
   `evidence.md` for the next run.
5. Only then consider the model or `thinking`, and only within the table above.

A reviewer that hit the 15-call cap and answered from the pack is a success, not a truncation.

## Done conditions

- `report-<perspective>.md` for every perspective exists in `/tmp/review-<label>/`
- **There are no changes in the diff**
