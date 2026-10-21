#!/usr/bin/env bash
# レビュー前の事実収集。diff・変更ファイル全文・検証ログを evidence.md にまとめる。
#
# 使い方:
#   collect-evidence.sh <base-ref> [出力ディレクトリ] [-- "<検証コマンド>" ...]
#
# 例:
#   collect-evidence.sh origin/main /tmp/review-tk01
#   collect-evidence.sh origin/main /tmp/review-tk01 -- "bun run typecheck" "bun test"
#   REVIEW_VERIFY=$'bun run typecheck\nbun test' collect-evidence.sh origin/main /tmp/review-tk01
#
# 検証コマンドは 1 引数 1 コマンド。`--` の後ろに複数並べる。
# 2 つ目以降の `--` は受け付けない（コマンド名として解釈されると事故になるため）。
#
# 出力:
#   <out>/evidence.md   骨組み（3 章「検証済み事実」は人が埋める）
#   <out>/diff.patch    生の diff
#   <out>/files/        変更ファイル全文
#   <out>/check.log     検証コマンドのログ（全文）
#
# 注意:
#   - このスクリプトは事実を集めるだけで判断はしない。
#     「検証済み事実」節はオーケストレータが埋めること。
#   - 検証コマンドはプロジェクトごとに違うので、ここでは決め打ちしない。
#     指定が無ければログ節は空のまま生成される（失敗はしない）。
#   - 出力先はリポジトリの外に置くこと。リポジトリ内を指定すると
#     レビューの完了条件「git status が変わらない」を自分で破る。
#   - 未追跡（??）ファイルは diff にも全文にも入らない。先に `git add -N` すること。

set -euo pipefail

usage() {
  sed -n '/^# 使い方:/,/^# 出力:/p' "$0" | sed 's/^# \{0,1\}//'
}

if [ $# -lt 1 ]; then
  usage >&2
  exit 2
fi

BASE="$1"; shift

# 第 2 引数が -- でなければ出力ディレクトリとして扱う
if [ $# -gt 0 ] && [ "$1" != "--" ]; then
  OUT="$1"; shift
else
  OUT="/tmp/review-$(date +%Y%m%d-%H%M%S)"
fi

if [ -z "$OUT" ]; then
  echo "error: 出力ディレクトリが空" >&2
  usage >&2
  exit 2
fi

if [ $# -gt 0 ]; then
  [ "$1" = "--" ] || { echo "error: 想定しない引数: $1" >&2; usage >&2; exit 2; }
  shift
fi

VERIFY_CMDS=("$@")
for cmd in "${VERIFY_CMDS[@]+"${VERIFY_CMDS[@]}"}"; do
  if [ "$cmd" = "--" ]; then
    echo "error: 検証コマンドに '--' が含まれる。1 引数 1 コマンドで渡すこと" >&2
    usage >&2
    exit 2
  fi
done

# 出力先を絶対パス化（cd より前に解決する。相対パスがリポジトリ直下に落ちるのを防ぐ）
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
    echo "error: 出力先がリポジトリ内 ($OUT)。レビューは作業ツリーを汚さないので /tmp 配下を指定する" >&2
    exit 2
    ;;
esac

cd "$REPO_ROOT"

HEAD_REF="$(git rev-parse --short HEAD)"
# 3 点 diff の実際の比較基点は merge-base。base 名だけだと追跡できないので sha も残す
BASE_SHA="$(git merge-base "$BASE" HEAD)"
BASE_SHA_SHORT="$(git rev-parse --short "$BASE_SHA")"

# 前回の残骸を消す（別 base で再実行したとき、古いファイル全文が混ざるのを防ぐ）
rm -rf "$OUT/files"
mkdir -p "$OUT/files"

# git は既定で非 ASCII パスを "..." 形式にクォートする。それを解除し、
# -z（NUL 区切り）で読むことでタブ・改行を含むパスでも壊れないようにする。
GIT_DIFF=(git -c core.quotePath=false diff --no-color)

STATUSES=()   # 各行の status（表示用）
PATHS=()      # 表示用パス（リネームは new）
TARGETS=()    # コピー対象パス

collect() {
  # collect <diff 引数...>
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
        # 削除ファイルは全文を持たない
        case "$st" in D*) ;; *) TARGETS+=("$new") ;; esac
        ;;
    esac
  done
}

DIFF_FILE="$OUT/diff.patch"
"${GIT_DIFF[@]}" "$BASE...HEAD" >"$DIFF_FILE"
collect "$BASE...HEAD"

# ステージされていない変更も拾う（作業ツリーに未コミットがある場合の取りこぼし防止）。
# diff に追記するだけでなく name-status にも反映する。片方だけだと
# 「diff には出るが全文が無いファイル」が生まれる。
UNCLEAN=0
if ! git diff --quiet || ! git diff --cached --quiet; then
  UNCLEAN=1
  git -c core.quotePath=false diff --no-color >>"$DIFF_FILE"
  git -c core.quotePath=false diff --no-color --cached >>"$DIFF_FILE"
  collect            # 作業ツリーの未ステージ分
  collect --cached   # ステージ済み分
  echo "WARN: 未コミットの変更を diff に含めた。レビュー前にコミットを推奨" >&2
fi

# 同じパスが複数の status を持つ場合（例: 未ステージの追加は A と M の 2 行になる）は
# 意味の強い方を 1 つに握る。A を M に化けさせると「新規」が見えなくなるため。
_merge_status() {
  local a="$1" b="$2"
  case "$a$b" in
    *A*) echo 'A' ;;
    *D*) echo 'D' ;;
    *)   case "$a" in R*|C*) echo "$a" ;; *) echo "$b" ;; esac ;;
  esac
}

# コミット済みと未コミットで同じパスが二重に並ぶのを防ぐ。
# STATUSES と PATHS は同じ index で対応しているので、まとめて間引く。
# パスには改行やタブも入りうるので、区切り文字で連結せず連想配列で見る。
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

# パスにタブ・改行・バックスラッシュが入っても 1 行 1 件を保てるようエスケープする
# （-z で読むときに使う。人が読む用の一覧はこの形）
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

# diff.patch と件数を合わせるため、未コミット分も含めた実数を併記する
{
  echo "コミット済み (${BASE}...HEAD): $(git diff --shortstat "${BASE}...HEAD")"
  if [ "$UNCLEAN" -eq 1 ]; then
    UNCLEAN_STAT="$({
      git diff --shortstat
      git diff --shortstat --cached
    } | sed 's/^ *//' | sed '/^$/d')"
    if [ -n "$UNCLEAN_STAT" ]; then
      echo "未コミット（追跡済み）:"
      printf '%s\n' "$UNCLEAN_STAT" | sed 's/^/    /'
    fi
  fi
} >"$OUT/shortstat.txt"

# 未追跡ファイルは diff にも name-status にも全文にも入らない。
# 黙って落とすと「変更が無い」と誤読されるので件数を出す。
UNTRACKED=()
mapfile -d '' -t UNTRACKED < <(git ls-files --others --exclude-standard -z)
UNTRACKED_COUNT="${#UNTRACKED[@]}"

# 各変更ファイルの全文を保存（削除ファイルは skip）
copied=0
for target in "${TARGETS[@]+"${TARGETS[@]}"}"; do
  [ -f "./$target" ] || continue
  # ディレクトリ構造を保ってコピーする（ファイル名の変換はパスの衝突を招くため）
  dest="$OUT/files/$target"
  mkdir -p "$(dirname "$dest")"
  # `--` を付けないと `-` で始まるパスで cp が異常終了し、set -e で全体が止まる
  cp -- "./$target" "$dest"
  copied=$((copied + 1))
done

# 検証ログ（失敗しても続行する）
CHECK_LOG="$OUT/check.log"
: >"$CHECK_LOG"
LOG_LIMIT=200

run_cmd() {
  echo "\$ $*"
  # シェル経由で実行し、パイプやリダイレクトを含む指定も受け付ける
  bash -c "$*" 2>&1 || echo "(exit != 0)"
  echo
}

if [ "${#VERIFY_CMDS[@]}" -gt 0 ]; then
  for cmd in "${VERIFY_CMDS[@]}"; do
    run_cmd "$cmd" >>"$CHECK_LOG"
  done
elif [ -n "${REVIEW_VERIFY:-}" ]; then
  # REVIEW_VERIFY は改行区切りで複数コマンドを指定できる
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    run_cmd "$cmd" >>"$CHECK_LOG"
  done <<<"$REVIEW_VERIFY"
else
  echo "(検証コマンド未指定。必要なら -- の後ろに渡して再実行する)" >>"$CHECK_LOG"
fi

LOG_LINES="$(wc -l <"$CHECK_LOG")"
if [ "$LOG_LINES" -gt "$LOG_LIMIT" ]; then
  LOG_BODY="$(tail -n "$LOG_LIMIT" "$CHECK_LOG")"
  LOG_NOTE="... （先頭 $((LOG_LINES - LOG_LIMIT)) 行を省略。全文: ${CHECK_LOG}）"
else
  LOG_BODY="$(cat "$CHECK_LOG")"
  LOG_NOTE=""
fi

TICKET="$(basename "$OUT" | sed 's/^review-//')"

status_label() {
  case "$1" in
    A*) echo "新規" ;;
    M*) echo "変更" ;;
    D*) echo "削除" ;;
    R*) echo "リネーム" ;;
    C*) echo "コピー" ;;
    *)  echo "$1" ;;
  esac
}

{
  echo "# ${TICKET} レビュー対象 evidence"
  echo
  echo "生成: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "base: ${BASE} (merge-base ${BASE_SHA_SHORT})    head: ${HEAD_REF}"
  echo "作業ディレクトリ: ${REPO_ROOT}"
  echo "成果物ディレクトリ: ${OUT}"
  if [ "$UNCLEAN" -eq 1 ]; then
    echo
    echo "**WARN: 未コミットの変更が diff に含まれている。**"
  fi
  if [ "$UNTRACKED_COUNT" -gt 0 ]; then
    echo
    echo "**WARN: 未追跡ファイルが ${UNTRACKED_COUNT} 件ある。diff にも全文にも含まれていない。**"
    echo "（対象に含めるなら \`git add -N <path>\` してから再実行する）"
    echo
    for f in "${UNTRACKED[@]}"; do
      echo "- \`$(esc_path "$f")\`"
    done
  fi
  echo
  echo "## 1. チケット / 受け入れ条件"
  echo
  echo "<!-- TODO: 要件定義・チケットの受け入れ条件を file:line 付きで転記する -->"
  echo
  echo "- 対象チケット: <!-- TODO: task-management の uid とタイトル。DB に無ければ「DB 外（PR / ブランチのみ）」 -->"
  echo "- 受け入れ条件:"
  echo "  - <!-- TODO: 条件 — 根拠: docs/requirements.md:行 / チケット uid の description -->"
  echo
  echo "## 2. 差分"
  echo
  cat "$OUT/shortstat.txt"
  echo
  echo "対象ファイル一覧:"
  echo
  echo '| ファイル | 区分 |'
  echo '|---|---|'
  for idx in "${!PATHS[@]}"; do
    # 表を崩させる文字を実体ではなく表示用に置換する（パスの実体は name-status.txt 側）
    cell="$(esc_path "${PATHS[$idx]}" | sed 's/|/\\|/g' | tr -d '\r')"
    echo "| ${cell} | $(status_label "${STATUSES[$idx]}") |"
  done
  echo
  echo '### diff'
  echo
  echo '```diff'
  cat "$DIFF_FILE"
  echo '```'
  echo
  echo '### 変更ファイル全文'
  echo
  while IFS= read -r -d '' f; do
    name="${f#"$OUT/files/"}"
    echo "#### $(esc_path "$name")"
    echo
    # 内容に ``` が含まれていてもフェンスが閉じないよう、最長の連続バッククォートより
    # 長いフェンスを使う
    fence="$(python3 - "$f" <<'PY'
import re, sys
with open(sys.argv[1], 'r', encoding='utf-8', errors='replace') as fh:
    s = fh.read()
longest = max((len(m) for m in re.findall(r'`+', s)), default=0)
print('`' * max(3, longest + 1))
PY
)"
    echo "${fence}"
    cat "$f"
    echo "${fence}"
    echo
  done < <(find "$OUT/files" -type f -print0 | sort -z)
  echo
  echo '## 3. 検証済み事実'
  echo
  echo '<!-- TODO: レビュアーはここを再検証しない。必ず file:line か実行ログの該当行を付ける -->'
  echo
  echo '### 3.1 実行して確認したこと'
  echo
  if [ -n "$LOG_NOTE" ]; then
    echo "\`${LOG_NOTE}\`"
    echo
  fi
  echo '```text'
  echo "$LOG_BODY"
  echo '```'
  echo
  echo "- 検証ログ全文: \`${CHECK_LOG}\`"
  echo '- <!-- TODO: 上のログから読み取れる事実 -->'
  echo
  echo '### 3.2 フレームワーク・依存の挙動（判断が割れる点）'
  echo
  echo '- <!-- TODO: 例: lib の X は Y という挙動。根拠: node_modules/pkg/file:line -->'
  echo
  echo '### 3.3 仕様の該当箇所'
  echo
  echo '- <!-- TODO: docs/requirements.md:120-134: 該当要件の引用 -->'
  echo
  echo '### 3.4 対象外・既知の未対応'
  echo
  echo '- <!-- TODO: 今回のスコープ外・既存の未対応 -->'
  echo
  echo '## 4. レビュー時の注意'
  echo
  echo '- 上記に無い情報が必要な場合は、レポート末尾の「未確認事項」に 1 行で書くだけにする。'
  echo '- ここに書かれた事実を疑う場合も、実験のやり直しはしない。'
  echo '- 指摘の修正は禁止。起票はオーケストレータが行う。'
} >"$OUT/evidence.md"

echo "evidence を生成した: $OUT/evidence.md"
echo "  変更ファイル全文: $copied 件 -> $OUT/files/"
echo "  検証ログ: $CHECK_LOG (${LOG_LINES} 行)"
echo
echo "次の手順: evidence.md の「## 1」「## 3」の TODO を埋めてからレビュアーへ渡す。"
