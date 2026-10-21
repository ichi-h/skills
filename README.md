# task-management

チケット（課題）・タスク・依存関係を SQLite で管理し、開発作業を順序立てて進めるためのエージェントスキルです。
本体はスキル（[`skills/task-management/SKILL.md`](skills/task-management/SKILL.md)）で、`task-management-viewer` は
そのスキルが書き込む DB を閲覧する補助ツールです（読み取り専用）。

## スキル

```bash
npx skills add ichi-h/task-management
```

エージェントに依頼すると読み込まれます。

```text
この課題をチケット化して、タスクに分解して進めて
```

状態は `$(pwd)/.<ユーザー名>/issues.db` に保存されます。スキーマと運用手順は
[`SKILL.md`](skills/task-management/SKILL.md)（日本語版は [`SKILL.ja.md`](skills/task-management/SKILL.ja.md)）を参照。

## task-management viewer

DB をボード・タスク一覧・集計の 3 ビューで表示し、DB の変更に自動追従します。

```bash
nix run github:ichi-h/task-management -- --db /path/to/.<user>/issues.db
```

`--db` を省略するとカレントディレクトリの `.<ユーザー名>/issues.db` を読みます（`PORT` で待ち受けポートを変更可）。

### home-manager

flake input として取り込み、overlay 経由で `pkgs.task-management-viewer` を入れます。

```nix
{
  inputs.task-management = {
    url = "github:ichi-h/task-management";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

```nix
{ inputs, pkgs, ... }:
{
  nixpkgs.overlays = [ inputs.task-management.overlays.default ];
  home.packages = [ pkgs.task-management-viewer ];
}
```

## ドキュメント

- [`docs/architecture.md`](docs/architecture.md): 全体構成・データの流れ・Nix パッケージング
- [`src/README.md`](src/README.md): サーバー（API・SSE・ファイル監視）とビルド
- [`src/client/README.md`](src/client/README.md): フロントエンド

## ライセンス

MIT（[`LICENSE`](LICENSE)）
