{
  description = "task-management-viewer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          depsDrv = pkgs.callPackage ./nix/deps.nix { };
        in
        rec {
          task-management-viewer = pkgs.callPackage ./nix/package.nix { deps = depsDrv; };
          # 依存だけを取得する導出（nix/deps.hash の更新用）
          deps = depsDrv;
          default = task-management-viewer;
        }
      );

      apps = forAllSystems (
        pkgs:
        let
          viewer = "${
            self.packages.${pkgs.stdenv.hostPlatform.system}.task-management-viewer
          }/bin/task-management-viewer";
        in
        {
          default = {
            type = "app";
            program = viewer;
            meta.description = "task-management-viewer を起動する（--db <issues.db> で DB を指定）";
          };
          viewer = {
            type = "app";
            program = viewer;
          };
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.bun
            pkgs.sqlite
          ];
          shellHook = ''
            echo "bun $(bun --version) / sqlite $(sqlite3 --version | cut -d' ' -f1)"
          '';
        };
      });

      overlays.default = final: prev: {
        task-management-viewer = final.callPackage ./nix/package.nix {
          deps = final.callPackage ./nix/deps.nix { };
        };
      };

      checks = forAllSystems (pkgs: {
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.task-management-viewer;
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
