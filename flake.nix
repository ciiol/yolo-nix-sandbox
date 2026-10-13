{
  description = "Yolo sandbox - bubblewrap-based NixOS sandbox";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
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
          craneLib = crane.mkLib pkgs;
          inherit (import ./sandbox { inherit nixpkgs system; }) env;
          commonArgs = {
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [
                ./Cargo.toml
                ./Cargo.lock
                ./src
              ];
            };
            strictDeps = true;
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        {
          inherit
            pkgs
            craneLib
            env
            commonArgs
            cargoArtifacts
            ;
        }
      );
    in
    {
      packages = forAllSystems (
        system:
        let
          inherit (perSystem.${system})
            pkgs
            craneLib
            env
            commonArgs
            cargoArtifacts
            ;
          yolo-unwrapped = craneLib.buildPackage (
            commonArgs
            // {
              inherit cargoArtifacts;
              doCheck = false;
            }
          );
          yolo =
            pkgs.runCommand "yolo-${yolo-unwrapped.version}"
              {
                nativeBuildInputs = [ pkgs.makeWrapper ];
                meta.mainProgram = "yolo";
              }
              ''
                makeWrapper ${yolo-unwrapped}/bin/yolo $out/bin/yolo \
                  --inherit-argv0 \
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

      checks = forAllSystems (
        system:
        let
          inherit (perSystem.${system})
            craneLib
            commonArgs
            cargoArtifacts
            ;
        in
        {
          formatting = (treefmtEval nixpkgs.legacyPackages.${system}).config.build.check self;
          yolo = self.packages.${system}.default;
          yolo-test = craneLib.cargoTest (commonArgs // { inherit cargoArtifacts; });
          yolo-clippy = craneLib.cargoClippy (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            }
          );
        }
      );

      devShells = forAllSystems (
        system:
        let
          inherit (perSystem.${system}) pkgs craneLib env;
          pythonWithPackages = pkgs.python3.withPackages (ps: [
            ps.pytest
          ]);
        in
        {
          default = craneLib.devShell {
            packages = [
              pkgs.direnv
              pkgs.just
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
