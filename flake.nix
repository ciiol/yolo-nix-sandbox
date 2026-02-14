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
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      sandboxConfig = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
            nixpkgs.overlays = [
              (final: _prev: {
                # TODO: remove once https://github.com/NixOS/nixpkgs/pull/486323 is resolved
                inherit (llm-agents.packages.${final.system}) codex;
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

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
          shfmt.enable = true;
          shellcheck.enable = true;
          deadnix.enable = true;
          statix.enable = true;
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

      pythonWithPackages = pkgs.python3.withPackages (ps: [
        ps.pytest
      ]);
    in
    {
      packages.${system} = {
        inherit sandboxProfile sandboxEtc;
        default = yolo;
      };

      formatter.${system} = treefmtEval.config.build.wrapper;

      checks.${system} = {
        formatting = treefmtEval.config.build.check self;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          yolo
          pkgs.bubblewrap
          pkgs.just
          pythonWithPackages
          pkgs.ruff
        ];
      };
    };
}
