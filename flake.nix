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
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      src = ./.;

      sandboxConfig = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
            boot.isContainer = true;

            environment.systemPackages = with pkgs; [
              coreutils
              bashInteractive
              gnugrep
              gnused
              findutils
              git
              nix
              cacert
              curl
            ];

            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];

            system.stateVersion = "26.05";
          }
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
