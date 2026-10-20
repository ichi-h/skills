# task-management viewer

`task-management` スキルが管理する SQLite DB（`.&lt;ユーザー名&gt;/issues.db`）をブラウザで閲覧するためのビューアです。
Bun + React + Tailwind CSS で動作し、**閲覧専用**（DB への書き込みは一切行いません）。

## 特徴

- チケット / タスク / 依存関係をボード・一覧・集計の 3 ビューで表示
- タスクの依存関係と「実行可能（依存がすべて完了・中止済み）」を判定して強調
- 未着手タスクがあるのに実行可能タスクが 0 件のチケットを「依存異常?」として警告
- DB ファイル（および WAL/SHM）の変更を `fs.watch` で監視し、Server-Sent Events で画面を自動更新
- 依存パッケージは React のみ。DB は Bun 内蔵の `bun:sqlite` で読み取り専用オープン
- Nix flake を同梱。Tailwind の処理済みアセットを埋め込んだ**単一バイナリ**としてインストール可能

## Nix でのインストール

flake を提供しているので、clone せずに直接インストールできます。

```bash
# 1. すぐ試す（インストールせずに起動）
nix run github:ichi-h/skills -- --db /path/to/.<user>/issues.db

# 2. プロファイルにインストール
nix profile install github:ichi-h/skills
task-management-viewer --db /path/to/.<user>/issues.db
```

サブコマンド名は `default` / `viewer`（`nix run github:ichi-h/skills#viewer`）です。
リポジトリ名を変更した場合は、上記 URL を新しい名前に置き換えてください。
ローカルに clone 済みなら `nix run . -- --db ...`、`nix profile install .` でも同じです。

ビルドだけ行う場合:

```bash
nix build github:ichi-h/skills
./result/bin/task-management-viewer --db /path/to/.<user>/issues.db
```

### オプション

| 指定方法 | 内容 |
| --- | --- |
| `--db <path>` / `-d <path>` | 閲覧する DB を指定（`--db` より後ろの引数、または非オプション引数も可） |
| `ISSUES_DB` 環境変数 | `--db` を省略したときの DB パス |
| `PORT` 環境変数 | 待ち受けポート（既定 `3000`） |
| 指定なし | `$(pwd)/.<ユーザー名>/issues.db`（スキルの既定値） |

```bash
task-management-viewer --db ~/work/project/.ichi/issues.db        # DB を明示
PORT=8080 task-management-viewer --db ./issues.db                  # ポート変更
ISSUES_DB=./issues.db task-management-viewer                       # 環境変数で指定
```

どちらも指定しない場合はカレントディレクトリの `.<ユーザー名>/issues.db` を読むため、
スキルを使って作業しているプロジェクトのルートで起動するとそのまま表示できます。

### home-manager / NixOS での常駐

`systemd` のユーザーサービスとして常駐させる例です（home-manager）。

```nix
{
  inputs.task-management.url = "github:ichi-h/skills";  # リポジトリ名を変えたら合わせて変更

  # home-manager のモジュール内
  home.packages = [ inputs.task-management.packages.${pkgs.system}.default ];

  systemd.user.services.task-management-viewer = {
    Unit.Description = "task-management viewer";
    Service = {
      ExecStart = "${inputs.task-management.packages.${pkgs.system}.default}/bin/task-management-viewer --db %h/work/project/.ichi/issues.db";
      Environment = [ "PORT=3000" ];
      Restart = "on-failure";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
```

`overlays.default` も公開しているので、`pkgs.task-management-viewer` として使うこともできます。

### 開発シェル

```bash
nix develop        # bun と sqlite3 が入ったシェル
nix fmt            # nixfmt で整形
nix flake check    # 評価チェック
```

## Bun での起動（Nix を使わない場合）

```bash
bun install

# DB を明示指定
bun run dev --db /path/to/.<user>/issues.db

# 既定値（$(pwd)/.<ユーザー名>/issues.db）を使う
bun run dev

# 本番相当（HMR なし）
NODE_ENV=production bun run start --db /path/to/.<user>/issues.db
```

bun が入っていない環境では `nix run nixpkgs#bun -- install` のように nix 経由でも実行できます。

## スクリプト

| コマンド | 内容 |
| --- | --- |
| `bun run dev` | 開発サーバー（`--hot` による HMR） |
| `bun run start` | 本番相当で起動 |
| `bun run build` | `dist/` に静的ファイルを出力（静的ホスティング用。`scripts/build.ts` が Tailwind を処理） |
| `bun run compile` | 単一バイナリを `build/task-management-viewer` に出力（Nix パッケージと同じ処理） |
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
scripts/compile.ts       単一バイナリのビルド（Nix からも利用）
nix/package.nix          本体の導出（deps を固定出力導出から持ち込んでオフラインビルド）
nix/deps.nix             node_modules を取得する固定出力導出
nix/deps.hash            deps.nix の出力ハッシュ
flake.nix                packages / apps / devShells / overlay / checks
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

## Nix パッケージのメンテナンス

`bun.lock` の依存が変わったら `nix/deps.hash` を更新します。

```bash
rm -f nix/deps.hash
nix build .#deps --no-link 2>&1 | grep 'got:'
# 表示されたハッシュを nix/deps.hash に書き込む
echo 'sha256-...=' > nix/deps.hash
nix build .# --no-link   # 本体もビルドできることを確認
```

`nix/deps.nix` は `bun install --ignore-scripts` で依存を取得します（npm 版 `bun` パッケージの
postinstall がバイナリをダウンロードするため）。実行に使う bun は Nix 側の `pkgs.bun` です。
