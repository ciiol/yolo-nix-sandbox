{ pkgs, ... }:
let
  # Codex v0.115.0+ uses bwrap internally, which rejects non-zero ambient caps.
  # In wide-UID mode yolo grants CAP_SETUID/CAP_SETGID inside the sandbox,
  # so we must clear them before codex spawns its own bwrap.
  codex-wrapped = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      exec ${pkgs.util-linux}/bin/setpriv --ambient-caps -all -- ${pkgs.codex}/bin/codex "$@"
    '';
  };
in
{
  environment.systemPackages = [ codex-wrapped ];
}
