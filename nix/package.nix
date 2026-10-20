{
  lib,
  stdenvNoCC,
  bun,
  makeWrapper,
  sqlite,
  deps,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "task-management-viewer";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ../.;
    filter =
      path: type:
      let
        base = baseNameOf path;
        relative = lib.removePrefix (toString ../. + "/") (toString path);
      in
      !(
        builtins.elem base [
          ".git"
          "node_modules"
          "dist"
          "build"
          "result"
        ]
        || lib.hasPrefix ".direnv" base
        || lib.hasSuffix ".db" relative
        || lib.hasSuffix ".db-wal" relative
        || lib.hasSuffix ".db-shm" relative
      );
  };

  nativeBuildInputs = [
    bun
    makeWrapper
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    # 依存は固定出力の導出から持ち込む（この段階ではネットワークを使わない）
    rm -rf node_modules
    ln -s ${deps}/node_modules node_modules
    bun run scripts/compile.ts --outfile task-management-viewer
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 task-management-viewer "$out/bin/task-management-viewer"
    # sqlite3 は必須ではないが、案内やデバッグ用に同梱する
    wrapProgram "$out/bin/task-management-viewer" \
      --prefix PATH : ${lib.makeBinPath [ sqlite ]}
    runHook postInstall
  '';

  meta = {
    description = "task-management スキルの SQLite DB をブラウザで閲覧するビューア";
    mainProgram = "task-management-viewer";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
