{ pkgs, ... }:
{
  programs.claude-code.plugins = [ pkgs.ralphex-plugin ];

  environment.systemPackages = [ pkgs.ralphex ];
}
