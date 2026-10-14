{ lib, hostConfig, ... }:
let
  # Builds go to the host daemon, so nix.conf should report what it can build
  # (e.g. aarch64-linux via the host's boot.binfmt.emulatedSystems).
  mirroredNixSettings = [
    "extra-platforms"
    "system-features"
    "extra-system-features"
  ];
  hostNixSettings = if hostConfig == null then { } else hostConfig.nix.settings;
in
{
  # NixOS also defines system-features at normal priority in its config, so a
  # plain definition would be appended to the sandbox's list instead of replacing it.
  nix.settings = lib.mapAttrs (_: lib.mkForce) (
    lib.filterAttrs (name: _: lib.elem name mirroredNixSettings) hostNixSettings
  );
}
