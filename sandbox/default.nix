{ nixpkgs, system }:
let
  pkgs = nixpkgs.legacyPackages.${system};
  overlay = final: _prev: {
    ralphex = final.callPackage ./pkgs/ralphex.nix { };
    ralphex-plugin = final.callPackage ./pkgs/ralphex-plugin.nix { };
    revdiff = final.callPackage ./pkgs/revdiff.nix { };
    revdiff-plugin = final.callPackage ./pkgs/revdiff-plugin.nix { };
    revdiff-planning-plugin = final.callPackage ./pkgs/revdiff-planning-plugin.nix { };
  };
  nixos = nixpkgs.lib.nixosSystem {
    modules = [
      {
        nixpkgs.hostPlatform = system;
        nixpkgs.overlays = [ overlay ];
      }
      ./modules/claude-code.nix
      ./modules/codex.nix
      ./modules/ralphex.nix
      ./modules/revdiff.nix
      ./configuration.nix
    ];
  };
  entrypoint = pkgs.writeShellApplication {
    name = "sandbox-entrypoint";
    text = builtins.readFile ./entrypoint.bash;
  };
in
{
  env = {
    SANDBOX_PROFILE = "${nixos.config.system.path}";
    SANDBOX_ETC = "${nixos.config.system.build.etc}";
    SANDBOX_ENTRYPOINT = "${entrypoint}";
  };
}
