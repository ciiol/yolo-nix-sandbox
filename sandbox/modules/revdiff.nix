{ pkgs, ... }:
{
  programs.claude-code.plugins = [
    pkgs.revdiff-plugin
  ];

  environment.systemPackages = [ pkgs.revdiff ];
}
