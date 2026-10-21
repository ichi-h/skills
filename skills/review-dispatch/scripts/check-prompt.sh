#!/usr/bin/env bash
# Gate a review prompt before it is handed to a reviewer.
#
# The runaway reviews this guards against were not caused by the reviewers. They were caused by
# prompts that omitted the budget (so 15 tool calls was never a limit anyone knew about),
# enumerated items to verify (so a judgement became 22 verification jobs), and pointed at locations
# instead of pasting facts (so every lookup re-read the whole context). Each check below is one of
# those three, made mechanical.
#
# It also gates on the artifact directory itself. A prompt cannot be dispatched from a directory
# that carries DO_NOT_DISPATCH (written by collect-evidence.sh when the budget was exceeded), and
# the reviewer's output file must be named in the prompt so collection is a file read rather than a
# second round trip to the reviewer.
#
# Usage:
#   check-prompt.sh /tmp/review-t003/prompt-spec.md
#   check-prompt.sh /tmp/review-t003/prompt-*.md    # exit 1 if any prompt fails
#
# Exit 0: all prompts pass. Exit 1: at least one fails; do not dispatch.
#
# Override the report-file check with REVIEW_ALLOW_NO_REPORT=1 (e.g. when a harness genuinely
# cannot read a file back). The budget gate cannot be overridden — split the wave instead.

REPORT_REQUIRED=1
[ "${REVIEW_ALLOW_NO_REPORT:-0}" = "1" ] && REPORT_REQUIRED=0

set -uo pipefail

fail=0

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "FAIL $f: prompt not found" >&2
    fail=1
    continue
  fi

  errs=()

  # 0. The artifact directory must not be marked over budget. This is the mechanical half of the
  #    800-line / 15 KB limit: the collector's exit 3 is easy to step past, a refusal is not.
  dir="$(cd "$(dirname "$f")" && pwd)"
  if [ -e "$dir/DO_NOT_DISPATCH" ]; then
    errs+=("$dir/DO_NOT_DISPATCH exists (budget exceeded): split the wave, do not dispatch")
  fi

  # 1. Every placeholder substituted
  if grep -q '{{' "$f"; then
    errs+=("unsubstituted placeholder {{...}}")
  fi

  # 2. The budget block reached the prompt. A limit written only in the skill file moves nothing.
  if ! grep -qE 'ツール呼び出しは *[0-9]+ *回|at most *[0-9]+ *tool' "$f"; then
    errs+=("no tool-call budget (e.g. 'ツール呼び出しは 15 回まで')")
  fi

  # 3. The escape hatch exists, so hitting the budget is not a failure.
  if ! grep -qE '未確認事項|Unconfirmed items' "$f"; then
    errs+=("no '未確認事項 / Unconfirmed items' escape hatch")
  fi

  # 4. Probing is banned by name, not in the abstract.
  if ! grep -qE 'node -e|python -c|インタプリタ|interpreter|プローブ|probe' "$f"; then
    errs+=("interpreter/probe ban not stated")
  fi

  # 5. The evidence file is named as the sole input, and re-exploration beyond it is forbidden.
  if ! grep -qE 'evidence\.md|EVIDENCE' "$f"; then
    errs+=("evidence.md not named as the input")
  fi

  # 5b. The reviewer writes its table to a named file, and that file is inside the artifact
  #     directory. Measured failure: the prompt banned file creation, the harness could only read
  #     the agent's pane (thinking and table borders included), and the orchestrator then woke every
  #     reviewer a second time to have it write a file — 2 extra round trips per reviewer.
  if [ "$REPORT_REQUIRED" -eq 1 ]; then
    if ! grep -qE 'report-[a-z0-9_-]+\.md' "$f"; then
      errs+=("no report-<perspective>.md path in the prompt (output must be written to a file)")
    fi
    # The carve-out has to sit with the ban, not elsewhere in the prompt: a prompt can mention the
    # artifact directory in passing and still prohibit every file write, which is the original
    # defect. Look at the carve-out line plus its neighbours.
    if ! grep -B2 -A2 -E '成果物ディレクトリ|artifact directory|それ以外のファイル|他のファイル|other files|outside the artifact' "$f" |
      grep -qE 'report-[a-z0-9_-]+\.md'; then
      errs+=("prohibition does not carve out the report file (reviewer cannot write it)")
    fi
  fi

  # 6. Enumerated verification demands — exploration seeds. A checklist is a judgement, so more
  #    than four asks means the prompt became a work order. This used to warn; measured runs still
  #    shipped a 7-item checklist, so it now fails.
  seeds="$(grep -cE 'それぞれ|ずつ|1 つずつ|each of|one by one|すべて確認|confirm that' "$f" || true)"
  if [ "$seeds" -gt 4 ]; then
    errs+=("${seeds} lines look like 'verify each X' demands (limit 4); drop enumerated items")
  fi

  # 6b. The reviewer must be told which arena its severity belongs to, otherwise three perspectives
  #     grade the same cause MUST / NITS / IMO and the integration pays for the arbitration.
  if grep -qE '^## 観点|^## Perspective' "$f" && ! grep -qE '自分の観点|own perspective' "$f"; then
    errs+=("severity is not scoped to the reviewer's own perspective (add the one line)")
  fi

  # 7. Line-range references. Every one of them is a file the reviewer will open, which is exactly
  #    the exploration the fact pack exists to remove.
  tool_marks="$(grep -cE ':[0-9]+-[0-9]+' "$f" || true)"
  if [ "$tool_marks" -gt 8 ]; then
    errs+=("${tool_marks} line-range references (limit 8); cite only the ones that decide the review")
  fi

  # Report every failing check at once. Failing on the first one meant fixing and rerunning the gate
  # for each rule in turn, which is how a gate gets bypassed out of fatigue.
  if [ "${#errs[@]}" -gt 0 ]; then
    echo "FAIL $f" >&2
    for e in "${errs[@]}"; do
      echo "  - $e" >&2
    done
    fail=1
    continue
  fi

  echo "OK   $f"
done

exit "$fail"
