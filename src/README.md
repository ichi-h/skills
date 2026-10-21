# src（サーバーとビルド）

ビューアのサーバー側です。Bun の `Bun.serve` で HTML をその場でバンドルし、`bun:sqlite` で DB を読みます。
全体像は [`../docs/architecture.md`](../docs/architecture.md) を参照してください。

```
src/
  server.ts              Bun.serve。API・SSE・DB 読み取り・ファイル監視
  shared/types.ts        サーバーとクライアントで共有する型
  client/                フロントエンド（../src/client/README.md）
scripts/
  build.ts               静的ビルド（dist/）
  compile.ts             単一バイナリのビルド
```

## server.ts

### DB パスの解決

`resolveDbPath()` が次の優先順で決めます。

1. `ISSUES_DB` 環境変数
2. `--db <path>` / `-d <path>`（フラグの直後の引数）
3. 非オプション引数（最初のもの）
4. 既定値 `$(pwd)/.<USER>/issues.db`（スキルの既定値）

パスは `resolve()` で絶対化します。

### BoardReader

DB の読み取りを担当するクラスです。接続は遅延評価で、`invalidate()` で破棄できます。

- `connect()`: 存在確認 → 読み取り専用オープン（失敗時は通常接続へフォールバック）→
  `sqlite_master` で必須テーブル（`tickets` / `tasks` / `task_dependencies`）を検証
- `read()`: チケット・タスク・依存関係を全件読み、DTO に組み立てる
  - `blockedBy`（先行タスク）と `blocks`（後続タスク）を `TaskRef` で相互に張る
  - `executable` は「`state === 'not_yet'` かつ先行タスクがすべて `completed` / `canceled`」
  - チケット単位の `counts`（total / notYet / completed / canceled）と `executableCount` を集計
  - 全体の `stats` をチケット状態・タスク状態ごとに数える
- `close()` / `invalidate()`: 接続を閉じ、次回 `read()` で張り直す

型は `src/shared/types.ts` の `BoardResponse` / `TicketDto` / `TaskDto` / `TaskRef` が返り値です。

### ファイル監視と SSE

`createWatcher(onChange)` は DB の**ディレクトリ**を `fs.watch` します。

- 対象ファイル名が DB 本体か `"<db>-"` で始まるもの（`-wal` / `-shm`）だけを拾う
- 150ms のデバウンスで `onChange` を呼ぶ
- ディレクトリが差し替えられた場合に備え、5 秒ごとに監視を張り直す

`onChange` では `reader.invalidate()` してから、`subscribers` に `{"type":"update","at":...}` を配信します。
SSE 接続は 15 秒ごとに `: ping` を送り、切断時は `subscribers` から外します。

### ルーティング

| パス          | 処理                                                               |
| ------------- | ------------------------------------------------------------------ |
| `/`           | `src/client/index.html`（Bun がバンドル）                          |
| `/api/board`  | `reader.read()` を JSON で返す。失敗時は 500 + `{ error, detail }` |
| `/api/events` | SSE ストリーム。接続直後に 1 回 `update` を送る                    |
| その他        | 404                                                                |

`development` は `NODE_ENV !== "production"` で有効になります（HMR の有無）。
SIGINT / SIGTERM で監視・DB・サーバーを閉じます。

## shared/types.ts

DB の状態（`TicketState` / `TaskState`）と API の DTO を定義します。DB の `CHECK` 制約と一致させる必要があります。
カラムを追加した場合はここを起点に `server.ts` のクエリも更新してください。

## scripts/build.ts（静的ビルド）

`src/client/index.html` をエントリに `Bun.build` し、`dist/` へ出力します（`bun-plugin-tailwind` で CSS を処理、minify 有効）。
静的ホスティング向けで、`Bun.serve` を使う通常の起動では不要です。

## scripts/compile.ts（単一バイナリ）

`src/server.ts` をエントリに `Bun.build`（`target: "bun"`, `compile.outfile`）し、
HTML と Tailwind 処理済み CSS を埋め込んだ実行ファイルを作ります。

```bash
bun run compile                       # build/task-management-viewer
bun run compile --outfile /tmp/app    # 出力先を指定
```

Nix パッケージ（`nix/package.nix`）もこのスクリプトを呼びます。
