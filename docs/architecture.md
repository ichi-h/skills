# アーキテクチャ

## このリポジトリの立ち位置

本体は `skills/task-management/SKILL.md`（スキル）です。スキルはエージェントへの手順書と
SQLite スキーマを定義し、`$(pwd)/.<ユーザー名>/issues.db` に状態を書き込みます。
アプリケーション（`task-management-viewer`）はその DB を読むだけで、状態を変更しません。

```
エージェント ──(SKILL.md の手順)──> sqlite3 ──> .<user>/issues.db
                                                    │ 読み取り専用
                                                    ▼
                                    task-management-viewer（Bun + React）
                                                    │
                                             ブラウザ（3 ビュー + SSE 自動更新）
```

したがって、ビューアを止めても作業は進みます。ビューアは可視化のための副産物です。

## ディレクトリ構成

```
skills/task-management/
  SKILL.md                 スキル本体（英語）
  SKILL.ja.md              スキル本体（日本語）
src/
  server.ts                Bun.serve。DB 読み取り・API・SSE・ファイル監視
  shared/types.ts          サーバーとクライアントで共有する型（DB の状態と一致させる）
  client/                  フロントエンド（詳細は src/client/README.md）
scripts/
  build.ts                 静的ビルド（dist/）
  compile.ts               単一バイナリのビルド（Nix からも利用）
nix/
  package.nix              本体の導出（依存を FOD から持ち込んでオフラインビルド）
  deps.nix                 node_modules を取得する固定出力導出
  deps.hash                deps.nix の出力ハッシュ
flake.nix                  packages / apps / devShells / overlay / checks / formatter
docs/architecture.md       このファイル
```

## データの流れ

1. スキルが `sqlite3` で DB を更新する（`tickets` / `tasks` / `task_dependencies`）。
2. ビューアはファイル監視（`fs.watch`）で DB・WAL・SHM の変更を検知し、接続を破棄して読み直す。
3. 変更は SSE（`/api/events`）で接続中のブラウザへ `{"type":"update"}` として通知される。
4. ブラウザは `/api/board` を再取得し、ボード / タスク一覧 / 集計を再描画する。

「実行可能」の判定はスキーマではなくスキルのルール（先行タスクが `completed` か `canceled`）を
そのまま実装しています。この判定はサーバー側で行い、`TaskDto.executable` として返します。

## DB アクセスの方針

- 接続は読み取り専用（`new Database(path, { readonly: true })`）。WAL を読めない環境では通常接続へフォールバックする。
- 起動時に `sqlite_master` を引き、`tickets` / `tasks` / `task_dependencies` の存在を確認する。
  欠けていれば 500 とエラー内容を返し、画面側で DB パスの指定方法を案内する。
- DB パスは `--db` / `-d`、非オプション引数、`ISSUES_DB`、既定値 `$(pwd)/.<ユーザー名>/issues.db` の順で解決する。

スキーマのカラムを追加した場合は `src/shared/types.ts` と `src/server.ts` のクエリを更新してください
（ビューアはスキーマ変更に自動追従しません）。

## ビルドと配布

| 目的             | 入口              | 出力                                            |
| ---------------- | ----------------- | ----------------------------------------------- |
| 開発             | `bun run dev`     | Bun が HTML を取り込んでその場でバンドル（HMR） |
| 本番相当         | `bun run start`   | 同上（`NODE_ENV=production` で HMR なし）       |
| 静的ホスティング | `bun run build`   | `dist/`                                         |
| 単一バイナリ     | `bun run compile` | `build/task-management-viewer`                  |
| Nix パッケージ   | `nix build`       | `result/bin/task-management-viewer`             |

単一バイナリは Tailwind の処理済みアセットまで埋め込むため、実行時に `node_modules` を要しません。
Nix パッケージは同じ `scripts/compile.ts` を呼びます。

## Nix パッケージング

- `nix/deps.nix` だけがネットワークを使う固定出力導出（FOD）。`bun install --ignore-scripts` で
  `node_modules` を取得し、ハッシュを `nix/deps.hash` に固定する。
- `nix/package.nix` は `deps` の `node_modules` を symlink してから `compile.ts` を実行する（オフライン）。
- `flake.nix` は `packages`（`default` / `viewer` 相当の `task-management-viewer`、`deps`）、`apps`、
  `devShells`（bun + sqlite3）、`overlays.default`、`checks`、`formatter` を公開する。
- overlay は `final.callPackage ./nix/package.nix` を使うため、`pkgs.task-management-viewer` として参照できる。

依存を更新したときのハッシュ更新手順:

```bash
rm -f nix/deps.hash
nix build .#deps --no-link 2>&1 | grep 'got:'
# 表示されたハッシュを nix/deps.hash に書き込む
echo 'sha256-...=' > nix/deps.hash
nix build .# --no-link   # 本体もビルドできることを確認
```

## 開発コマンド

```bash
nix develop        # bun と sqlite3 が入ったシェル
bun run typecheck  # tsc --noEmit
nix fmt            # nixfmt で整形
nix flake check    # 評価チェック
```

## API

| エンドポイント    | 内容                                                |
| ----------------- | --------------------------------------------------- |
| `GET /api/board`  | チケット・タスク・依存関係・集計をまとめて返す      |
| `GET /api/events` | DB 変更通知の SSE ストリーム（`{"type":"update"}`） |

レスポンスの形は `src/shared/types.ts` の `BoardResponse` / `ErrorResponse` を参照してください。
詳細は [`../src/README.md`](../src/README.md) にあります。
