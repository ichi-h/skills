# task-management viewer

`task-management` スキルが管理する SQLite DB（`.&lt;ユーザー名&gt;/issues.db`）をブラウザで閲覧するためのビューアです。
Bun + React + Tailwind CSS で動作し、**閲覧専用**（DB への書き込みは一切行いません）。

## 特徴

- チケット / タスク / 依存関係をボード・一覧・集計の 3 ビューで表示
- タスクの依存関係と「実行可能（依存がすべて完了・中止済み）」を判定して強調
- 未着手タスクがあるのに実行可能タスクが 0 件のチケットを「依存異常?」として警告
- DB ファイル（および WAL/SHM）の変更を `fs.watch` で監視し、Server-Sent Events で画面を自動更新
- 依存パッケージは React のみ。DB は Bun 内蔵の `bun:sqlite` で読み取り専用オープン

## 起動

```bash
bun install

# DB を明示指定
bun run dev --db /path/to/.<user>/issues.db

# 既定値（$(pwd)/.<ユーザー名>/issues.db）を使う
bun run dev

# 本番相当（HMR なし）
NODE_ENV=production bun run start --db /path/to/.<user>/issues.db
```

`--db` の代わりに環境変数 `ISSUES_DB`、ポートは `PORT`（既定 3000）でも指定できます。
bun が入っていない環境では `nix run nixpkgs#bun -- install` のように nix 経由でも実行できます。

## スクリプト

| コマンド | 内容 |
| --- | --- |
| `bun run dev` | 開発サーバー（`--watch` + HMR） |
| `bun run start` | 本番相当で起動 |
| `bun run build` | `dist/` に静的ファイルを出力（静的ホスティング用。`scripts/build.ts` が Tailwind を処理） |
| `bun run typecheck` | `tsc --noEmit` |

## 構成

```
src/
  server.ts              Bun.serve。API・SSE・DB 読み取り・ファイル監視
  shared/types.ts        サーバーとクライアントで共有する型
  client/
    index.html           Bun がその場でバンドルするエントリ HTML
    frontend.tsx         React のマウント
    styles.css           Tailwind CSS のエントリ
    App.tsx              画面全体（ボード / タスク一覧 / 集計）
    hooks/useBoard.ts    API 取得と SSE 購読
    components/          TicketCard, TaskItem, StateBadge, Markdown
scripts/build.ts         静的ビルド（bun-plugin-tailwind を使用）
```

## API

| エンドポイント | 内容 |
| --- | --- |
| `GET /api/board` | チケット・タスク・依存関係・集計をまとめて返す |
| `GET /api/events` | DB 変更通知の SSE ストリーム（`{"type":"update"}`） |

DB が存在しない、または task-management のスキーマを持たない場合は `500` とエラー内容を返し、
画面側で DB パスの指定方法を案内します。DB を作り直した場合も再起動なしで復帰します。

## 前提スキーマ

`skills/task-management/SKILL.md` の定義（`tickets` / `tasks` / `task_dependencies`）を読み取るだけです。
スキーマの変更には追従しないため、カラム追加時は `src/server.ts` と `src/shared/types.ts` を更新してください。
