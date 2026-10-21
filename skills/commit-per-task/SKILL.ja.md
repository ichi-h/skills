---
name: commit-per-task
description: タスクが1つ完了するごとに、Conventional Commitsに従ってGitコミットを1つ作成するスキル。task-managementスキルを使う場面では、ユーザーがコミット不要と明言しない限り、あわせて自動的に使用する。
---

# Commit per Task スキル

`task-management` スキルと併用する。このスキルはバージョン管理だけを扱う。

## 規則

- **完了したタスク1つにつきコミット1つ。** 複数タスクをまとめない。完了したタスクを未コミットのまま残さない。
- **タスクを completed にする前にコミットする。**
- **1コミット1関心。** 無関係なリファクタや整形は独立したタスクにする。
- **タスクが触ったファイルだけをステージする。** 生成物やローカルのDBファイルは除外する。
- `--no-verify` を使わない。`--force` push をしない。

## メッセージ形式

Conventional Commits v1.0.0 に従う。

```text
<type>(<scope>): <description>

<body>
```

- `type`: `feat` / `fix` / `docs` / `style` / `refactor` / `perf` / `test` / `build` / `ci` / `chore` / `revert`。
- `scope`: 影響するドメイン（モジュール、パッケージ、ディレクトリ。例: `client`、`server`、`skills`）。リポジトリ全体に及ぶ変更のみ省略する。
- `description`: 命令形・小文字始まり・末尾ピリオド無し。ヘッダは72文字以内。変更が何をするかを書く。
- `body`: なぜ・何を。72文字で折り返す。自明な変更では省略する。

破壊的変更は type/scope の後に `!` を付け、`BREAKING CHANGE:` フッターで破壊内容と移行方法を書く。

```text
feat(db)!: rename not_yet to pending

BREAKING CHANGE: existing DBs must be migrated.
```
