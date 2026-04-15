{ nixpkgs, system }:
let
  pkgs = nixpkgs.legacyPackages.${system};
  overlay = final: _prev: {
    ralphex = final.callPackage ./pkgs/ralphex.nix { };
    revdiff = final.callPackage ./pkgs/revdiff.nix { };
  };
  nixos = nixpkgs.lib.nixosSystem {
    modules = [
      {
        nixpkgs.hostPlatform = system;
        nixpkgs.overlays = [ overlay ];
      }
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
