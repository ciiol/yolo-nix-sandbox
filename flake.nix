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
      src = ./.;

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

      yolo = pkgs.writeShellApplication {
        name = "yolo";
        runtimeInputs = [ pkgs.bubblewrap ];
        text =
          builtins.replaceStrings
            [ "@SANDBOX_PROFILE@" "@SANDBOX_ETC@" ]
            [ "${sandboxProfile}" "${sandboxEtc}" ]
            (builtins.readFile ./yolo.sh);
      };

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.shfmt.enable = true;
      };
    in
    {
      packages.${system} = {
        inherit sandboxProfile sandboxEtc;
        default = yolo;
      };

      formatter.${system} = treefmtEval.config.build.wrapper;

      checks.${system} = {
        formatting = treefmtEval.config.build.check self;

        shellcheck = pkgs.runCommand "check-shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
          cd ${src}
          shellcheck --shell=bash yolo.sh tests/test-poc.sh
          touch $out
        '';

        deadnix = pkgs.runCommand "check-deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
          cd ${src}
          deadnix --fail .
          touch $out
        '';

        statix = pkgs.runCommand "check-statix" { nativeBuildInputs = [ pkgs.statix ]; } ''
          cd ${src}
          statix check .
          touch $out
        '';
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          yolo
          pkgs.bubblewrap
          pkgs.just
        ];
      };
    };
}
