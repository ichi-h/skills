---
name: review-prepare
description: 並列レビューの前準備。レビュー対象の diff を確定し、レビュアーに渡す事実パック（evidence.md）を生成するスキル。指摘の判断はしない。
---

# Review Prepare スキル

レビュー対象を確定し、レビュアーが探索不要で判断できる事実パックを作る。

**このスキルの成果物は evidence.md である。指摘の判断はしない。コードは 1 行も変えない。**

## 原則

- レビュアーが読むのは diff ではなく `evidence.md` である。だから事実はすべて `evidence.md`
  に入れ、内容は「調べ物の材料」ではなく「答え」にする。
- **同じ事実は 1 回だけ書く。** 全文と diff の両方に載せない。
- **レビュアーに見えない事実は、ツール呼び出し 1 回に等しい。**
  「`docs/requirements.md:117-133` を見よ」で済ませない。要件の文を貼る。

## 手順

### 1. 対象を確定する

ユーザー（またはオーケストレータ）から、レビュー対象のチケット ID・ブランチ・
比較基準 `base`（マージ先 ref）・受け入れ条件を受け取る。不明なら確認する。

```bash
mkdir -p /tmp/review-<label>                                  # 先に作る（下のリダイレクト用）
# タスク管理 DB（.<ユーザー名>/issues.db）を作業ツリーの差分から外す
EXCLUDE="$(git rev-parse --git-path info/exclude)"
mkdir -p "$(dirname "$EXCLUDE")"
grep -qxF ".$(whoami)/" "$EXCLUDE" 2>/dev/null || echo ".$(whoami)/" >> "$EXCLUDE"
git status --porcelain > /tmp/review-<label>/status.before   # 完了判定に使う記録
git diff --shortstat "<base>...HEAD"                          # 800 行超ならレビューを分割する
```

- `status.before` との差分で完了判定する。開始前の dirty は許容。
- **対象 diff が 800 行超なら 1 回でレビューしない。** 分割して戻す。
  分割の単位はファイル数ではなく関心ごと。1 つの観点が同時に頭に置くファイル群を 1 波にする
  （例: `app/lib/*` の波と `server/*` + `test/*` の波）。
  波ごとに `OUT` を変え（`/tmp/review-<label>-1`、`-2`）、同じチケットを各波に引き継ぐ。
- 未追跡（`??`）ファイルは diff に入らない。対象に含めるなら `git add -N <path>` する。

### 2. evidence.md を生成する

`collect-evidence.sh` が骨組みを作る。スクリプトは**このスキルのディレクトリ**から
相対パスで呼ぶ（インストール先は環境で違うため）。

```bash
SKILL_DIR=<このスキルのディレクトリ>
"$SKILL_DIR/scripts/collect-evidence.sh" <base-ref> /tmp/review-<label> \
  -- "bun run typecheck" "bun test"   # 検証コマンド。プロジェクトごとに決める
```

スクリプトは新規ファイルを行番号付きで載せ、変更ファイルはハンクだけを出し、全文は
`<out>/files/` に置く。60 KB / 1,200 行を超えたら警告する。

変更ファイルのハンクだけでは判断できないときは、そのファイルの見出しの下に
`scripts/evidence-ranges.py` で該当領域を行番号付きで足す。全文は足さない。

```bash
git -c core.quotePath=false diff --no-color "<base>...HEAD" -- docs/operations.md \
  | "$SKILL_DIR/scripts/evidence-ranges.py" --file docs/operations.md --pad 15
```

### 3. TODO を埋める

生成された evidence.md の `## 1`（チケット / 受け入れ条件）と `## 3`（検証済み事実）を埋める。

埋めるのは**レビュアーが再検証しがちなものだけ**:

- 実際に動かして確認した挙動（実行ログの該当行）
- 判断が割れるフレーム・依存の挙動（`node_modules/pkg/file:line` まで）
- **仕様書の該当行の本文。** 場所ではなく文を貼る。貼られた 4 文は事実になる。
- 対象外・既知の未対応の明示

**事実には必ず file:line を付ける。** 無いとレビュアーは「念のため確認」を始め、探索モードに落ちる。

`## 2`（差分）と `## 4`（注意書き）はスクリプトが生成済みなので触らない。

### 4. 投入前に予算を確認する

```bash
wc -c -l /tmp/review-<label>/evidence.md        # 60 KB / 1,200 行以内であること
grep -c 'TODO' /tmp/review-<label>/evidence.md  # 0 であること（真に対象外の項目を除く）
```

- 予算超過なら波を増やすか素材を外へ出す。**予算を下げてファイルに合わせるのは禁止。**
- 投入前に、段落ごとに「このファイルだけで指摘に到達できるか」を自問する。
  場所を指すだけの段落は事実ではなく、探索の理由である。
- 何度も要求される素材は、次の実行でパックに入れる。レビュアーごとに再発見させるのではなく、
  レビューの後に回収する（`review-integrate` を参照）。

## 完了条件

- `/tmp/review-<label>/evidence.md` が存在し、TODO がすべて埋まっており、60 KB / 1,200 行以内である
- `/tmp/review-<label>/status.before` が記録済み
- **diff に変更が無い**
