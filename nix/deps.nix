{
  lib,
  stdenvNoCC,
  bun,
  hashFile ? ./deps.hash,
}:
# package.json / bun.lock から node_modules を取得する固定出力導出。
#
# Nix のビルドサンドボックスにはネットワークが無いため、依存の取得だけを
# 固定出力導出（FOD）に隔離する。ここだけがネットワークを使い、
# 本体のビルドはオフラインで再現できる。
#
# 依存を更新したら次の手順でハッシュを更新する:
#   rm -f nix/deps.hash
#   nix build .#deps 2>&1 | grep 'got:'   # 表示されたハッシュを nix/deps.hash に書く
stdenvNoCC.mkDerivation {
  pname = "task-management-viewer-deps";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ../.;
    filter =
      path: type:
      builtins.elem (baseNameOf path) [
        "package.json"
        "bun.lock"
        "bunfig.toml"
      ];
  };

  nativeBuildInputs = [ bun ];

  dontConfigure = true;
  dontFixup = true;

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    export BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
    # `bun` パッケージ（npm 版）の postinstall はバイナリをダウンロードするため無効化する。
    # 実行に使う bun は Nix 側の pkgs.bun で、node_modules 内の bun は不要。
    bun install --frozen-lockfile --no-progress --backend copyfile --ignore-scripts
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r node_modules "$out/node_modules"
    runHook postInstall
  '';

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash =
    if builtins.pathExists hashFile then
      lib.removeSuffix "\n" (builtins.readFile hashFile)
    else
      lib.fakeHash;
}
