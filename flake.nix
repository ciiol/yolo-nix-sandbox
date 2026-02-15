{
  description = "Yolo sandbox - bubblewrap-based NixOS sandbox";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    llm-agents.url = "github:numtide/llm-agents.nix";
    llm-agents.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      llm-agents,
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
            mypy = {
              enable = true;
              directories."tests" = {
                directory = "tests";
                extraPythonPackages = [ pkgs.python3Packages.pytest ];
              };
            };
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
                    # TODO: remove once https://github.com/NixOS/nixpkgs/pull/486323 is resolved
                    inherit (llm-agents.packages.${system}) codex;
                    ralphex = final.callPackage ./pkgs/ralphex.nix { };
                  })
                ];
              }
              ./sandbox.nix
            ];
          };

          sandboxProfile = sandboxConfig.config.system.path;
          sandboxEtc = sandboxConfig.config.system.build.etc;

          sandbox-entrypoint = pkgs.writeShellApplication {
            name = "sandbox-entrypoint";
            text = builtins.readFile ./entrypoint.bash;
          };

          yolo = pkgs.writeShellApplication {
            name = "yolo";
            runtimeInputs = [ pkgs.bubblewrap ];
            text =
              builtins.replaceStrings
                [ "@SANDBOX_PROFILE@" "@SANDBOX_ETC@" "@SANDBOX_ENTRYPOINT@" ]
                [ "${sandboxProfile}" "${sandboxEtc}" "${sandbox-entrypoint}" ]
                (builtins.readFile ./yolo.bash);
          };
        in
        {
          default = yolo;
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
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.just
              pythonWithPackages
            ];
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
