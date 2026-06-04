{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.programs.pi-coding-agent;
  env =
    lib.optionalAttrs cfg.skipVersionCheck { PI_SKIP_VERSION_CHECK = "1"; }
    // lib.optionalAttrs cfg.offline { PI_OFFLINE = "1"; };
  wrapperArgs = lib.concatLists (
    lib.mapAttrsToList (name: value: [
      "--set"
      name
      value
    ]) env
  );
  wrappedPi = pkgs.symlinkJoin {
    name = "pi-coding-agent-wrapped";
    paths = [ pkgs.pi-coding-agent ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/pi ${lib.escapeShellArgs wrapperArgs}
    '';
  };
in
{
  options.programs.pi-coding-agent = {
    skipVersionCheck = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Skip pi's startup version check (sets PI_SKIP_VERSION_CHECK=1).
        Enabled by default because pi is pinned via nixpkgs and cannot
        self-update inside the sandbox, so the check is an unactionable nag.
      '';
    };
    offline = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Disable pi's startup network operations — update checks, package-update
        checks, and install/update telemetry (sets PI_OFFLINE=1).
        Does not affect pi's normal model/API traffic.
      '';
    };
  };

  config.environment.systemPackages = [
    (if env == { } then pkgs.pi-coding-agent else wrappedPi)
  ];
}
