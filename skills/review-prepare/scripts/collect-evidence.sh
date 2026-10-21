#!/usr/bin/env bash
# Fact gathering before review. Collects the diff, the full text of changed files, and the verification log into evidence.md.
#
# Each fact appears exactly once: new files are inlined with line numbers (2.1), modified files
# contribute only their hunks (2.2), and the complete text stays on disk under <out>/files/ (2.3).
# Do not duplicate both forms.
#
# Usage:
#   collect-evidence.sh <base-ref> [output-directory] [-- "<verification command>" ...]
#
# Examples:
#   collect-evidence.sh origin/main /tmp/review-tk01
#   collect-evidence.sh origin/main /tmp/review-tk01 -- "bun run typecheck" "bun test"
#   REVIEW_VERIFY=$'bun run typecheck\nbun test' collect-evidence.sh origin/main /tmp/review-tk01
#
# Verification commands are one command per argument. Pass several after `--`.
# A second or later `--` is rejected (being interpreted as a command name would cause an accident).
#
# Output:
#   <out>/evidence.md   Skeleton (the "verified facts" section is filled in by a human)
#   <out>/diff.patch    Raw diff
#   <out>/files/        Full text of changed files
#   <out>/check.log     Log of verification commands (full text)
#
# Notes:
#   - This script only gathers facts; it makes no judgements.
#     The orchestrator must fill in the "Verified facts" section.
#   - Verification commands differ per project, so they are not hardcoded here.
#     If none are given, the log section is generated empty (this is not a failure).
#   - Keep the output directory outside the repository. Pointing inside the repository
#     breaks the review's done condition ("git status does not change") by yourself.
#   - Untracked (??) files appear in neither the diff nor the full text. Run `git add -N` first.

set -euo pipefail

usage() {
  sed -n '/^# Usage:/,/^# Output:/p' "$0" | sed 's/^# \{0,1\}//'
}

if [ $# -lt 1 ]; then
  usage >&2
  exit 2
fi

BASE="$1"; shift

# If the second argument is not --, treat it as the output directory
if [ $# -gt 0 ] && [ "$1" != "--" ]; then
  OUT="$1"; shift
else
  OUT="/tmp/review-$(date +%Y%m%d-%H%M%S)"
fi

if [ -z "$OUT" ]; then
  echo "error: output directory is empty" >&2
  usage >&2
  exit 2
fi

if [ $# -gt 0 ]; then
  [ "$1" = "--" ] || { echo "error: unexpected argument: $1" >&2; usage >&2; exit 2; }
  shift
fi

VERIFY_CMDS=("$@")
for cmd in "${VERIFY_CMDS[@]+"${VERIFY_CMDS[@]}"}"; do
  if [ "$cmd" = "--" ]; then
    echo "error: verification command contains '--'. Pass one command per argument" >&2
    usage >&2
    exit 2
  fi
done

# Make the output path absolute (resolve before cd, so a relative path does not land in the repo root)
abspath() {
  if command -v realpath >/dev/null 2>&1; then
    realpath -m -- "$1"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"
  else
    case "$1" in
      /*) printf '%s\n' "$1" ;;
      *)  printf '%s\n' "$(pwd)/$1" ;;
    esac
  fi
}
OUT="$(abspath "$OUT")"

REPO_ROOT="$(git rev-parse --show-toplevel)"

case "$OUT/" in
  "$REPO_ROOT"/*)
    echo "error: output directory is inside the repository ($OUT). Reviews must not dirty the working tree; specify a path under /tmp" >&2
    exit 2
    ;;
esac

cd "$REPO_ROOT"

HEAD_REF="$(git rev-parse --short HEAD)"
# The real comparison point of a three-dot diff is the merge-base. The base name alone is not traceable, so keep the sha too
BASE_SHA="$(git merge-base "$BASE" HEAD)"
BASE_SHA_SHORT="$(git rev-parse --short "$BASE_SHA")"

# Remove leftovers from a previous run (prevents stale full texts from mixing in when rerunning with a different base)
rm -rf "$OUT/files"
mkdir -p "$OUT/files"

# By default git quotes non-ASCII paths in "..." form. Disable that, and read with
# -z (NUL separated) so that paths containing tabs or newlines do not break.
GIT_DIFF=(git -c core.quotePath=false diff --no-color)

STATUSES=()   # status of each line (for display)
PATHS=()      # path for display (new path for renames)
TARGETS=()    # paths to copy

collect() {
  # collect <diff arguments...>
  local entries=() i=0 st old new
  mapfile -d '' -t entries < <("${GIT_DIFF[@]}" --name-status -z "$@")
  while [ "$i" -lt "${#entries[@]}" ]; do
    st="${entries[$i]}"; i=$((i + 1))
    case "$st" in
      R*|C*)
        old="${entries[$i]}"; new="${entries[$i + 1]}"; i=$((i + 2))
        STATUSES+=("$st"); PATHS+=("$new"); TARGETS+=("$new")
        ;;
      *)
        new="${entries[$i]}"; i=$((i + 1))
        STATUSES+=("$st"); PATHS+=("$new")
        # Deleted files have no full text
        case "$st" in D*) ;; *) TARGETS+=("$new") ;; esac
        ;;
    esac
  done
}

DIFF_FILE="$OUT/diff.patch"
"${GIT_DIFF[@]}" "$BASE...HEAD" >"$DIFF_FILE"
collect "$BASE...HEAD"

# Also pick up unstaged changes (prevents missing changes when the working tree has uncommitted work).
# Reflect them not only by appending to the diff but also in name-status. Doing only one leaves
# "files that appear in the diff but have no full text".
UNCLEAN=0
if ! git diff --quiet || ! git diff --cached --quiet; then
  UNCLEAN=1
  git -c core.quotePath=false diff --no-color >>"$DIFF_FILE"
  git -c core.quotePath=false diff --no-color --cached >>"$DIFF_FILE"
  collect            # unstaged working tree changes
  collect --cached   # staged changes
  echo "WARN: uncommitted changes were included in the diff. Committing before review is recommended" >&2
fi

# When the same path has multiple statuses (e.g. an unstaged addition yields two lines, A and M),
# collapse them into the stronger meaning. Turning A into M would hide the "new file" fact.
_merge_status() {
  local a="$1" b="$2"
  case "$a$b" in
    *A*) echo 'A' ;;
    *D*) echo 'D' ;;
    *)   case "$a" in R*|C*) echo "$a" ;; *) echo "$b" ;; esac ;;
  esac
}

# Prevent the same path from appearing twice, once as committed and once as uncommitted.
# STATUSES and PATHS correspond by the same index, so thin them out together.
# Paths may contain newlines or tabs, so use an associative array instead of joining with a separator.
_dedupe_by_path() {
  local i p
  local -a path_order=() new_path=()
  local -A merged=()
  for i in "${!PATHS[@]}"; do
    p="${PATHS[$i]}"
    if [ -z "${merged[$p]+set}" ]; then
      merged[$p]="${STATUSES[$i]}"
      path_order+=("$p")
    else
      merged[$p]="$(_merge_status "${merged[$p]}" "${STATUSES[$i]}")"
    fi
  done

  local -a new_status=()
  for p in "${path_order[@]+"${path_order[@]}"}"; do
    new_path+=("$p")
    new_status+=("${merged[$p]}")
  done
  PATHS=("${new_path[@]+"${new_path[@]}"}")
  STATUSES=("${new_status[@]+"${new_status[@]}"}")

  local -a new_targets=()
  local -A seen_target=()
  local t
  for t in "${TARGETS[@]+"${TARGETS[@]}"}"; do
    [ -n "${seen_target[$t]+set}" ] && continue
    seen_target[$t]=1
    new_targets+=("$t")
  done
  TARGETS=("${new_targets[@]+"${new_targets[@]}"}")
}
_dedupe_by_path

# Escape so that one line stays one entry even if a path contains tabs, newlines, or backslashes
# (used when reading with -z. The human-readable listing has this form)
esc_path() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

: >"$OUT/name-status.txt"
for idx in "${!PATHS[@]}"; do
  printf '%s\t%s\n' "${STATUSES[$idx]}" "$(esc_path "${PATHS[$idx]}")" >>"$OUT/name-status.txt"
done

# To keep counts consistent with diff.patch, also record the actual numbers including uncommitted changes
{
  echo "Committed (${BASE}...HEAD): $(git diff --shortstat "${BASE}...HEAD")"
  if [ "$UNCLEAN" -eq 1 ]; then
    UNCLEAN_STAT="$({
      git diff --shortstat
      git diff --shortstat --cached
    } | sed 's/^ *//' | sed '/^$/d')"
    if [ -n "$UNCLEAN_STAT" ]; then
      echo "Uncommitted (tracked):"
      printf '%s\n' "$UNCLEAN_STAT" | sed 's/^/    /'
    fi
  fi
} >"$OUT/shortstat.txt"

# Untracked files appear in neither the diff, name-status, nor full text.
# Silently dropping them causes "there are no changes" to be misread, so report the count.
UNTRACKED=()
mapfile -d '' -t UNTRACKED < <(git ls-files --others --exclude-standard -z)
UNTRACKED_COUNT="${#UNTRACKED[@]}"

# Save the full text of each changed file (skip deleted files)
copied=0
for target in "${TARGETS[@]+"${TARGETS[@]}"}"; do
  [ -f "./$target" ] || continue
  # Copy preserving the directory structure (renaming files would cause path collisions)
  dest="$OUT/files/$target"
  mkdir -p "$(dirname "$dest")"
  # Without `--`, cp exits abnormally on paths starting with `-`, and set -e stops everything
  cp -- "./$target" "$dest"
  copied=$((copied + 1))
done

# Verification log (continue even if it fails)
CHECK_LOG="$OUT/check.log"
: >"$CHECK_LOG"
LOG_LIMIT=200

run_cmd() {
  echo "\$ $*"
  # Run through a shell so that specifications including pipes or redirects are accepted
  bash -c "$*" 2>&1 || echo "(exit != 0)"
  echo
}

if [ "${#VERIFY_CMDS[@]}" -gt 0 ]; then
  for cmd in "${VERIFY_CMDS[@]}"; do
    run_cmd "$cmd" >>"$CHECK_LOG"
  done
elif [ -n "${REVIEW_VERIFY:-}" ]; then
  # REVIEW_VERIFY accepts multiple commands separated by newlines
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    run_cmd "$cmd" >>"$CHECK_LOG"
  done <<<"$REVIEW_VERIFY"
else
  echo "(no verification commands given. Pass them after -- and rerun if needed)" >>"$CHECK_LOG"
fi

LOG_LINES="$(wc -l <"$CHECK_LOG")"
if [ "$LOG_LINES" -gt "$LOG_LIMIT" ]; then
  LOG_BODY="$(tail -n "$LOG_LIMIT" "$CHECK_LOG")"
  LOG_NOTE="... (omitted the first $((LOG_LINES - LOG_LIMIT)) lines. Full log: ${CHECK_LOG})"
else
  LOG_BODY="$(cat "$CHECK_LOG")"
  LOG_NOTE=""
fi

TICKET="$(basename "$OUT" | sed 's/^review-//')"

status_label() {
  case "$1" in
    A*) echo "new" ;;
    M*) echo "modified" ;;
    D*) echo "deleted" ;;
    R*) echo "renamed" ;;
    C*) echo "copied" ;;
    *)  echo "$1" ;;
  esac
}

{
  echo "# ${TICKET} review target evidence"
  echo
  echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "base: ${BASE} (merge-base ${BASE_SHA_SHORT})    head: ${HEAD_REF}"
  echo "Working directory: ${REPO_ROOT}"
  echo "Artifact directory: ${OUT}"
  if [ "$UNCLEAN" -eq 1 ]; then
    echo
    echo "**WARN: uncommitted changes are included in the diff.**"
  fi
  if [ "$UNTRACKED_COUNT" -gt 0 ]; then
    echo
    echo "**WARN: there are ${UNTRACKED_COUNT} untracked files. They are included in neither the diff nor the full text.**"
    echo "(To include them in scope, run \`git add -N <path>\` and rerun)"
    echo
    for f in "${UNTRACKED[@]}"; do
      echo "- \`$(esc_path "$f")\`"
    done
  fi
  echo
  echo "## 1. Ticket / acceptance criteria"
  echo
  echo "<!-- TODO: transcribe the requirements and the ticket's acceptance criteria with file:line -->"
  echo
  echo "- Target ticket: <!-- TODO: the task-management uid and title. If absent from the DB, \"outside the DB (PR / branch only)\" -->"
  echo "- Acceptance criteria:"
  echo "  - <!-- TODO: criterion — evidence: docs/requirements.md:line / the ticket uid's description -->"
  echo
  echo "## 2. Diff"
  echo
  cat "$OUT/shortstat.txt"
  echo
  echo "Changed files:"
  echo
  echo '| File | Kind |'
  echo '|---|---|'
  for idx in "${!PATHS[@]}"; do
    # Replace characters that would break the table in the display only (the real path is in name-status.txt)
    cell="$(esc_path "${PATHS[$idx]}" | sed 's/|/\\|/g' | tr -d '\r')"
    echo "| ${cell} | $(status_label "${STATUSES[$idx]}") |"
  done
  echo
  echo 'Nothing here is repeated elsewhere in this file. Every fact appears exactly once: new'
  echo 'files as line-numbered text, modified files as hunks. The raw patch is on disk at'
  echo "\`${DIFF_FILE}\` if you need the unbroken form."
  echo
  echo '### 2.1 New files (full text, line-numbered)'
  echo
  echo 'These files did not exist at the base, so the full text is the change. Line numbers are'
  echo 'the real ones — cite them directly instead of opening the file.'
  echo
  for idx in "${!PATHS[@]}"; do
    case "${STATUSES[$idx]}" in A*) ;; *) continue ;; esac
    path="${PATHS[$idx]}"
    f="$OUT/files/$path"
    if [ ! -f "$f" ]; then
      echo "#### $(esc_path "$path")"
      echo
      echo '- (binary or unreadable; not inlined)'
      echo
      continue
    fi
    echo "#### $(esc_path "$path")"
    echo
    # Use a fence longer than the longest run of backticks so that a ``` inside the content
    # does not close the fence early
    fence="$(python3 - "$f" <<'PY'
import re, sys
with open(sys.argv[1], 'r', encoding='utf-8', errors='replace') as fh:
    s = fh.read()
longest = max((len(m) for m in re.findall(r'`+', s)), default=0)
print('`' * max(3, longest + 1))
PY
)"
    echo "${fence}"
    awk '{ printf "%6d| %s\n", NR, $0 }' "$f"
    echo "${fence}"
    echo
  done
  echo '### 2.2 Modified files (changed hunks only)'
  echo
  echo 'Full text is deliberately not included: pasting a 400-line document because 8 lines of it'
  echo 'changed is what made reviewers read for 27 minutes. The `@@ -a,b +c,d @@` header carries'
  echo 'the new side line numbers, so `path:line` in a finding can be derived from it.'
  echo
  echo 'When a finding needs lines outside these hunks, cite only what is visible here. Do not'
  echo 'send the reviewer to the repository for it.'
  echo
  for idx in "${!PATHS[@]}"; do
    case "${STATUSES[$idx]}" in A*) continue ;; esac
    path="${PATHS[$idx]}"
    echo "#### $(esc_path "$path")"
    echo
    echo '```diff'
    {
      git -c core.quotePath=false diff --no-color "$BASE...HEAD" -- "$path"
      if [ "$UNCLEAN" -eq 1 ]; then
        git -c core.quotePath=false diff --no-color -- "$path"
        git -c core.quotePath=false diff --no-color --cached -- "$path"
      fi
    } | sed '/^$/d'
    echo '```'
    echo
  done
  echo '### 2.3 Full text on disk'
  echo
  echo "Not inlined. \`${OUT}/files/\` holds the complete text of every changed file (${copied} files)."
  echo
  echo '## 3. Verified facts'
  echo
  echo '<!-- TODO: reviewers must not re-verify this section. Always attach file:line or the relevant line of the run log -->'
  echo
  echo '### 3.1 Things confirmed by running them'
  echo
  if [ -n "$LOG_NOTE" ]; then
    echo "\`${LOG_NOTE}\`"
    echo
  fi
  echo '```text'
  echo "$LOG_BODY"
  echo '```'
  echo
  echo "- Full verification log: \`${CHECK_LOG}\`"
  echo '- <!-- TODO: facts readable from the log above -->'
  echo
  echo '### 3.2 Framework / dependency behaviour (points where judgements diverge)'
  echo
  echo '- <!-- TODO: e.g. library X behaves as Y. Evidence: node_modules/pkg/file:line -->'
  echo
  echo '### 3.3 Relevant parts of the spec'
  echo
  echo 'Quote the requirement text itself, not just its location. A bare `docs/requirements.md:117-133`'
  echo 'sends every reviewer into the repository to read it, and each of them pays a tool call and a'
  echo 'full context re-read for the same four lines. Paste the sentences.'
  echo
  echo '- <!-- TODO: quote the requirement, then its source: docs/requirements.md:120-134 -->'
  echo
  echo '### 3.4 Out of scope / known gaps'
  echo
  echo '- <!-- TODO: out of scope for this review / pre-existing gaps. Name the ticket or the reason. -->'
  echo
  echo '## 4. Notes for the review'
  echo
  echo "- Everything needed for the judgement is in this file. Anything not here is outside this review's scope."
  echo '- Never re-verify section 3, and never re-run a command that section 3.1 reports: its result is already the fact.'
  echo '- Do not run interpreters or probes (node -e, python -c, tsx, sqlite3, test runners) to settle a question.'
  echo '- Do not create, edit, or delete any file, including scratch files in the work tree.'
  echo '- At most 3 lines under `Unconfirmed items`, and only for facts that genuinely depend on the environment.'
  echo '- Fixing findings is prohibited. Filing tickets is done by the orchestrator.'
} >"$OUT/evidence.md"

EVIDENCE_BYTES="$(wc -c <"$OUT/evidence.md")"
EVIDENCE_LINES="$(wc -l <"$OUT/evidence.md")"

# Budget: 60 KB / 1,200 lines (see the review-to-ticket skill). Overshooting is silent otherwise,
# because an oversized fact pack still produces a report — just 20 minutes later.
BUDGET_BYTES=61440
BUDGET_LINES=1200

if [ "$EVIDENCE_BYTES" -gt "$BUDGET_BYTES" ] || [ "$EVIDENCE_LINES" -gt "$BUDGET_LINES" ]; then
  {
    echo
    echo "**WARN: evidence.md is ${EVIDENCE_BYTES} bytes / ${EVIDENCE_LINES} lines, over the budget"
    echo "(60 KB / 1,200 lines).** Reviewers pay for every line with a full context re-read."
    echo 'Split the review into two waves (see the review-prepare skill, step 1) or trim the material.'
    echo 'Do not lower the budget to fit the file.'
  } >>"$OUT/evidence.md"
  echo "WARN: evidence.md exceeds the budget (${EVIDENCE_BYTES} bytes / ${EVIDENCE_LINES} lines > 60 KB / 1,200 lines)" >&2
  echo "      Split the review or trim the material. Do not dispatch as is." >&2
fi

echo "Generated evidence: $OUT/evidence.md (${EVIDENCE_BYTES} bytes / ${EVIDENCE_LINES} lines, budget 60 KB / 1,200 lines)"
echo "  Full text of changed files: $copied -> $OUT/files/ (referenced, not inlined)"
echo "  Verification log: $CHECK_LOG (${LOG_LINES} lines)"
echo
echo "Next: fill in the TODOs of \"## 1\" and \"## 3\" in evidence.md, then hand it to the reviewers."
echo "      Section 3.3 must quote the requirement text, not only its location."
