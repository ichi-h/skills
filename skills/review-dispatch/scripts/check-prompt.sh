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

  # 6. Enumerated verification demands — exploration seeds. A checklist is a judgement, so more
  #    than four asks means the prompt became a work order. This used to warn; measured runs still
  #    shipped a 7-item checklist, so it now fails.
  seeds="$(grep -cE 'それぞれ|ずつ|1 つずつ|each of|one by one|すべて確認|confirm that' "$f" || true)"
  if [ "$seeds" -gt 4 ]; then
    errs+=("${seeds} lines look like 'verify each X' demands (limit 4); drop enumerated items")
  fi

  # 7. Line-range references. Every one of them is a file the reviewer will open, which is exactly
  #    the exploration the fact pack exists to remove.
  tool_marks="$(grep -cE ':[0-9]+-[0-9]+' "$f" || true)"
  if [ "$tool_marks" -gt 8 ]; then
    errs+=("${tool_marks} line-range references (limit 8); cite only the ones that decide the review")
  fi

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
