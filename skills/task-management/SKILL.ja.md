---
name: task-management
description: sqlite3でチケット（課題）・タスク・依存関係を管理するスキル。課題が明確な開発作業を複数工程に分解し、順序立てて進めたいときに必ず使う（「タスク分解して」「チケット化して」「再開して」、issues.db への言及など）。分解が不要なほど単純な課題には使わない。
---

# Task Management スキル

## 用語

- **課題**: 解決すべき問題。1課題1関心。「何が問題か」「なぜ解決するか」「解決の方針」（課題三要素）を必ず含む。
- **チケット**: 課題を管理するレコード。1チケット = 1課題 = 1PRが目安。
- **タスク**: 課題解決に必要な工程。なるべく小さく分割し、全完了で課題が解決される粒度にする。

## ルール

- DBは `$(pwd)/.<ユーザー名>/issues.db`。ユーザー名は `whoami` で取得する（例: ユーザー名が `alice` なら `.alice/issues.db`）。なければ `mkdir -p ".$(whoami)"` して下記スキーマで作成する。
- `PRAGMA foreign_keys = ON;` は接続ごとの設定。`sqlite3` 実行のたびにSQL先頭へ付ける。
- 複数文の更新は `BEGIN; ... COMMIT;` で囲む。
- uid は自動採番。`INSERT ... RETURNING uid` で受け取る（`RETURNING` は SQLite 3.35+）。
- 単一の実行者が順に回す前提（排他制御なし）。

## スキーマ

```sql
CREATE TABLE tickets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uid TEXT UNIQUE NOT NULL DEFAULT (lower(hex(randomblob(2)))) CHECK(length(uid) = 4),
  title TEXT NOT NULL,
  description TEXT NOT NULL, -- 課題三要素。見出し: ## 何が問題か / ## なぜ解決するか / ## 解決の方針
  state TEXT NOT NULL DEFAULT 'not_yet'
    CHECK(state IN ('not_yet', 'in_progress', 'completed', 'archived'))
);

-- canceled は「解決不要と判断され実行しなかった」タスク。依存関係上は completed と同等。
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uid TEXT UNIQUE NOT NULL DEFAULT (lower(hex(randomblob(2)))) CHECK(length(uid) = 4),
  ticket_id INTEGER NOT NULL REFERENCES tickets(id),
  title TEXT NOT NULL,
  description TEXT NOT NULL, -- 具体的な内容・チェックリスト
  state TEXT NOT NULL DEFAULT 'not_yet'
    CHECK(state IN ('not_yet', 'completed', 'canceled'))
);

-- 依存先がすべて completed/canceled になって初めて実行可能。依存なしは最初から実行可能。
CREATE TABLE task_dependencies (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id INTEGER NOT NULL REFERENCES tasks(id),
  depends_on_task_id INTEGER NOT NULL REFERENCES tasks(id),
  CHECK(task_id != depends_on_task_id),
  UNIQUE(task_id, depends_on_task_id)
);
```

## フロー

### 1. 課題をticketsへ保存

複数の関心があればチケットを分割する。課題三要素を明確にできなければ、理由を示してユーザーに検討を促し、保存しない。

```sql
INSERT INTO tickets (title, description) VALUES ('概要', '## 何が問題か ...') RETURNING uid;
```

### 2. 全工程をtasks / task_dependenciesへ

着手するなら `UPDATE tickets SET state='in_progress' WHERE uid='..'`。

```sql
INSERT INTO tasks (ticket_id, title, description)
VALUES ((SELECT id FROM tickets WHERE uid='チケットuid'), '概要', '詳細') RETURNING uid, title;

-- B は A の完了後
INSERT INTO task_dependencies (task_id, depends_on_task_id)
VALUES ((SELECT id FROM tasks WHERE uid='Bのuid'), (SELECT id FROM tasks WHERE uid='Aのuid'));
```

依存を追加したら**必ず循環チェック**。1行でも返れば循環なので、追加分を消して設計を見直す。

```sql
WITH RECURSIVE walk(origin, current, depth) AS (
  SELECT task_id, depends_on_task_id, 1 FROM task_dependencies
  UNION ALL
  SELECT w.origin, td.depends_on_task_id, w.depth + 1
  FROM walk w JOIN task_dependencies td ON td.task_id = w.current
  WHERE w.depth < 1000
)
SELECT DISTINCT t.uid, t.title FROM walk w JOIN tasks t ON t.id = w.origin
WHERE w.origin = w.current;
```

### 3. 実行可能なタスクを全件取得して遂行

```sql
SELECT t.* FROM tasks t
WHERE t.ticket_id = (SELECT id FROM tickets WHERE uid='チケットuid')
  AND t.state = 'not_yet'
  AND NOT EXISTS (
    SELECT 1 FROM task_dependencies td
    JOIN tasks t2 ON td.depends_on_task_id = t2.id
    WHERE td.task_id = t.id AND t2.state NOT IN ('completed', 'canceled')
  );
```

### 4. 状態を更新

```sql
UPDATE tasks SET state='completed' WHERE uid IN ('fe3a', 'w2gi');

-- 課題解決に不要になった場合のみ。面倒・困難は理由にならない。理由を残す。
UPDATE tasks SET state='canceled', description = description || char(10) || '[canceled] 理由: ...'
WHERE uid='xxxx';
```

### 5. 3〜4を繰り返し、完了判定

完了判定は「手順3が空」ではなく**未着手が0件**で行う。

```sql
SELECT COUNT(*) FROM tasks
WHERE ticket_id = (SELECT id FROM tickets WHERE uid='チケットuid') AND state='not_yet';
```

- 0件: 課題が解決済みか確認し、`UPDATE tickets SET state='completed' ...`。PRマージ後などは `archived` にしてよい。
- 残りがあるのに手順3も空: 依存関係の異常（循環・誤依存）。原因を調べてユーザーへ報告する。

## 再開

セッションを跨いだら、まず進行中の状況を確認して手順3へ戻る。

```sql
SELECT tk.uid, tk.title, t.uid AS task_uid, t.title AS task_title
FROM tickets tk
LEFT JOIN tasks t ON t.ticket_id = tk.id AND t.state='not_yet'
WHERE tk.state='in_progress' ORDER BY tk.id, t.id;
```

## タスクの差し込み

対象タスクの直後に新タスクを入れる。**後続の付け替え（UPDATE）を先に**行う。逆だと新タスクが自分自身に依存して止まる。

```sql
-- 1. 新タスク追加（返ってきた uid を以降に使う）
INSERT INTO tasks (ticket_id, title, description)
SELECT ticket_id, '新タスク', '詳細' FROM tasks WHERE uid='対象uid' RETURNING uid;

BEGIN;
-- 2. 対象に依存していた後続を、新タスク依存へ付け替え
UPDATE task_dependencies
SET depends_on_task_id = (SELECT id FROM tasks WHERE uid='新uid')
WHERE depends_on_task_id = (SELECT id FROM tasks WHERE uid='対象uid');
-- 3. 新タスクを対象の後ろに置く
INSERT INTO task_dependencies (task_id, depends_on_task_id)
VALUES ((SELECT id FROM tasks WHERE uid='新uid'), (SELECT id FROM tasks WHERE uid='対象uid'));
COMMIT;
```
