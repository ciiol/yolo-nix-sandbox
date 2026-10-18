{ config, lib, ... }:
let
  cfg = config.programs.yolo;
  hmGit = config.programs.git;
  # Home Manager renders list-form settings (26.05+) after iniContent instead
  # of merging them into it, so their values override iniContent's. The
  # settings option only exists since 25.11, and iniContent has no value while
  # programs.git is disabled.
  hmGitFragments = lib.optionals hmGit.enable (
    [ hmGit.iniContent ] ++ lib.optionals (lib.isList (hmGit.settings or { })) hmGit.settings
  );
  hmGitIdentity = lib.foldl' (
    identity: fragment:
    identity
    // lib.filterAttrs (
      name: _:
      lib.elem name [
        "name"
        "email"
      ]
    ) (fragment.user or { })
  ) { } hmGitFragments;
in
{
  options.programs.yolo = {
    enable = lib.mkEnableOption "yolo sandbox";
    package = lib.mkOption {
      type = lib.types.package;
      description = "The yolo package to install.";
    };
    git = {
      settings = lib.mkOption {
        type =
          with lib.types;
          let
            gitini = attrsOf (attrsOf anything);
          in
          either gitini (listOf gitini);
        default = lib.optionalAttrs (hmGitIdentity != { }) {
          user = hmGitIdentity;
        };
        defaultText = lib.literalMD "`user.name` and `user.email` from {option}`programs.git`";
        example = lib.literalExpression ''
          {
            inherit (config.programs.git.iniContent) user gpg commit tag init pull;
          }
        '';
        description = ''
          Git configuration written to the sandbox's {file}`/etc/gitconfig`,
          which Git reads before the sandbox's {file}`~/.config/git/config`.
          Setting this option replaces the default. A list renders its
          fragments in order instead of merging them.
        '';
      };
      ignores = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = lib.optionals hmGit.enable hmGit.ignores;
        defaultText = lib.literalExpression "lib.optionals config.programs.git.enable config.programs.git.ignores";
        description = ''
          Ignore patterns for the sandbox's Git. A non-empty list is written to
          a file that {file}`/etc/gitconfig` sets as `core.excludesFile`, which
          replaces Git's default of {file}`$XDG_CONFIG_HOME/git/ignore`.
        '';
      };
      attributes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = lib.optionals hmGit.enable hmGit.attributes;
        defaultText = lib.literalExpression "lib.optionals config.programs.git.enable config.programs.git.attributes";
        description = "Git attributes written to the sandbox's {file}`/etc/gitattributes`.";
      };
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
