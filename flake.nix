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
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          sandboxConfig = nixpkgs.lib.nixosSystem {
            modules = [
              {
                nixpkgs.hostPlatform = system;
                nixpkgs.overlays = [
                  (final: _prev: {
                    ralphex = final.callPackage ./sandbox/pkgs/ralphex.nix { };
                  })
                ];
              }
              ./sandbox
            ];
          };

          sandboxProfile = sandboxConfig.config.system.path;
          sandboxEtc = sandboxConfig.config.system.build.etc;

          sandbox-entrypoint = pkgs.writeShellApplication {
            name = "sandbox-entrypoint";
            text = builtins.readFile ./sandbox/entrypoint.bash;
          };

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
            env = {
              SANDBOX_PROFILE = "${sandboxProfile}";
              SANDBOX_ETC = "${sandboxEtc}";
              SANDBOX_ENTRYPOINT = "${sandbox-entrypoint}";
            };
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postInstall = ''
              wrapProgram $out/bin/yolo \
                --prefix PATH : ${
                  pkgs.lib.makeBinPath [
                    pkgs.bubblewrap
                    pkgs.direnv
                    pkgs.util-linux
                  ]
                }
            '';
          };
        in
        {
          default = yolo;
          inherit yolo;
        }
      );

      formatter = forAllSystems (
        system: (treefmtEval nixpkgs.legacyPackages.${system}).config.build.wrapper
      );

      checks = forAllSystems (system: {
        formatting = (treefmtEval nixpkgs.legacyPackages.${system}).config.build.check self;
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pythonWithPackages = pkgs.python3.withPackages (ps: [
            ps.pytest
          ]);
          sandboxConfig = nixpkgs.lib.nixosSystem {
            modules = [
              {
                nixpkgs.hostPlatform = system;
                nixpkgs.overlays = [
                  (final: _prev: {
                    ralphex = final.callPackage ./sandbox/pkgs/ralphex.nix { };
                  })
                ];
              }
              ./sandbox
            ];
          };
          sandboxProfile = sandboxConfig.config.system.path;
          sandboxEtc = sandboxConfig.config.system.build.etc;
          sandbox-entrypoint = pkgs.writeShellApplication {
            name = "sandbox-entrypoint";
            text = builtins.readFile ./sandbox/entrypoint.bash;
          };
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
            env = {
              SANDBOX_PROFILE = "${sandboxProfile}";
              SANDBOX_ETC = "${sandboxEtc}";
              SANDBOX_ENTRYPOINT = "${sandbox-entrypoint}";
            };
          };
        }
      );

      homeManagerModules.default =
        { lib, pkgs, ... }:
        {
          imports = [ ./modules/home-manager.nix ];
          programs.yolo.package = lib.mkDefault self.packages.${pkgs.system}.default;
        };
    };
}
