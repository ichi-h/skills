{
  description = "task-management";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "power-manager";
            version = "0.1.0";
            src = self;
            nativeBuildInputs = [
              pkgs.bun
              pkgs.makeWrapper
            ];
            buildPhase = ''
              export HOME="$TMPDIR"
              bun install --frozen-lockfile
              bun build --compile --target=bun-linux-${
                if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "x64"
              } --outfile power-manager src/index.ts
            '';
            installPhase = ''
              install -Dm755 power-manager $out/bin/power-manager
              wrapProgram $out/bin/power-manager --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.openssh ]}
            '';
          };
        }
      );
      nixosModules.default = import ./nix/module.nix self;
    };
}
