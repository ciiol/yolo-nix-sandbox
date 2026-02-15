{ config, lib, ... }:
let
  cfg = config.programs.yolo;
in
{
  options.programs.yolo = {
    enable = lib.mkEnableOption "yolo sandbox";
    package = lib.mkOption {
      type = lib.types.package;
      description = "The yolo package to install.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
