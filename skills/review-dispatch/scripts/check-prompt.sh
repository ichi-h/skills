#!/usr/bin/env bash
# Gate a review prompt before it is handed to a reviewer.
#
# The runaway reviews this guards against were not caused by the reviewers. They were caused by
# prompts that omitted the budget (so 15 tool calls was never a limit anyone knew about),
# enumerated items to verify (so a judgement became 22 verification jobs), and pointed at locations
# instead of pasting facts (so every lookup re-read the whole context). Each check below is one of
# those three, made mechanical.
#
# Usage:
#   check-prompt.sh /tmp/review-t003/prompt-spec.md
#   check-prompt.sh /tmp/review-t003/prompt-*.md    # exit 1 if any prompt fails
#
# Exit 0: all prompts pass. Exit 1: at least one fails; do not dispatch.

set -uo pipefail

fail=0

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "FAIL $f: prompt not found" >&2
    fail=1
    continue
  fi

  errs=()

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

  if [ "${#errs[@]}" -gt 0 ]; then
    echo "FAIL $f" >&2
    for e in "${errs[@]}"; do
      echo "  - $e" >&2
    done
    fail=1
    continue
  fi

  # 6. Advisory: count enumerated verification demands — exploration seeds.
  #    Warn rather than fail, because a checklist can legitimately use a number.
  seeds="$(grep -cE 'それぞれ|ずつ|1 つずつ|each of|one by one|すべて確認|confirm that' "$f" || true)"
  if [ "$seeds" -gt 2 ]; then
    echo "WARN $f: ${seeds} lines look like 'verify each X' demands. A perspective is a judgement," >&2
    echo "     not a work order. Keep the checklist to <=4 questions and drop enumerated items." >&2
  fi

  tool_marks="$(grep -cE ':[0-9]+-[0-9]+' "$f" || true)"
  if [ "$tool_marks" -gt 8 ]; then
    echo "WARN $f: ${tool_marks} line-range references. Each one is a file the reviewer will open." >&2
    echo "     Cite only the ones that decide the review." >&2
  fi

  echo "OK   $f"
done

exit "$fail"
