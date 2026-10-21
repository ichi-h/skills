#!/usr/bin/env bash
# Self-test for check-prompt.sh. Every gate rule gets one fixture that must pass and one that must
# fail, so a rule that stops firing is caught here instead of in a real review.
#
# Usage: scripts/self-test.sh     # exit 0 = all rules behave as documented

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$SCRIPT_DIR/check-prompt.sh"
TEMPLATE="$SCRIPT_DIR/../templates/prompt.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0

render() { # render <out> <perspective>
  sed -e "s|{{PERSPECTIVE}}|$2|g" \
      -e 's|{{TICKET}}|t001|g' \
      -e "s|{{EVIDENCE}}|$WORK/evidence.md|g" \
      -e "s|{{DIFF}}|$WORK/diff.patch|g" \
      -e "s|{{FILES}}|$WORK/files|g" \
      -e "s|{{REPORT}}|$WORK/report-$2.md|g" \
      -e 's|{{CHECKLIST}}|- 失敗は部分失敗に畳まれるか|' \
      "$TEMPLATE" >"$1"
}

expect() { # expect <pass|fail> <label> <prompt-file>
  want="$1"; label="$2"; file="$3"
  if "$GATE" "$file" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" != "$want" ]; then
    echo "FAIL [$label] expected $want, got $got" >&2
    fail=1
  else
    echo "ok   [$label] $got"
  fi
}

# Baseline: the template, fully substituted, must pass.
render "$WORK/prompt-code.md" code
expect pass "template renders and passes" "$WORK/prompt-code.md"

# Placeholder left behind.
sed 's|t001|{{TICKET}}|' "$WORK/prompt-code.md" >"$WORK/ph.md"
expect fail "unsubstituted placeholder" "$WORK/ph.md"

# Report path missing.
sed "s|report-code.md|notes.md|" "$WORK/prompt-code.md" >"$WORK/noreport.md"
expect fail "no report path" "$WORK/noreport.md"

# Prohibition that does not carve out the artifact directory.
sed 's|それ以外のファイル|何も|' "$WORK/prompt-code.md" >"$WORK/nocarve.md"
expect fail "no artifact carve-out" "$WORK/nocarve.md"

# Severity not scoped to the reviewer's own perspective.
sed 's|重大度は自分の観点から見た影響で付ける。||' "$WORK/prompt-code.md" >"$WORK/nosev.md"
expect fail "unscoped severity" "$WORK/nosev.md"

# Budget missing.
sed 's|ツール呼び出しは 15 回まで|回数制限なし|' "$WORK/prompt-code.md" >"$WORK/nobudget.md"
expect fail "no budget" "$WORK/nobudget.md"

# Over-budget marker next to the prompt.
touch "$WORK/DO_NOT_DISPATCH"
expect fail "DO_NOT_DISPATCH blocks dispatch" "$WORK/prompt-code.md"
rm -f "$WORK/DO_NOT_DISPATCH"
expect pass "DO_NOT_DISPATCH removed" "$WORK/prompt-code.md"

# Missing file.
expect fail "missing prompt file" "$WORK/does-not-exist.md"

echo
if [ "$fail" -ne 0 ]; then
  echo "self-test FAILED" >&2
  exit 1
fi
echo "self-test passed"
