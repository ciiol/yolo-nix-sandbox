{
  description = "Yolo sandbox - bubblewrap-based NixOS sandbox";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      treefmtEval =
        pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs = {
            nixfmt.enable = true;
            shfmt.enable = true;
            shellcheck.enable = true;
            deadnix.enable = true;
            statix.enable = true;
            mdformat.enable = true;
            ruff-check.enable = true;
            ruff-format.enable = true;
            rustfmt.enable = true;
          };
        };

      perSystem = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (import ./sandbox { inherit nixpkgs system; }) env;
        in
        {
          inherit pkgs env;
        }
      );
    in
    {
      packages = forAllSystems (
        system:
        let
          inherit (perSystem.${system}) pkgs env;
          yolo = pkgs.rustPlatform.buildRustPackage {
            pname = "yolo";
            version = "0.1.0";
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [
                ./Cargo.toml
                ./Cargo.lock
                ./src
              ];
            };
            cargoLock.lockFile = ./Cargo.lock;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postInstall = ''
              wrapProgram $out/bin/yolo \
                --prefix PATH : ${
                  pkgs.lib.makeBinPath [
                    pkgs.bubblewrap
                    pkgs.direnv
                    pkgs.util-linux
                  ]
                } \
                --set SANDBOX_PROFILE "${env.SANDBOX_PROFILE}" \
                --set SANDBOX_ETC "${env.SANDBOX_ETC}" \
                --set SANDBOX_ENTRYPOINT "${env.SANDBOX_ENTRYPOINT}" \
                --set SANDBOX_USRBINENV "${env.SANDBOX_USRBINENV}"
            '';
          };

          ralphex = pkgs.callPackage ./sandbox/pkgs/ralphex.nix { };
          revdiff = pkgs.callPackage ./sandbox/pkgs/revdiff.nix { };
        in
        {
          default = yolo;
          inherit yolo ralphex revdiff;
        }
      );

      formatter = forAllSystems (
        system: (treefmtEval nixpkgs.legacyPackages.${system}).config.build.wrapper
      );

      checks = forAllSystems (system: {
        formatting = (treefmtEval nixpkgs.legacyPackages.${system}).config.build.check self;
        yolo = self.packages.${system}.default;
      });

      devShells = forAllSystems (
        system:
        let
          inherit (perSystem.${system}) pkgs env;
          pythonWithPackages = pkgs.python3.withPackages (ps: [
            ps.pytest
          ]);
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.cargo
              pkgs.clippy
              pkgs.direnv
              pkgs.just
              pkgs.rustc
              pkgs.rustfmt
              pythonWithPackages
            ];
            inherit env;
          };
        }
      );

      homeModules.default =
        { lib, pkgs, ... }:
        {
          imports = [ ./modules/home-manager.nix ];
          programs.yolo.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
    };
}
