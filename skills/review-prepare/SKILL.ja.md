---
name: review-prepare
description: 並列レビューの前準備。レビュー対象の diff を確定し、レビュアーに渡す事実パック（evidence.md）を生成するスキル。指摘の判断はしない。
---

# Review Prepare スキル

レビュー対象を確定し、レビュアーが探索不要で判断できる事実パックを作る。

**このスキルの成果物は evidence.md である。指摘の判断はしない。コードは 1 行も変えない。**

## 原則

- レビュアーが読むのは `evidence.md`（判断材料）であり、`diff.patch` は指摘が引用する行を
  開くときだけ使う。**diff を `evidence.md` の中に繰り返さない。** diff は `diff.patch` 1 本に置き、
  それが唯一の写しである。inline していた頃は実測でパックの 93% を diff が占め、
  レビュアーは事実ではなくパッチ全体を読み直していた。
- **同じ事実は 1 回だけ書く。** 全文と diff の両方に載せない。
- **レビュアーに見えない事実は、ツール呼び出し 1 回に等しい。**
  「`docs/requirements.md:117-133` を見よ」で済ませない。要件の文を貼る。
- **事実には存在理由を持たせる。** 場所を指すだけの段落は事実ではなく、探索の理由である。

## 生成物

```
/tmp/review-<label>/
  evidence.md      # レビュアーが読むもの: §1 チケット / §2 棚卸し / §3 検証済み事実
  diff.patch       # diff の唯一の写し（lockfile・生成物は除外済み）
  files/           # 変更ファイルの全文（ハンクだけでは足りないとき用）
  check.log        # 検証コマンドの全ログ
  status.before    # 開始時の `git status --porcelain`（完了判定用）
  name-status.txt  # 機械可読なファイル一覧
  shortstat.txt    # コミット済み / 未コミットの行数
```

`diff.patch`、`files/`、`check.log`、`shortstat.txt`、`name-status.txt`、`status.before` は
要約ではなく事実そのものである。サイズはパックの予算に数えない（必要時に読むだけ）。

## 手順

### 1. 対象を確定する

ユーザー（またはオーケストレータ）から、レビュー対象のチケット ID・ブランチ・
比較基準 `base`（マージ先 ref）・受け入れ条件を受け取る。不明なら確認する。

```bash
mkdir -p /tmp/review-<label>
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
  `collect-evidence.sh` は読み飛ばした未追跡ファイルの件数を報告する。
  未追跡だけの作業は「差分なし」ではない。

### 2. evidence.md を生成する

`collect-evidence.sh` が骨組みと収集物を作る。スクリプトは**このスキルのディレクトリ**から
相対パスで呼ぶ（インストール先は環境で違うため）。

```bash
SKILL_DIR=<このスキルのディレクトリ>
"$SKILL_DIR/scripts/collect-evidence.sh" <base-ref> /tmp/review-<label> \
  --ticket <uid> \                     # 任意: タスク管理 DB から §1 を埋める
  -- "bun run typecheck" "bun test"    # 検証コマンド。プロジェクトごとに決める
```

スクリプトの挙動:

- **diff は `diff.patch` にだけ書く。** `evidence.md` にはファイル表・shortstat・変更行数だけを載せる。
- **lockfile と生成物**（lockfile、`dist/`、`build/`、`coverage/`、`node_modules/`、`*.min.*`、
  `*.map`、`*.snap`、コード生成物）をパッチと `files/` の両方から外し、外した事実を §2 に
  状態と +/− 行数付きで 1 行ずつ残す。「どこへ消えたか」を誰も考えなくて済む。
- **`--ticket <uid>` があれば §1 をチケットから埋める**（`.<ユーザー名>/issues.db` がある場合）。
  無ければ §1 は TODO のまま残る。
- **予算はスクリプト自身が強制する**: パック 15 KB / 400 行、パッチ 800 変更行。
  超過時は生成物を書いたうえで **exit 3** を返す。レビューを分割するか素材を削ること。
  予算を下げてファイルに合わせるのは禁止。

変更ファイルのハンクだけでは判断できないときは、`scripts/evidence-ranges.py` で該当領域だけを
足す。全文は足さない。

```bash
git -c core.quotePath=false diff --no-color "<base>...HEAD" -- docs/operations.md \
  | "$SKILL_DIR/scripts/evidence-ranges.py" --file docs/operations.md --pad 15
```

これは追加の手段である。パッチと `files/` に本文は既にあるので、
「場所を書く方が領域を貼るよりレビュアーに高くつく」ときだけ使う。

### 3. TODO を埋める

生成された evidence.md の `## 3`（検証済み事実）を埋める。`## 1` はチケットから埋まらなかった
ときだけ埋める。`## 2` は生成済みなので触らない。`## 4` は存在しない。レビューへの注意書きは
`review-dispatch/templates/prompt.md` にあり、レビュアーは全員それを読む。

埋めるのは**レビュアーが再検証しがちなものだけ**:

- 実際に動かして確認した挙動（実行ログの該当行）
- 判断が割れるフレーム・依存の挙動（`node_modules/pkg/file:line` まで）
- **仕様書の該当行の本文。** 場所ではなく文を貼る。貼られた 4 文は事実になる。
- 対象外・既知の未対応の明示

**事実には必ず file:line を付ける。** 無いとレビュアーは「念のため確認」を始め、探索モードに落ちる。

### 4. 投入前に予算を確認する

```bash
echo "exit: $?"   # 手順 2 の終了コード。0 以外なら投入しない
grep -c 'TODO' /tmp/review-<label>/evidence.md   # 0 であること（真に対象外の項目を除く）
wc -c -l /tmp/review-<label>/evidence.md         # 15 KB / 400 行以内が目安
```

サイズはスクリプトが落とす。grep はその裏側を拾う ——
TODO の残ったパックは予算より小さく、見た目は完璧だからである。
片方が見落とすものを片方が捕まえるので、両方やる。

- 予算超過なら波を増やすか素材を外へ出す。**予算を下げてファイルに合わせるのは禁止。**
- 投入前に、段落ごとに「このファイルだけで指摘に到達できるか」を自問する。
  場所を指すだけの段落は事実ではなく、探索の理由である。

## 完了条件

- `/tmp/review-<label>/evidence.md` が存在し、TODO が埋まっており、`collect-evidence.sh` が exit 0 した
- `/tmp/review-<label>/diff.patch` が存在する（レビュアーはこれを読む）
- `/tmp/review-<label>/status.before` が記録済み
- **diff に変更が無い**
