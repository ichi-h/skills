# src/client（フロントエンド）

React 19 + Tailwind CSS v4 の SPA です。ビルドツールは Bun で、`src/client/index.html` をエントリに
`Bun.serve` がその場でバンドルします（開発時は HMR、`NODE_ENV=production` で無効）。
全体像は [`../../docs/architecture.md`](../../docs/architecture.md) を参照してください。

```
src/client/
  index.html            エントリ HTML（styles.css と frontend.tsx を読み込む）
  frontend.tsx          React のマウント（StrictMode）
  styles.css            Tailwind のエントリ（@import "tailwindcss" + ダークテーマの最小設定）
  App.tsx               画面全体（ヘッダー・フィルタ・3 ビュー）
  hooks/useBoard.ts     API 取得と SSE 購読
  components/
    TicketCard.tsx      ボードのチケットカード
    TaskItem.tsx        カード内のタスク行
    StateBadge.tsx      状態バッジとラベル
    Markdown.tsx        説明文の軽量 Markdown 描画
```

型はすべて `src/shared/types.ts`（`BoardResponse` / `TicketDto` / `TaskDto`）を使います。
コンポーネント側で独自の状態型を定義しないでください。

## データ取得（hooks/useBoard.ts）

- 初回マウント時に `GET /api/board` を取得する。失敗時は `ErrorResponse.detail` か `error` をメッセージにする。
- `EventSource("/api/events")` を購読する。
  - `onopen` で `live = true`、`onerror` で `live = false`
  - `{"type":"update"}` を受けたら 120ms デバウンスして再取得
- `reload()` は進行中のリクエストを `AbortController` で中断してから再取得する（ヘッダーの「再読込」ボタン）。
- 戻り値は `{ data, error, updatedAt, live, reload }`。`error` があっても `data` が残っていれば
  画面は古い内容を表示しつつ警告を出す。

## 画面構成（App.tsx）

3 つのビューを切り替えます。

| ビュー     | 内容                                                          |
| ---------- | ------------------------------------------------------------- |
| ボード     | チケットカードのグリッド。説明の開閉、タスク行の開閉          |
| タスク一覧 | 全タスクの表（チケット / タスク / 状態 / 依存 / 後続 / 説明） |
| 集計       | チケット状態の内訳、実行可能タスク一覧、チケット別進捗バー    |

ヘッダーには次を置きます。

- DB パス（`data.dbPath`）と SSE の接続状態（「ライブ」/「オフライン」）
- ビュー切り替え（ボード / タスク一覧 / 集計）と「再読込」
- チケット状態フィルタ（すべて / 進行中 / 未着手 / 完了 / アーカイブ、件数付き）と検索ボックス
  - 検索はタイトル・uid・説明・タスクのタイトル / uid を対象にする

取得に失敗して `data` が無い場合は、DB パスの指定方法（`bun run start --db ...`）を案内するエラーカードを出します。

## コンポーネント

### TicketCard.tsx

チケット 1 件のカードです。

- 進捗率は `(completed + canceled) / total`。バッジはチケット状態。
- `counts.notYet > 0 && executableCount === 0` を **「依存異常?」** として警告表示する
  （循環や誤った依存の疑い。スキルの「step 3 が空なのに未着手が残る」状態に対応）。
- タスクは `TaskItem` を並べ、クリックで説明を開閉する。

### TaskItem.tsx

タスク 1 行です。

- `state !== 'not_yet'` のタスクは `opacity-70` で淡く表示する。
- `executable` が真なら `ring-1 ring-sky-500/30` で強調する（次に着手できるタスク）。

### StateBadge.tsx

`TicketState` / `TaskState` の日本語ラベルと色（バッジ）を定義します。状態を追加したら
`src/shared/types.ts` と併せてここも更新してください。

### Markdown.tsx

完全な Markdown パーサは入れず、スキルの説明文で使う記法だけを扱う軽量レンダラです。

- 見出し（`#`〜`######`）、箇条書き（`-` / `*`）、コードブロック（``）、インラインコード（` ` ``）
- 上記以外（強調・リンクなど）はプレーンテキストとして表示する

## スタイル

Tailwind CSS v4 を `bun-plugin-tailwind` 経由で処理します。`styles.css` は `@import "tailwindcss"` と
ダークテーマ（`color-scheme: dark`、背景 `slate-950`）の最小設定のみです。
`src/client/index.html` は `./styles.css` と `./frontend.tsx` を相対パスで参照します。

## 開発

```bash
bun run dev     # HMR 付きで起動（既定 http://localhost:3000）
bun run build   # dist/ に静的ファイルを出力
```

静的ビルドの出力は `Bun.serve` を通さないため、API（`/api/board`・`/api/events`）は別途必要です。
通常は `bun run dev` / `bun run start` を使ってください。
