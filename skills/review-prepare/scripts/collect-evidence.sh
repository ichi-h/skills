#!/usr/bin/env bash
# Fact gathering before review. Builds the judgement pack (evidence.md) and records
# the diff on disk.
#
# evidence.md holds only what a reviewer must judge from: the ticket and its
# acceptance criteria (§1) and the verified facts (§3). The diff itself is NOT
# inlined: it lives in one place, <out>/diff.patch, and the full text of changed
# files in <out>/files/. A reviewer reads the pack, then opens the patch only for
# the lines a finding cites. Inlining the diff here was 93% of the pack in measured
# runs (45.6 KB of 45.6 KB) and is what made reviewers re-read the whole context.
#
# Usage:
#   collect-evidence.sh <base-ref> [output-directory] [--ticket <uid>] [-- "<verification command>" ...]
#
# Examples:
#   collect-evidence.sh origin/main /tmp/review-tk01 --ticket t008
#   collect-evidence.sh origin/main /tmp/review-tk01 -- "bun run typecheck" "bun test"
#   collect-evidence.sh origin/main /tmp/review-tk01 --ticket t008 -- "npm run check"
#
# --ticket <uid> fills §1 from the task-management DB (.<username>/issues.db) when
# the file exists; without it, §1 keeps its TODO placeholders.
#
# Verification commands are one command per argument. Pass several after `--`.
# A second or later `--` is rejected (being interpreted as a command name would cause an accident).
#
# Output:
#   <out>/evidence.md   Judgement pack (§1 ticket / §2 inventory / §3 verified facts)
#   <out>/diff.patch    Raw diff (the only copy of the diff)
#   <out>/files/        Full text of changed files
#   <out>/check.log     Log of verification commands (full text)
#
# Notes:
#   - This script only gathers facts; it makes no judgements.
#     The orchestrator must fill in the "Verified facts" section.
#   - Lockfiles and build artefacts are excluded from the diff and the full text;
#     they are listed in §2 with the reason instead.
#   - Verification commands differ per project, so they are not hardcoded here.
#     If none are given, the log section is generated empty (this is not a failure).
#   - Keep the output directory outside the repository. Pointing inside the repository
#     breaks the review's done condition ("git status does not change") by yourself.
#   - Untracked (??) files appear in neither the diff nor the full text. Run `git add -N` first.
#
# Exit status:
#   0  evidence.md is within budget (15 KB / 400 lines) and the diff is within 800 changed lines
#   2  usage error
#   3  budget exceeded: the pack and the patch were written, but do not dispatch
#      (split the review into waves or trim the material; do not raise the budget)

set -euo pipefail

usage() {
  sed -n '/^# Usage:/,/^# Output:/p' "$0" | sed 's/^# \{0,1\}//'
}

if [ $# -lt 1 ]; then
  usage >&2
  exit 2
fi

BASE="$1"; shift

# If the second argument is not an option or --, treat it as the output directory
OUT=""
if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then
  OUT="$1"; shift
fi

TICKET_UID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ticket)
      [ $# -ge 2 ] || { echo "error: --ticket requires a uid" >&2; exit 2; }
      TICKET_UID="$2"; shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "error: unexpected argument: $1" >&2; usage >&2; exit 2
      ;;
  esac
done

VERIFY_CMDS=("$@")
for cmd in "${VERIFY_CMDS[@]+"${VERIFY_CMDS[@]}"}"; do
  if [ "$cmd" = "--" ]; then
    echo "error: verification command contains '--'. Pass one command per argument" >&2
    usage >&2
    exit 2
  fi
done

[ -n "$OUT" ] || OUT="/tmp/review-$(date +%Y%m%d-%H%M%S)"

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

# Files whose content never decides a review. Dropping them keeps the patch small
# and the reviewers' attention on what changed behaviour.
is_excluded() {
  case "$1" in
    *lock.json|*.lock|lock.json|package-lock.json|yarn.lock|pnpm-lock.yaml|bun.lock|Cargo.lock|poetry.lock|composer.lock|go.sum|*.lockb) return 0 ;;
    dist/*|*/dist/*|build/*|*/build/*|coverage/*|*/coverage/*|node_modules/*|*/node_modules/*) return 0 ;;
    *.min.js|*.min.css|*.map|*.snap|*.generated.*|*.g.dart|*.pb.go) return 0 ;;
  esac
  return 1
}

# Human-readable reason for the exclusion (used in §2 of the pack)
exclusion_reason() {
  case "$1" in
    *lock.json|*.lock|lock.json|package-lock.json|yarn.lock|pnpm-lock.yaml|bun.lock|Cargo.lock|poetry.lock|composer.lock|go.sum|*.lockb)
      echo "lockfile" ;;
    dist/*|*/dist/*|build/*|*/build/*|coverage/*|*/coverage/*|node_modules/*|*/node_modules/*)
      echo "build artefact" ;;
    *)
      echo "generated" ;;
  esac
}

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
: >"$DIFF_FILE"
collect "$BASE...HEAD"

# Also pick up unstaged changes (prevents missing changes when the working tree has uncommitted work).
UNCLEAN=0
if ! git diff --quiet || ! git diff --cached --quiet; then
  UNCLEAN=1
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

# Split paths into "kept" and "excluded" (lockfiles and build artefacts).
KEPT_PATHS=(); KEPT_STATUSES=(); EXCLUDED_PATHS=(); EXCLUDED_STATUSES=()
for idx in "${!PATHS[@]}"; do
  p="${PATHS[$idx]}"
  if is_excluded "$p"; then
    EXCLUDED_PATHS+=("$p"); EXCLUDED_STATUSES+=("${STATUSES[$idx]}")
  else
    KEPT_PATHS+=("$p"); KEPT_STATUSES+=("${STATUSES[$idx]}")
  fi
done
PATHS=("${KEPT_PATHS[@]+"${KEPT_PATHS[@]}"}")
STATUSES=("${KEPT_STATUSES[@]+"${KEPT_STATUSES[@]}"}")

# The patch keeps the exclusions out. Rebuild it from the kept paths so that the
# reviewer never pages through a 1,000-line lockfile hunk.
if [ "${#PATHS[@]}" -gt 0 ]; then
  # Build the argument list in chunks: `git diff -- a b c` (paths after one --)
  {
    printf '%s\0' "${PATHS[@]}"
  } >"$OUT/.kept-paths"
  mapfile -d '' -t KEPT_LIST <"$OUT/.kept-paths"
  "${GIT_DIFF[@]}" "$BASE...HEAD" -- "${KEPT_LIST[@]}" >"$DIFF_FILE"
  if [ "$UNCLEAN" -eq 1 ]; then
    git -c core.quotePath=false diff --no-color -- "${KEPT_LIST[@]}" >>"$DIFF_FILE"
    git -c core.quotePath=false diff --no-color --cached -- "${KEPT_LIST[@]}" >>"$DIFF_FILE"
  fi
  rm -f "$OUT/.kept-paths"
else
  : >"$DIFF_FILE"
fi

# Escape so that one line stays one entry even if a path contains tabs, newlines, or backslashes
esc_path() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

# Changed lines in the patch (+/-), excluding context and hunk headers.
DIFF_CHANGED_LINES="$(awk '/^(\+\+\+|---)/{next} /^[+-]/{n++} END{print n+0}' "$DIFF_FILE")"

: >"$OUT/name-status.txt"
for idx in "${!PATHS[@]}"; do
  printf '%s\t%s\n' "${STATUSES[$idx]}" "$(esc_path "${PATHS[$idx]}")" >>"$OUT/name-status.txt"
done

# Per-file line counts, used for the excluded-files lines in §2
declare -A NUMSTAT_ADD=() NUMSTAT_DEL=()
while IFS=$'\t' read -r a d p; do
  [ -n "${p:-}" ] || continue
  NUMSTAT_ADD["$p"]="${a:-0}"
  NUMSTAT_DEL["$p"]="${d:-0}"
done < <({
  git diff --numstat "$BASE...HEAD"
  if [ "$UNCLEAN" -eq 1 ]; then
    git diff --numstat
    git diff --numstat --cached
  fi
} | awk -F'\t' 'NF>=3 {k=$3; add[k]+=$1; del[k]+=$2} END{for (k in add) printf "%d\t%d\t%s\n", add[k], del[k], k}')

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

# Save the full text of each changed file (skip deleted files, skip excluded ones)
copied=0
for target in "${TARGETS[@]+"${TARGETS[@]}"}"; do
  is_excluded "$target" && continue
  [ -f "./$target" ] || continue
  dest="$OUT/files/$target"
  mkdir -p "$(dirname "$dest")"
  # Without `--`, cp exits abnormally on paths starting with `-`, and set -e stops everything
  cp -- "./$target" "$dest"
  copied=$((copied + 1))
done

# Verification log (continue even if it fails)
CHECK_LOG="$OUT/check.log"
: >"$CHECK_LOG"
LOG_LIMIT=120

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

# §1 from the task-management DB. A bare `docs/requirements.md:117-133` makes every
# reviewer open the file; the ticket text pasted here is a fact.
ticket_section() {
  local db=".$(whoami)/issues.db" row="" uid title state desc
  if [ -z "$TICKET_UID" ]; then
    echo "<!-- TODO: transcribe the requirements and the ticket's acceptance criteria -->"
    echo
    echo "- Target ticket: <!-- TODO: the task-management uid and title. If absent from the DB, \"outside the DB (PR / branch only)\" -->"
    echo "- Acceptance criteria:"
    echo "  - <!-- TODO: criterion — evidence: docs/requirements.md:line / the ticket uid's description -->"
    return
  fi

  if ! command -v sqlite3 >/dev/null 2>&1 || [ ! -f "$db" ]; then
    echo "<!-- TODO: ${db} is missing or sqlite3 is unavailable; fill this section by hand -->"
    echo
    echo "- Target ticket: \`${TICKET_UID}\`"
    return
  fi

  row="$(sqlite3 -separator $'\x1f' "$db" \
    "SELECT uid, title, state, description FROM tickets WHERE uid='${TICKET_UID}'" 2>/dev/null || true)"
  if [ -z "$row" ]; then
    echo "- Target ticket: \`${TICKET_UID}\` (not found in ${db})"
    return
  fi

  # Split on the unit separator only, so a description containing newlines survives intact.
  # (`read -r` alone stops at the first newline and silently truncated the ticket text.)
  uid="${row%%$'\x1f'*}"; row="${row#*$'\x1f'}"
  title="${row%%$'\x1f'*}"; row="${row#*$'\x1f'}"
  state="${row%%$'\x1f'*}"; desc="${row#*$'\x1f'}"

  echo "- Target ticket: \`${uid}\` — ${title} (state=${state})"
  echo "- Acceptance criteria (the ticket text itself; judge against this, not against the diff alone):"
  echo
  # Quote it as a block, and demote its own headings by one level: the ticket body starts with `##`,
  # which would otherwise become a sibling of §1 and break the pack's table of contents.
  printf '%s\n' "$desc" | sed -e 's/^\(#\{1,5\}\) /#\1 /' -e 's/^/  /'
  echo
  echo "- Tasks recorded for the ticket:"
  sqlite3 -separator ' | ' "$db" \
    "SELECT uid, state, title FROM tasks WHERE ticket_id=(SELECT id FROM tickets WHERE uid='${TICKET_UID}') ORDER BY id" \
    2>/dev/null | sed 's/^/  - /' || true
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
  ticket_section
  echo
  echo "## 2. Diff (on disk, not inlined)"
  echo
  cat "$OUT/shortstat.txt"
  echo
  echo "Changed lines in the kept patch: ${DIFF_CHANGED_LINES} (budget 800)"
  echo
  echo "**The diff is not repeated here.** Read \`${DIFF_FILE}\` for the patch and"
  echo "\`${OUT}/files/\` for the full text of changed files. Open only the lines a finding cites —"
  echo "reading the whole patch is a tool call and a full context re-read."
  echo
  echo "Changed files (kept):"
  echo
  if [ "${#PATHS[@]}" -eq 0 ]; then
    echo "- (none)"
  else
    echo '| File | Kind |'
    echo '|---|---|'
    for idx in "${!PATHS[@]}"; do
      cell="$(esc_path "${PATHS[$idx]}" | sed 's/|/\\|/g' | tr -d '\r')"
      echo "| ${cell} | $(status_label "${STATUSES[$idx]}") |"
    done
  fi
  if [ "${#EXCLUDED_PATHS[@]}" -gt 0 ]; then
    echo
    echo "Excluded from the patch and the full text (nothing to judge in them):"
    echo
    for idx in "${!EXCLUDED_PATHS[@]}"; do
      p="${EXCLUDED_PATHS[$idx]}"
      echo "- \`$(esc_path "$p")\` ($(status_label "${EXCLUDED_STATUSES[$idx]}"), +${NUMSTAT_ADD[$p]:-0}/-${NUMSTAT_DEL[$p]:-0}) — $(exclusion_reason "$p"); see \`package.json\` / the manifest for the actual change"
    done
  fi
  echo
  echo 'When a file is new, the patch carries it in full (every line is a `+` line), and the hunk'
  echo 'header `@@ -0,0 +1,N @@` gives the line numbers. There is no second copy of the diff anywhere.'
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
} >"$OUT/evidence.md"

EVIDENCE_BYTES="$(wc -c <"$OUT/evidence.md")"
EVIDENCE_LINES="$(wc -l <"$OUT/evidence.md")"

# Budget: 15 KB / 400 lines for the pack, 800 changed lines for the patch.
# Overshooting is silent otherwise, because an oversized pack still produces a report —
# just 20 minutes later, at three reviewers' expense.
BUDGET_BYTES=15360
BUDGET_LINES=400
DIFF_BUDGET=800
OVER=0

if [ "$EVIDENCE_BYTES" -gt "$BUDGET_BYTES" ] || [ "$EVIDENCE_LINES" -gt "$BUDGET_LINES" ]; then
  OVER=1
  {
    echo
    echo "**WARN: evidence.md is ${EVIDENCE_BYTES} bytes / ${EVIDENCE_LINES} lines, over the budget"
    echo "(15 KB / 400 lines).** Reviewers pay for every line with a full context re-read."
    echo 'Split the review into two waves (see the review-prepare skill, step 1) or trim the material.'
    echo 'Do not lower the budget to fit the file.'
  } >>"$OUT/evidence.md"
  echo "WARN: evidence.md exceeds the budget (${EVIDENCE_BYTES} bytes / ${EVIDENCE_LINES} lines > 15 KB / 400 lines)" >&2
fi

if [ "$DIFF_CHANGED_LINES" -gt "$DIFF_BUDGET" ]; then
  OVER=1
  echo "WARN: the patch has ${DIFF_CHANGED_LINES} changed lines, over the budget (800)." >&2
  echo "      Split the review into waves by concern (review-prepare, step 1)." >&2
fi

echo "Generated evidence: $OUT/evidence.md (${EVIDENCE_BYTES} bytes / ${EVIDENCE_LINES} lines, budget 15 KB / 400 lines)"
echo "  Full text of changed files: $copied -> $OUT/files/"
echo "  Patch: $DIFF_FILE (${DIFF_CHANGED_LINES} changed lines, budget 800)"
echo "  Verification log: $CHECK_LOG (${LOG_LINES} lines)"

if [ "$OVER" -eq 1 ]; then
  echo
  echo "DO NOT DISPATCH: the budget is exceeded. Split the review or trim the material." >&2
  echo "Next: fill in the TODOs of \"## 3\" in evidence.md after the split, then hand it to the reviewers." >&2
  exit 3
fi

echo
echo "Next: fill in the TODOs of \"## 3\" in evidence.md, then hand it to the reviewers."
echo "      Section 3.3 must quote the requirement text, not only its location."
