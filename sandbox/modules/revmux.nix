{ pkgs, ... }:
{
  programs.claude-code.plugins = [ pkgs.revmux-plugin ];

  environment.systemPackages = [ pkgs.revmux ];
}
