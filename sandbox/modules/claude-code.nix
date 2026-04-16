{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.programs.claude-code;
  pluginArgs = lib.concatMapStringsSep " " (p: "--plugin-dir ${p}") cfg.plugins;
  wrappedClaude = pkgs.symlinkJoin {
    name = "claude-code";
    paths = [ pkgs.claude-code ];
    postBuild = ''
      mv $out/bin/claude $out/bin/.claude-wrapped
      cat > $out/bin/claude <<EOF
      #! ${pkgs.bash}/bin/bash -e
      exec -a "\$0" "$out/bin/.claude-wrapped" ${pluginArgs} "\$@"
      EOF
      chmod +x $out/bin/claude
    '';
  };
in
{
  options.programs.claude-code = {
    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Plugin directories to pass to claude via --plugin-dir";
    };
  };

  config = {
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "claude-code" ];

    environment.systemPackages = [
      (if cfg.plugins != [ ] then wrappedClaude else pkgs.claude-code)
    ];
  };
}
