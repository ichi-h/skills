---
name: review-prepare
description: 並列レビューの前準備。レビュー対象の diff を確定し、レビュアーに渡す事実パック（evidence.md）を生成するスキル。指摘の判断はしない。
---

# Review Prepare スキル

レビュー対象を確定し、レビュアーが探索不要で判断できる事実パックを作る。

**このスキルの成果物は evidence.md である。指摘の判断はしない。コードは 1 行も変えない。**

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
- 対象 diff が 800 行超なら 1 回でレビューせず、分割して戻す。
- 未追跡（`??`）ファイルは diff に入らない。対象に含めるなら `git add -N <path>` する。

### 2. evidence.md を生成する

`collect-evidence.sh` が骨組みを作る。スクリプトは**このスキルのディレクトリ**から
相対パスで呼ぶ（インストール先は環境で違うため）。

```bash
SKILL_DIR=<このスキルのディレクトリ>
"$SKILL_DIR/scripts/collect-evidence.sh" <base-ref> /tmp/review-<label> \
  -- "bun run typecheck" "bun test"   # 検証コマンド。プロジェクトごとに決める
```

### 3. TODO を埋める

生成された evidence.md の `## 1`（チケット / 受け入れ条件）と `## 3`（検証済み事実）を埋める。

埋めるのは**レビュアーが再検証しがちなものだけ**:

- 実際に動かして確認した挙動（実行ログの該当行）
- 判断が割れるフレーム・依存の挙動（`node_modules/pkg/file:line` まで）
- 仕様書の該当行（`docs/requirements.md:120-134`）
- 対象外・既知の未対応の明示

**事実には必ず file:line を付ける。** 無いとレビュアーは「念のため確認」を始め、探索モードに落ちる。

`## 2`（差分）と `## 4`（注意書き）はスクリプトが生成済みなので触らない。

## 完了条件

- `/tmp/review-<label>/evidence.md` が存在し、TODO がすべて埋まっている
- `/tmp/review-<label>/status.before` が記録済み
- **diff に変更が無い**
